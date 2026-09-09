defmodule QuorumWeb.AttendeeLive do
  @moduledoc """
  The student's phone-first feed: post a question, upvote, and watch the ranking.
  The list reorders live, but the row a student is reading or voting on is held in
  place with a resort nudge rather than freezing the whole list.
  """
  use QuorumWeb, :live_view

  alias Quorum.Sessions

  @impl true
  def mount(%{"code" => code}, session, socket) do
    token = session[QuorumWeb.BrowserToken.session_key()]

    case Sessions.get_room_by_code(code) do
      {:ok, %{} = room} ->
        if connected?(socket) do
          Sessions.subscribe(room.id)
          QuorumWeb.Presence.track(self(), Sessions.topic(room.id), token, %{})
        end

        socket =
          socket
          |> assign(
            token: token,
            room: room,
            show_name: false,
            draft: "",
            pinned_id: nil,
            display_ids: [],
            status: nil,
            page_title: room.name
          )
          |> load()

        {:ok, socket}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/join?code=#{String.upcase(code)}")}
    end
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("draft", params, socket),
    do: {:noreply, assign(socket, draft: Map.get(params, "body", ""))}

  def handle_event("toggle_name", _params, socket),
    do: {:noreply, assign(socket, show_name: !socket.assigns.show_name)}

  def handle_event("ask", params, socket) do
    body = params |> Map.get("body", "") |> String.trim()
    name = params |> Map.get("name", "") |> String.trim()

    if body == "" do
      {:noreply, socket}
    else
      attrs = %{body: body, submitter_token: socket.assigns.token}
      attrs = if name == "", do: attrs, else: Map.put(attrs, :display_name, name)

      case Sessions.ask(socket.assigns.room.id, attrs) do
        {:ok, %{status: :pending}} ->
          socket =
            assign(socket,
              show_name: false,
              draft: "",
              status: "Sent to your lecturer for review."
            )

          {:noreply, load(socket)}

        {:ok, _question} ->
          socket = assign(socket, show_name: false, draft: "", status: "Posted to the queue.")
          {:noreply, load(socket)}

        {:error, :too_long} ->
          {:noreply,
           assign(socket,
             status: "That's longer than #{socket.assigns.room.question_max_length} characters."
           )}

        {:error, :too_many} ->
          {:noreply, assign(socket, status: allowance_message(socket.assigns.room))}

        {:error, _} ->
          {:noreply, assign(socket, status: "That question couldn't be posted. Try again.")}
      end
    end
  end

  def handle_event("toggle_vote", %{"id" => id}, socket) do
    if MapSet.member?(socket.assigns.voted, id) do
      Sessions.unvote(id, socket.assigns.token)
      {:noreply, socket |> assign(pinned_id: nil) |> load()}
    else
      Sessions.vote(id, socket.assigns.token)
      {:noreply, socket |> assign(pinned_id: id) |> load()}
    end
  end

  def handle_event("resort", _params, socket) do
    sorted = Enum.map(socket.assigns.visible, & &1.id)
    {:noreply, assign(socket, display_ids: sorted, pinned_id: nil, moved: 0)}
  end

  def handle_event("retract", %{"id" => id}, socket) do
    with {:ok, question} <- Sessions.get_question(id),
         true <- question.submitter_token == socket.assigns.token do
      Sessions.retract(question)
    end

    {:noreply, socket |> assign(status: nil) |> load()}
  end

  defp load(socket) do
    room_id = socket.assigns.room.id
    {:ok, room} = Sessions.get_room(room_id)
    token = socket.assigns.token
    questions = Sessions.list_questions(room_id)
    %{visible: visible, held: held, answered: answered} = Sessions.partition(questions)
    voted = Sessions.voted_question_ids(room_id, token)

    sorted_ids = Enum.map(visible, & &1.id)
    display_ids = reconcile(socket.assigns.display_ids, sorted_ids)

    assign(socket,
      room: room,
      visible: visible,
      answered: answered,
      # A held question is invisible to the room, but its own asker sees it
      # waiting, so they don't take the silence for a failure and post again.
      waiting: Enum.filter(held, &mine?(&1, token)),
      left: Sessions.questions_left(room, token),
      by_id: Map.new(visible, &{&1.id, &1}),
      voted: voted,
      display_ids: display_ids,
      moved: moved_count(display_ids, sorted_ids)
    )
  end

  # Keep the order the reader is looking at, appending anything new at the end.
  defp reconcile(display_ids, sorted_ids) do
    kept = Enum.filter(display_ids, &(&1 in sorted_ids))
    kept ++ Enum.reject(sorted_ids, &(&1 in kept))
  end

  # How many questions would rise if the reader resorted now.
  defp moved_count(display_ids, sorted_ids) do
    di = index_map(display_ids)
    si = index_map(sorted_ids)
    Enum.count(sorted_ids, fn id -> Map.get(si, id, 0) < Map.get(di, id, 0) end)
  end

  defp index_map(ids), do: ids |> Enum.with_index() |> Map.new()

  defp mine?(question, token), do: question.submitter_token == token

  defp clock(dt), do: Calendar.strftime(dt, "%H:%M")

  defp ago(dt) do
    case DateTime.diff(DateTime.utc_now(), dt) do
      s when s < 60 -> "just now"
      s when s < 3600 -> "#{div(s, 60)} min ago"
      s -> "#{div(s, 3600)} h ago"
    end
  end

  defp votes(1), do: "vote"
  defp votes(_), do: "votes"

  # How many this student can still post, counting only what's waiting on them.
  defp remaining(0), do: "You've used your questions for now. Retracting one frees it up."
  defp remaining(1), do: "One question left."
  defp remaining(n), do: "#{n} questions left."

  defp allowance_message(%{questions_per_student: 1}),
    do: "You already have a question waiting. Retract it, or wait for it to be answered."

  defp allowance_message(%{questions_per_student: n}),
    do: "You already have #{n} questions waiting. Retract one, or wait for one to be answered."

  defp vote_label(true, count), do: "Voted, #{count} #{votes(count)}. Press to remove your vote"
  defp vote_label(false, count), do: "Upvote, #{count} #{votes(count)}"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="q-reconnecting">Reconnecting now. Draft saved.</div>

    <main style="max-width:680px;margin:0 auto;min-height:100dvh;">
      <header style="padding:18px 22px;display:flex;justify-content:space-between;align-items:center;gap:12px;">
        <span class="q-label" style="font-size:18px;">{@room.name}</span>
        <span style="white-space:nowrap;font:600 14px var(--q-font-sans);color:var(--q-accent);display:inline-flex;align-items:center;gap:6px;">
          <span
            :if={@room.status == :open}
            style="width:8px;height:8px;border-radius:50%;background:var(--q-accent);display:inline-block;"
          ></span>
          {if @room.status == :open, do: "Live", else: "Closed"}
        </span>
      </header>
      <hr class="q-divider" />

      <%= if @room.status == :closed do %>
        <section style="padding:22px;">
          <div class="q-surface" style="padding:22px;">
            <div class="q-label" style="font-size:17px;margin-bottom:6px;">
              This session is closed
            </div>
            <p class="q-meta">Students can still read. Nobody can post or vote.</p>
          </div>
        </section>
      <% else %>
        <section style="padding:22px;">
          <p style="font:400 16px/1.45 var(--q-font-serif);margin:0 0 14px;">
            Ask the lecturer anything, or vote anonymously for a question you want answered.
          </p>
          <form id="ask-form" phx-submit="ask" phx-change="draft">
            <label class="q-sr-only" for="body">Your question</label>
            <textarea
              id="body"
              name="body"
              class="q-textarea"
              rows="3"
              maxlength={@room.question_max_length}
              placeholder="What would you like explained?"
              phx-debounce="400"
            >{@draft}</textarea>
            <div
              :if={@show_name and @room.allow_display_name?}
              style="margin-top:10px;"
            >
              <label class="q-sr-only" for="name">Your name</label>
              <input id="name" name="name" class="q-input" maxlength="60" placeholder="Your name" />
            </div>
            <div style="display:flex;justify-content:space-between;align-items:center;margin-top:14px;gap:12px;flex-wrap:wrap;">
              <button
                :if={!@show_name and @room.allow_display_name?}
                type="button"
                class="q-button--link"
                phx-click="toggle_name"
              >
                Add your name
              </button>
              <span :if={@show_name and @room.allow_display_name?} class="q-meta">
                Shown on this question only.
              </span>
              <span :if={!@room.allow_display_name?} class="q-meta">
                Every question here is anonymous.
              </span>
              <button type="submit" class="q-button">Post question</button>
            </div>
          </form>
          <p :if={@room.hold_for_review?} class="q-meta">
            Your lecturer reads each question before the room sees it.
          </p>
          <p :if={@left} class="q-meta">
            {remaining(@left)}
          </p>
          <p class="q-status">{@status}</p>
        </section>
      <% end %>

      <section :if={@waiting != []} style="padding:0 22px 4px;">
        <div class="q-label" style="margin-bottom:8px;">
          Waiting for your lecturer
        </div>
        <div :for={question <- @waiting} class="q-row q-row--waiting">
          <div style="min-width:0;flex:1;">
            <p class="q-question">{question.body}</p>
            <p class="q-meta" style="margin:6px 0 0;">
              Nobody else can see this yet. Your lecturer decides whether it reaches the room.
            </p>
          </div>
          <button
            type="button"
            class="q-button q-button--secondary"
            phx-click="retract"
            phx-value-id={question.id}
          >
            Retract
          </button>
        </div>
      </section>

      <div
        :if={@moved > 0}
        style="display:flex;justify-content:space-between;align-items:center;gap:12px;padding:12px 22px;background:var(--q-surface-sunken);"
      >
        <span class="q-meta">
          {@moved} {if @moved == 1, do: "question", else: "questions"} moved above
        </span>
        <button type="button" class="q-button q-button--secondary" phx-click="resort">Resort list</button>
      </div>

      <section style="padding:16px 22px 32px;display:flex;flex-direction:column;gap:14px;">
        <div
          :if={@visible == [] and @answered == []}
          class="q-surface"
          style="padding:28px;text-align:center;"
        >
          <div class="q-label" style="font-size:17px;margin-bottom:6px;">No questions yet</div>
          <p class="q-meta">Be the first. Ask what you'd like explained.</p>
        </div>

        <div :for={id <- @display_ids} :if={Map.has_key?(@by_id, id)}>
          <% question = @by_id[id] %>
          <% voted = MapSet.member?(@voted, id) %>
          <% pinned = @pinned_id == id %>
          <div class={["q-row", pinned && "q-row--pinned"]}>
            <button
              type="button"
              class={["q-vote", voted && "q-vote--voted"]}
              phx-click="toggle_vote"
              phx-value-id={id}
              aria-label={vote_label(voted, question.vote_count)}
            >
              <svg width="15" height="12" viewBox="0 0 15 12" aria-hidden="true">
                <path d="M7.5 1 L14 11 L1 11 Z" fill="currentColor" />
              </svg>
              <span style="font:700 15px var(--q-font-sans);margin-top:2px;">{question.vote_count}</span>
            </button>
            <div style="flex:1;min-width:0;">
              <p class="q-question">{question.body}</p>

              <div :if={pinned} class="q-status q-status--saved">
                Voted. Held in place while you read.
                <button
                  type="button"
                  class="q-button--link"
                  phx-click="resort"
                  style="margin-left:8px;"
                >
                  Let it move
                </button>
              </div>
              <div :if={voted and not pinned} class="q-status q-status--saved">Voted</div>

              <div
                :if={mine?(question, @token)}
                class="q-meta"
                style="margin-top:6px;display:flex;gap:14px;align-items:center;"
              >
                <span class="q-label">Your question</span>
                <button
                  type="button"
                  class="q-button--link"
                  style="color:var(--q-destructive);"
                  phx-click="retract"
                  phx-value-id={id}
                >
                  Retract it
                </button>
              </div>
              <div :if={!mine?(question, @token)} class="q-meta" style="margin-top:6px;">
                {if question.display_name, do: question.display_name, else: "Anonymous"}, {ago(
                  question.inserted_at
                )}
              </div>
            </div>
          </div>
        </div>

        <div :if={@answered != []}>
          <div class="q-label" style="margin:8px 0 14px;">Answered, {length(@answered)}</div>
          <div :for={question <- @answered} class="q-row" style="margin-bottom:14px;">
            <button
              type="button"
              class="q-vote q-vote--closed"
              disabled="disabled"
              aria-label={"Voting closed, #{question.vote_count} #{votes(question.vote_count)}"}
            >
              <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true">
                <path d="M2 7 L6 11 L12 3" stroke="currentColor" stroke-width="2" fill="none" />
              </svg>
              <span style="font:700 14px var(--q-font-sans);margin-top:2px;">{question.vote_count}</span>
            </button>
            <div style="flex:1;min-width:0;">
              <p class="q-question">{question.body}</p>
              <div class="q-meta" style="margin-top:6px;">
                Answered at {clock(question.updated_at)}. Voting closed.
              </div>
            </div>
          </div>
        </div>
      </section>
    </main>
    """
  end
end
