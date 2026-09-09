defmodule QuorumWeb.HostLive do
  @moduledoc """
  The lecturer's console, as a full page: the site shell, the room bar, the
  joining panel, the ranked queue, and a rail carrying what's on the projection
  and the keyboard map.

  The joining panel owns the space while the room is empty and shrinks to a strip
  once questions arrive, on the same split-priority principle as the projection.
  """
  use QuorumWeb, :live_view

  alias Quorum.Sessions
  alias QuorumWeb.CurrentUser

  @impl true
  def mount(%{"host_token" => token}, session, socket) do
    case Sessions.get_room_by_host_token(token) do
      {:ok, %{} = room} ->
        if connected?(socket), do: Sessions.subscribe(room.id)

        socket =
          socket
          |> assign(
            current_user: CurrentUser.from_session(session),
            room: room,
            search: "",
            selected_id: nil,
            confirming_close: false,
            renaming: false,
            status: nil,
            page_title: room.name
          )
          |> load()

        {:ok, socket}

      _ ->
        {:ok, assign(socket, room: nil, current_user: nil, page_title: "Host")}
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

  def handle_event("start_rename", _params, socket),
    do: {:noreply, assign(socket, renaming: true)}

  def handle_event("cancel_rename", _params, socket),
    do: {:noreply, assign(socket, renaming: false)}

  def handle_event("rename", %{"name" => name}, socket) do
    case String.trim(name) do
      "" ->
        {:noreply, assign(socket, renaming: false)}

      name ->
        Sessions.rename_room(socket.assigns.room, name)
        {:noreply, socket |> assign(renaming: false, page_title: name) |> load()}
    end
  end

  def handle_event("new_code", _params, socket) do
    case Sessions.new_join_code(socket.assigns.room) do
      {:ok, room} ->
        {:noreply,
         socket
         |> assign(room: room, status: "New code. The old one stops working now.")
         |> load()}

      _ ->
        {:noreply, assign(socket, status: "Couldn't issue a new code. Try again.")}
    end
  end

  def handle_event("copied", _params, socket),
    do: {:noreply, assign(socket, status: "Student link copied.")}

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

  # Escape cancels whatever is open, and the queue shortcuts stay quiet while one is.
  def handle_event("key", %{"key" => "Escape"}, socket),
    do: {:noreply, assign(socket, confirming_close: false, renaming: false)}

  def handle_event("key", _params, %{assigns: %{confirming_close: true}} = socket),
    do: {:noreply, socket}

  def handle_event("key", _params, %{assigns: %{renaming: true}} = socket),
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

  defp qr(code, width),
    do: ~p"/r/#{code}" |> url() |> EQRCode.encode() |> EQRCode.svg(width: width)

  defp student_url(code), do: url(~p"/r/#{code}")

  # The tally under the search field keeps its height when the field is empty.
  defp tally("", _shown, _total), do: ""

  defp tally(_term, shown, total),
    do: "Showing #{shown} of #{total} #{if total == 1, do: "question", else: "questions"}"

  # What the room is seeing right now, in one sentence.
  defp projection_line(nil),
    do: "Nothing spotlighted, so the room sees the join code and the connected count."

  defp projection_line(question),
    do: "#{first_words(question.body)}, #{question.vote_count} #{votes(question.vote_count)}."

  defp first_words(body) do
    case String.split(body, ~r/\s+/) do
      words when length(words) <= 8 -> body
      words -> words |> Enum.take(8) |> Enum.join(" ") |> Kernel.<>("...")
    end
  end

  @impl true
  def render(%{room: nil} = assigns) do
    ~H"""
    <div class="q-page">
      <QuorumWeb.Shell.header current_user={@current_user} />
      <main style="flex:1;display:flex;align-items:center;justify-content:center;padding:32px;">
        <div style="text-align:center;max-width:420px;">
          <div class="q-label" style="font-size:18px;margin-bottom:6px;">
            That host link doesn't match a room
          </div>
          <p class="q-meta" style="margin:0 0 18px;">
            The link may be incomplete, or the room may have been deleted.
          </p>
          <.link href={~p"/start"} class="q-button">Open a room</.link>
        </div>
      </main>
      <QuorumWeb.Shell.footer />
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="q-reconnecting">Reconnecting now. The queue is kept.</div>

    <div class="q-page" phx-window-keyup="key">
      <QuorumWeb.Shell.header current_user={@current_user} />

      <div class="q-room-bar">
        <div style="min-width:0;">
          <div class="q-room-title">
            <h1>{@room.name}</h1>
            <button :if={!@renaming} type="button" class="q-button--link" phx-click="start_rename">
              Rename
            </button>
          </div>
          <form
            :if={@renaming}
            phx-submit="rename"
            style="display:flex;gap:10px;margin-top:10px;flex-wrap:wrap;"
          >
            <label class="q-sr-only" for="room-name">Room name</label>
            <input
              id="room-name"
              name="name"
              class="q-input"
              value={@room.name}
              maxlength="200"
              style="max-width:320px;"
              onkeyup="event.stopPropagation()"
              onkeydown="event.stopPropagation()"
              phx-mounted={JS.focus()}
            />
            <button type="submit" class="q-button">Save name</button>
            <button type="button" class="q-button q-button--secondary" phx-click="cancel_rename">
              Keep the old one
            </button>
          </form>
          <p :if={!@renaming} class="q-meta" style="margin:6px 0 0;">
            {if @question_count == 0,
              do: "Nobody has joined yet. The projection is showing the code.",
              else: "Pick a question to answer. The room sees your pick on the projection."}
          </p>
        </div>

        <div class="q-room-actions">
          <div class="q-room-stat"><b>{@connected}</b><span>connected</span></div>
          <div class="q-room-stat"><b>{@question_count}</b><span>questions</span></div>
          <a
            href={~p"/host/#{@room.host_token}/project"}
            target="_blank"
            rel="noopener"
            class="q-button"
          >
            Open projection
          </a>
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
      </div>

      <div class="q-console">
        <main class="q-console-main">
          <%= if @question_count == 0 do %>
            <section class="q-join-panel">
              <div class="q-join-qr">{raw(qr(@room.join_code, 150))}</div>
              <div style="min-width:0;">
                <p class="q-meta" style="font-size:15px;margin:0;">
                  Students join at quorum.app/join with
                </p>
                <p class="q-code">{@room.join_code}</p>
                <div class="q-join-actions">
                  <button
                    type="button"
                    class="q-button q-button--secondary"
                    phx-click={
                      JS.dispatch("quorum:copy", detail: %{text: student_url(@room.join_code)})
                    }
                  >
                    Copy student link
                  </button>
                  <button type="button" class="q-button q-button--secondary" phx-click="new_code">
                    New code
                  </button>
                </div>
                <p class="q-status" aria-live="polite">{@status}</p>
              </div>
            </section>
          <% else %>
            <section class="q-join-strip">
              <div class="q-join-qr">{raw(qr(@room.join_code, 46))}</div>
              <div style="flex:1;min-width:0;">
                <p class="q-meta" style="margin:0;">Still joining at quorum.app/join</p>
                <p class="q-code">{@room.join_code}</p>
              </div>
              <button
                type="button"
                class="q-button q-button--secondary"
                phx-click={JS.dispatch("quorum:copy", detail: %{text: student_url(@room.join_code)})}
              >
                Copy student link
              </button>
            </section>
            <p class="q-status" aria-live="polite">{@status}</p>
          <% end %>

          <div :if={@question_count > 0}>
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
          </div>

          <div :if={@question_count == 0} class="q-panel">
            <div class="q-label" style="font-size:17px;margin-bottom:6px;">No questions yet</div>
            <p class="q-meta" style="margin:0;">
              Questions appear here the moment a student posts one, sorted by votes. Search and the
              answered list turn up with the first one.
            </p>
          </div>

          <div :if={@question_count > 0}>
            <div class="q-label" style="margin-bottom:12px;">Waiting, {length(@waiting)}</div>

            <p :if={@waiting == []} class="q-meta" style="padding:4px 0 12px;">
              No questions match that search.
            </p>

            <div style="display:flex;flex-direction:column;gap:12px;">
              <div
                :for={q <- @waiting}
                phx-click="select"
                phx-value-id={q.id}
                class={[
                  "q-queue-row",
                  spotlighted?(@spotlight, q.id) && "q-queue-row--spotlit",
                  q.id == @selected_id && !spotlighted?(@spotlight, q.id) && "q-queue-row--selected"
                ]}
              >
                <div class="q-queue-votes">
                  <b>{q.vote_count}</b><span>{votes(q.vote_count)}</span>
                </div>
                <div style="flex:1;min-width:0;">
                  <p class="q-question" style="margin:0;">{q.body}</p>
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
                <div class="q-queue-actions">
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
          </div>

          <div :if={@answered != []}>
            <div class="q-label" style="margin-bottom:12px;">Answered, {length(@answered)}</div>
            <div style="display:flex;flex-direction:column;gap:12px;">
              <div :for={q <- @answered} class="q-queue-row">
                <div class="q-queue-votes" style="color:var(--q-ink-muted);">
                  <b>{q.vote_count}</b>
                </div>
                <p class="q-question" style="flex:1;min-width:0;margin:0;">{q.body}</p>
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
          </div>

          <section class="q-panel q-panel--split">
            <div style="min-width:0;">
              <div class="q-label" style="font-size:17px;margin-bottom:6px;">
                Attach a reading list
              </div>
              <p class="q-meta" style="margin:0;">
                Point students at approved readings while they wait for you.
              </p>
            </div>
            <div>
              <button type="button" class="q-button q-button--secondary" disabled="disabled">
                Choose a list
              </button>
              <p class="q-meta" style="margin:6px 0 0;max-width:26ch;">
                Turns on once reading lists ship.
              </p>
            </div>
          </section>
        </main>

        <aside class="q-console-rail">
          <div class="q-rail-block">
            <h2>On the projection now</h2>
            <p>
              {projection_line(@spotlight)}
              <span :if={@spotlight}>Press <strong>Q</strong> on the projection to clear it.</span>
            </p>
            <button
              :if={@spotlight}
              type="button"
              class="q-button q-button--secondary"
              style="margin-top:12px;"
              phx-click="clear_spotlight"
            >
              Clear the spotlight
            </button>
          </div>

          <div class="q-rail-block">
            <h2>Before you start</h2>
            <div class="q-rail-lines">
              <div>Put the projection on the screen behind you.</div>
              <div>Say the code out loud once.</div>
              <div>Take the top questions at a pause.</div>
            </div>
          </div>

          <div class="q-rail-block">
            <h2>Keyboard</h2>
            <div class="q-rail-lines">
              <div><strong>J</strong> and <strong>K</strong> move down and up the queue</div>
              <div><strong>Enter</strong> spotlights the selected question</div>
              <div><strong>A</strong> marks it answered</div>
              <div><strong>H</strong> hides it from students</div>
            </div>
          </div>
        </aside>
      </div>

      <QuorumWeb.Shell.footer />

      <div
        :if={@confirming_close}
        role="dialog"
        aria-modal="true"
        aria-labelledby="close-dialog-title"
        style="position:fixed;inset:0;background:rgba(20,23,26,0.45);display:flex;align-items:center;justify-content:center;padding:22px;z-index:40;"
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
          <div style="display:flex;justify-content:flex-end;gap:12px;flex-wrap:wrap;">
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
end
