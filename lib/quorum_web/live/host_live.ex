defmodule QuorumWeb.HostLive do
  @moduledoc """
  The lecturer's console: the ranked queue with spotlight, answer, and hide, a
  live view of what's on the projection, and keyboard shortcuts for driving it
  without the mouse.
  """
  use QuorumWeb, :live_view

  alias Quorum.Sessions

  @impl true
  def mount(%{"host_token" => token}, _session, socket) do
    case Sessions.get_room_by_host_token(token) do
      {:ok, %{} = room} ->
        if connected?(socket), do: Sessions.subscribe(room.id)

        socket =
          socket
          |> assign(
            room: room,
            search: "",
            selected_id: nil,
            confirming_close: false,
            page_title: room.name
          )
          |> load()

        {:ok, socket}

      _ ->
        {:ok, assign(socket, room: nil, page_title: "Host")}
    end
  end

  @impl true
  def handle_info(_message, %{assigns: %{room: nil}} = socket), do: {:noreply, socket}
  def handle_info(_message, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("search", %{"value" => value}, socket),
    do: {:noreply, socket |> assign(search: value) |> load()}

  def handle_event("spotlight", %{"id" => id}, socket) do
    Sessions.spotlight(socket.assigns.room, id)
    {:noreply, socket}
  end

  def handle_event("clear_spotlight", _params, socket) do
    Sessions.clear_spotlight(socket.assigns.room)
    {:noreply, socket}
  end

  def handle_event("answer", %{"id" => id}, socket), do: act(socket, id, &Sessions.answer/1)
  def handle_event("hide", %{"id" => id}, socket), do: act(socket, id, &Sessions.hide/1)
  def handle_event("restore", %{"id" => id}, socket), do: act(socket, id, &Sessions.restore/1)

  def handle_event("confirm_close", _params, socket),
    do: {:noreply, assign(socket, confirming_close: true)}

  def handle_event("cancel_close", _params, socket),
    do: {:noreply, assign(socket, confirming_close: false)}

  def handle_event("close", _params, socket) do
    Sessions.close_room(socket.assigns.room)
    {:noreply, socket |> assign(confirming_close: false) |> load()}
  end

  def handle_event("select", %{"id" => id}, socket),
    do: {:noreply, assign(socket, selected_id: id)}

  # Escape cancels the dialog, and the queue shortcuts stay quiet while it's open.
  def handle_event("key", %{"key" => "Escape"}, socket),
    do: {:noreply, assign(socket, confirming_close: false)}

  def handle_event("key", _params, %{assigns: %{confirming_close: true}} = socket),
    do: {:noreply, socket}

  def handle_event("key", %{"key" => key}, socket) do
    ids = Enum.map(socket.assigns.waiting, & &1.id)
    selected = socket.assigns.selected_id

    case key do
      k when k in ["j", "J", "ArrowDown"] ->
        {:noreply, assign(socket, selected_id: step(ids, selected, +1))}

      k when k in ["k", "K", "ArrowUp"] ->
        {:noreply, assign(socket, selected_id: step(ids, selected, -1))}

      "Enter" ->
        if selected, do: Sessions.spotlight(socket.assigns.room, selected)
        {:noreply, socket}

      k when k in ["a", "A"] ->
        maybe(selected, &Sessions.answer/1)
        {:noreply, socket}

      k when k in ["h", "H"] ->
        maybe(selected, &Sessions.hide/1)
        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  defp maybe(nil, _fun), do: :ok

  defp maybe(id, fun) do
    case Sessions.get_question(id) do
      {:ok, question} -> fun.(question)
      _ -> :ok
    end
  end

  defp act(socket, id, fun) do
    with {:ok, question} <- Sessions.get_question(id), do: fun.(question)
    {:noreply, socket}
  end

  defp load(socket) do
    room_id = socket.assigns.room.id
    {:ok, room} = Sessions.get_room(room_id)
    questions = Sessions.list_questions(room_id)
    %{visible: visible, answered: answered} = Sessions.partition(questions)

    waiting =
      case String.trim(socket.assigns.search) do
        "" ->
          visible

        term ->
          Enum.filter(visible, &String.contains?(String.downcase(&1.body), String.downcase(term)))
      end

    connected = room_id |> Sessions.topic() |> QuorumWeb.Presence.list() |> map_size()
    selected = keep_selected(socket.assigns.selected_id, Enum.map(waiting, & &1.id))

    assign(socket,
      room: room,
      spotlight: room.spotlight_question,
      waiting: waiting,
      visible_count: length(visible),
      answered: answered,
      question_count: length(visible) + length(answered),
      connected: connected,
      selected_id: selected
    )
  end

  defp keep_selected(nil, [first | _]), do: first
  defp keep_selected(nil, []), do: nil
  defp keep_selected(id, ids), do: if(id in ids, do: id, else: List.first(ids))

  defp step([], _current, _delta), do: nil

  defp step(ids, current, delta) do
    i = Enum.find_index(ids, &(&1 == current)) || 0
    Enum.at(ids, min(max(i + delta, 0), length(ids) - 1))
  end

  defp spotlighted?(nil, _id), do: false
  defp spotlighted?(spotlight, id), do: spotlight.id == id

  defp clock(dt), do: Calendar.strftime(dt, "%H:%M")

  defp asker(%{display_name: name}) when is_binary(name) and name != "", do: "Asked by #{name}"
  defp asker(_), do: "Anonymous"

  defp votes(1), do: "vote"
  defp votes(_), do: "votes"

  # The tally under the search field keeps its height when the field is empty.
  defp tally("", _shown, _total), do: ""

  defp tally(_term, shown, total),
    do: "Showing #{shown} of #{total} #{if total == 1, do: "question", else: "questions"}"

  @impl true
  def render(%{room: nil} = assigns) do
    ~H"""
    <main style="min-height:100dvh;display:flex;align-items:center;justify-content:center;">
      <p class="q-meta" style="font-size:16px;">That host link doesn't match a room.</p>
    </main>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="q-reconnecting">Reconnecting now. The queue is kept.</div>

    <div phx-window-keyup="key" style="min-height:100dvh;">
      <div style="max-width:1180px;margin:0 auto;">
        <header style="padding:18px 28px;display:flex;justify-content:space-between;align-items:center;gap:22px;flex-wrap:wrap;">
          <div>
            <div class="q-label" style="font-size:18px;">{@room.name}</div>
            <div class="q-meta">
              Pick a question to answer. The room sees your pick on the projection.
            </div>
          </div>
          <div style="display:flex;align-items:center;gap:28px;">
            <div style="text-align:center;">
              <div style="font:700 22px var(--q-font-sans);">{@connected}</div>
              <div class="q-meta">connected</div>
            </div>
            <div style="text-align:center;">
              <div style="font:700 22px var(--q-font-sans);">{@question_count}</div>
              <div class="q-meta">questions</div>
            </div>
            <button
              :if={@room.status == :open}
              type="button"
              class="q-button q-button--destructive"
              phx-click="confirm_close"
            >
              Close session
            </button>
            <span
              :if={@room.status == :closed}
              class="q-meta"
              style="color:var(--q-destructive);font-weight:600;"
            >
              Session closed
            </span>
          </div>
        </header>
        <hr class="q-divider" />

        <div style="display:flex;gap:28px;padding:22px 28px 40px;align-items:flex-start;">
          <section style="flex:1;min-width:0;">
            <label class="q-sr-only" for="search">Search questions</label>
            <input
              id="search"
              name="search"
              value={@search}
              class="q-input"
              placeholder="Search questions"
              autocomplete="off"
              phx-keyup="search"
              onkeyup="event.stopPropagation()"
              onkeydown="event.stopPropagation()"
            />
            <p class="q-status" aria-live="polite">
              {tally(@search, length(@waiting), @visible_count)}
            </p>

            <div class="q-label" style="margin:10px 0 12px;">Waiting, {length(@waiting)}</div>

            <div :if={@waiting == []} class="q-meta" style="padding:12px 0 22px;">
              {if String.trim(@search) == "",
                do: "No questions waiting.",
                else: "No questions match that search."}
            </div>

            <div
              :for={q <- @waiting}
              phx-click="select"
              phx-value-id={q.id}
              class="q-surface"
              style={row_style(spotlighted?(@spotlight, q.id), q.id == @selected_id)}
            >
              <div style="display:flex;gap:18px;align-items:flex-start;">
                <div style="text-align:center;min-width:44px;flex:none;">
                  <div style="font:700 26px var(--q-font-sans);">{q.vote_count}</div>
                  <div class="q-meta">{votes(q.vote_count)}</div>
                </div>
                <div style="flex:1;min-width:0;">
                  <p class="q-question" style="font-size:17px;">{q.body}</p>
                  <div
                    :if={spotlighted?(@spotlight, q.id)}
                    class="q-status q-status--saved"
                    style="font-weight:600;"
                  >
                    On the projection now
                  </div>
                  <div :if={!spotlighted?(@spotlight, q.id)} class="q-meta" style="margin-top:6px;">
                    {asker(q)}, {clock(q.inserted_at)}
                  </div>
                </div>
                <div style="display:grid;grid-auto-flow:column;gap:10px;flex:none;align-items:start;">
                  <button
                    :if={!spotlighted?(@spotlight, q.id)}
                    type="button"
                    class="q-button"
                    phx-click="spotlight"
                    phx-value-id={q.id}
                  >
                    Spotlight
                  </button>
                  <button
                    type="button"
                    class="q-button q-button--secondary"
                    phx-click="answer"
                    phx-value-id={q.id}
                  >
                    Mark answered
                  </button>
                  <button
                    type="button"
                    class="q-button q-button--destructive"
                    phx-click="hide"
                    phx-value-id={q.id}
                  >
                    Hide
                  </button>
                </div>
              </div>
            </div>

            <div :if={@answered != []} style="margin-top:22px;">
              <div class="q-label" style="margin-bottom:12px;">Answered, {length(@answered)}</div>
              <div
                :for={q <- @answered}
                class="q-surface"
                style="padding:16px 18px;margin-bottom:12px;display:flex;gap:18px;align-items:center;"
              >
                <div style="font:700 22px var(--q-font-sans);min-width:44px;text-align:center;color:var(--q-ink-muted);flex:none;">
                  {q.vote_count}
                </div>
                <p class="q-question" style="flex:1;min-width:0;font-size:17px;">{q.body}</p>
                <span class="q-meta" style="flex:none;">Answered {clock(q.updated_at)}</span>
                <button
                  type="button"
                  class="q-button--link"
                  style="flex:none;"
                  phx-click="restore"
                  phx-value-id={q.id}
                >
                  Reopen
                </button>
              </div>
            </div>
          </section>

          <aside class="q-surface" style="width:320px;flex:none;padding:20px;">
            <div class="q-label" style="margin-bottom:10px;">On the projection now</div>
            <%= if @spotlight do %>
              <p class="q-question" style="font-size:17px;">{@spotlight.body}</p>
              <div class="q-meta" style="margin:8px 0 14px;">
                {asker(@spotlight)}, {@spotlight.vote_count} {votes(@spotlight.vote_count)}
              </div>
              <button type="button" class="q-button q-button--secondary" phx-click="clear_spotlight">
                Clear the spotlight
              </button>
            <% else %>
              <p class="q-meta" style="margin-bottom:14px;">
                Nothing is on the projection. Spotlight a question to show it.
              </p>
            <% end %>

            <hr class="q-divider" style="margin:22px 0;" />

            <div class="q-label" style="margin-bottom:6px;">Projection screen</div>
            <p class="q-meta" style="margin-bottom:12px;">
              Open it on the projector, then leave this window open.
            </p>
            <a
              href={~p"/host/#{@room.host_token}/project"}
              target="_blank"
              rel="noopener"
              class="q-button q-button--secondary"
            >
              Open projection view
            </a>

            <hr class="q-divider" style="margin:22px 0;" />

            <div class="q-label" style="margin-bottom:8px;">Keyboard</div>
            <div class="q-meta" style="line-height:1.7;">
              <div><strong>J</strong> and <strong>K</strong> move down and up the queue</div>
              <div><strong>Enter</strong> spotlights the selected question</div>
              <div><strong>A</strong> marks it answered</div>
              <div><strong>H</strong> hides it from students</div>
            </div>
          </aside>
        </div>
      </div>

      <div
        :if={@confirming_close}
        role="dialog"
        aria-modal="true"
        aria-labelledby="close-dialog-title"
        style="position:fixed;inset:0;background:rgba(20,23,26,0.45);display:flex;align-items:center;justify-content:center;padding:22px;"
      >
        <div
          class="q-surface"
          style="background:var(--q-surface-raised);max-width:420px;padding:24px;"
        >
          <div id="close-dialog-title" class="q-label" style="font-size:18px;margin-bottom:8px;">
            Close this session?
          </div>
          <p class="q-meta" style="margin-bottom:20px;">
            Students won't be able to post or vote after this. Answered questions stay visible.
          </p>
          <div style="display:flex;justify-content:flex-end;gap:12px;">
            <button
              type="button"
              class="q-button q-button--secondary"
              phx-click="cancel_close"
              phx-mounted={JS.focus()}
            >
              Keep it open
            </button>
            <button type="button" class="q-button q-button--destructive-solid" phx-click="close">
              Close session
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp row_style(spotlighted?, selected?) do
    base = "display:block;padding:16px 18px;margin-bottom:12px;cursor:pointer;"

    accent =
      cond do
        spotlighted? -> "border-color:var(--q-accent);background:var(--q-accent-tint);"
        selected? -> "box-shadow:0 0 0 2px var(--q-accent);"
        true -> ""
      end

    base <> accent
  end
end
