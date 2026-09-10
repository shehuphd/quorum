defmodule QuorumWeb.AttendeeLive do
  @moduledoc """
  The student's phone-first feed: post a question, upvote, and watch the ranking.
  A vote fills the vote box and moves the count, and that's the whole of it: the
  list ranks live, so a row can move as the room votes.

  A posted question waits ten seconds before it's written, counting down where
  the composer was. That window is for the student who spots the same question
  already in the list, notices a typo, or decides they'd rather not have asked.
  Nothing they cancel is ever written, so there's nothing to retract and nobody
  saw it.
  """
  use QuorumWeb, :live_view

  alias Quorum.Sessions

  @undo_seconds 10

  @doc "How long a student has to call a question back before it's written."
  def undo_seconds, do: @undo_seconds

  @impl true
  def mount(%{"code" => code}, session, socket) do
    token = session[QuorumWeb.BrowserToken.session_key()]
    name = session[QuorumWeb.RoomController.display_name_key()] || ""

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
            name: name,
            show_name: name != "",
            draft: "",
            pinned: MapSet.new(),
            status: nil,
            pending: nil,
            tick: nil,
            undo_left: nil,
            page_title: room.name
          )
          |> load()

        {:ok, socket}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/join?code=#{String.upcase(code)}")}
    end
  end

  @impl true
  def handle_info(:tick, %{assigns: %{pending: nil}} = socket), do: {:noreply, socket}

  def handle_info(:tick, %{assigns: %{undo_left: left}} = socket) when left <= 1,
    do: {:noreply, post_pending(socket)}

  def handle_info(:tick, socket) do
    {:noreply,
     assign(socket,
       undo_left: socket.assigns.undo_left - 1,
       tick: Process.send_after(self(), :tick, 1000)
     )}
  end

  def handle_info(_message, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("draft", params, socket) do
    {:noreply,
     assign(socket,
       draft: Map.get(params, "body", ""),
       name: params |> Map.get("name", socket.assigns.name) |> String.slice(0, 60)
     )}
  end

  # Turning the name off clears it, so a student who changes their mind isn't
  # one keystroke away from signing the next question by accident.
  def handle_event("toggle_name", _params, socket) do
    show? = !socket.assigns.show_name

    {:noreply,
     assign(socket, show_name: show?, name: if(show?, do: socket.assigns.name, else: ""))}
  end

  def handle_event("ask", params, socket) do
    body = params |> Map.get("body", "") |> String.trim()
    name = params |> Map.get("name", socket.assigns.name) |> String.trim()

    if body == "" do
      {:noreply, socket}
    else
      attrs = %{body: body, submitter_token: socket.assigns.token}
      attrs = if name == "", do: attrs, else: Map.put(attrs, :display_name, name)

      {:noreply,
       socket
       |> assign(
         pending: attrs,
         undo_left: @undo_seconds,
         name: name,
         show_name: name != "",
         draft: "",
         status: nil,
         tick: Process.send_after(self(), :tick, 1000)
       )}
    end
  end

  # The student called it back inside the window, so nothing was ever written.
  # The text goes back in the composer: cancelling is usually a rewrite.
  def handle_event("cancel_ask", _params, socket) do
    {:noreply,
     socket
     |> cancel_tick()
     |> assign(
       pending: nil,
       draft: socket.assigns.pending[:body] || "",
       status: "Called back. Nobody saw it."
     )}
  end

  def handle_event("send_now", _params, socket),
    do: {:noreply, socket |> cancel_tick() |> post_pending()}

  def handle_event("toggle_vote", %{"id" => id}, socket) do
    if MapSet.member?(socket.assigns.voted, id) do
      Sessions.unvote(id, socket.assigns.token)
    else
      Sessions.vote(id, socket.assigns.token)
    end

    {:noreply, load(socket)}
  end

  # A pin is one student's own bookmark. It never leaves this browser and it
  # doesn't touch the ranking anyone else sees: it lifts the question to the top
  # of their own list so a row they care about can't be voted out of sight.
  def handle_event("toggle_pin", %{"id" => id}, socket) do
    pinned = socket.assigns.pinned

    pinned =
      if MapSet.member?(pinned, id),
        do: MapSet.delete(pinned, id),
        else: MapSet.put(pinned, id)

    {:noreply, socket |> assign(pinned: pinned) |> load()}
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

    assign(socket,
      room: room,
      visible: visible,
      answered: answered,
      # A held question is invisible to the room, but its own asker sees it
      # waiting, so they don't take the silence for a failure and post again.
      waiting: Enum.filter(held, &mine?(&1, token)),
      left: Sessions.questions_left(room, token),
      voted: voted
    )
    |> order_pinned()
    |> drop_pending_if_closed()
  end

  # A session that ends mid-window takes the question with it. Saying so beats
  # counting down against a room that can no longer take it.
  defp drop_pending_if_closed(%{assigns: %{pending: nil}} = socket), do: socket

  defp drop_pending_if_closed(%{assigns: %{room: %{status: :closed}}} = socket) do
    socket
    |> cancel_tick()
    |> assign(
      pending: nil,
      undo_left: nil,
      status: "The session closed before your question went in."
    )
  end

  defp drop_pending_if_closed(socket), do: socket

  defp cancel_tick(socket) do
    if ref = socket.assigns[:tick], do: Process.cancel_timer(ref)
    assign(socket, tick: nil)
  end

  # The window has run out, or the student asked to send it now. Everything the
  # room's own limits have to say is applied here, at the moment of the write.
  defp post_pending(%{assigns: %{pending: nil}} = socket), do: socket

  defp post_pending(socket) do
    attrs = socket.assigns.pending
    socket = assign(socket, pending: nil, tick: nil, undo_left: nil)

    case Sessions.ask(socket.assigns.room.id, attrs) do
      {:ok, %{status: :pending}} ->
        socket |> assign(status: "Sent to your presenter for review.") |> load()

      {:ok, _question} ->
        socket |> assign(status: "Posted to the queue.") |> load()

      {:error, :closed} ->
        held_back(socket, attrs, "The session closed before this went in.")

      {:error, :too_long} ->
        held_back(
          socket,
          attrs,
          "That's longer than #{socket.assigns.room.question_max_length} characters."
        )

      {:error, :too_many} ->
        held_back(socket, attrs, allowance_message(socket.assigns.room))

      {:error, _} ->
        held_back(socket, attrs, "That question couldn't be posted. Try again.")
    end
  end

  # A refusal at the end of the window would otherwise lose what they typed, so
  # the text goes back in the composer with the reason beside it.
  defp held_back(socket, attrs, message),
    do: assign(socket, draft: attrs[:body] || "", status: message)

  # Pinned rows keep their rank among themselves and sit above the rest.
  defp order_pinned(socket) do
    {pinned, rest} =
      Enum.split_with(socket.assigns.visible, &MapSet.member?(socket.assigns.pinned, &1.id))

    assign(socket, visible: pinned ++ rest)
  end

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
            <p class="q-status">{@status}</p>
          </div>
        </section>
      <% else %>
        <section :if={@pending} style="padding:22px;" id="undo-window">
          <div class="q-undo">
            <p class="q-question" style="margin:0 0 4px;">{@pending[:body]}</p>
            <p class="q-meta" style="margin:0 0 14px;">
              Going in shortly. Take it back if someone's already asked it.
            </p>

            <div
              class="q-undo-track"
              role="progressbar"
              aria-valuemin="0"
              aria-valuemax={undo_seconds()}
              aria-valuenow={@undo_left}
              aria-label="Seconds until this question is posted"
            >
              <span class="q-undo-bar" style={"animation-duration:#{undo_seconds()}s;"}></span>
            </div>

            <div class="q-undo-actions">
              <button type="button" class="q-button q-button--destructive" phx-click="cancel_ask">
                Cancel ({@undo_left})
              </button>
              <button type="button" class="q-button--link" phx-click="send_now">
                Send it now
              </button>
            </div>
          </div>
        </section>

        <section :if={!@pending} style="padding:22px;">
          <p style="font:400 16px/1.45 var(--q-font-serif);margin:0 0 14px;">
            Ask the presenter anything, or vote anonymously for a question below.
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
            >{@draft}</textarea>
            <div
              :if={@show_name and @room.allow_display_name?}
              style="margin-top:10px;"
            >
              <label class="q-sr-only" for="name">Your name</label>
              <input
                id="name"
                name="name"
                class="q-input"
                value={@name}
                maxlength="60"
                placeholder="Your name"
              />
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
                Shown on the questions you post.
              </span>
              <span :if={!@room.allow_display_name?} class="q-meta">
                Every question here is anonymous.
              </span>
              <button type="submit" class="q-button" disabled={String.trim(@draft) == ""}>
                Post question
              </button>
            </div>
          </form>
          <p :if={@room.hold_for_review?} class="q-meta">
            Your presenter reads each question before the room sees it.
          </p>
          <p :if={@left} class="q-meta">
            {remaining(@left)}
          </p>
          <p class="q-status">{@status}</p>
        </section>
      <% end %>

      <section :if={@waiting != []} style="padding:0 22px 4px;">
        <div class="q-label" style="margin-bottom:8px;">
          Waiting for your presenter
        </div>
        <div :for={question <- @waiting} class="q-row q-row--waiting">
          <div style="min-width:0;flex:1;">
            <p class="q-question">{question.body}</p>
            <p class="q-meta" style="margin:6px 0 0;">
              Nobody else can see this yet. Your presenter decides whether it reaches the room.
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

      <section style="padding:16px 22px 32px;display:flex;flex-direction:column;gap:14px;">
        <div
          :if={@visible == [] and @answered == []}
          class="q-surface"
          style="padding:28px;text-align:center;"
        >
          <div class="q-label" style="font-size:17px;margin-bottom:6px;">No questions yet</div>
          <p class="q-meta">Be the first. Ask what you'd like explained.</p>
        </div>

        <div :for={question <- @visible}>
          <% voted = MapSet.member?(@voted, question.id) %>
          <% pinned = MapSet.member?(@pinned, question.id) %>
          <div class="q-row">
            <div class="q-row-controls">
              <button
                type="button"
                class={["q-vote", voted && "q-vote--voted"]}
                phx-click="toggle_vote"
                phx-value-id={question.id}
                aria-pressed={to_string(voted)}
                aria-label={vote_label(voted, question.vote_count)}
              >
                <svg width="15" height="12" viewBox="0 0 15 12" aria-hidden="true">
                  <path d="M7.5 1 L14 11 L1 11 Z" fill="currentColor" />
                </svg>
                <span style="font:700 15px var(--q-font-sans);margin-top:2px;">{question.vote_count}</span>
              </button>
              <button
                type="button"
                class={["q-pin", pinned && "q-pin--on"]}
                phx-click="toggle_pin"
                phx-value-id={question.id}
                aria-pressed={to_string(pinned)}
                aria-label={
                  if pinned,
                    do: "Pinned to the top of your list. Press to unpin",
                    else: "Pin for me, to keep this at the top of your list"
                }
              >
                <svg width="13" height="16" viewBox="0 0 13 16" aria-hidden="true">
                  <path
                    d="M4 1h5l-.6 4.2 2.4 2.3H2.2l2.4-2.3z"
                    fill={if pinned, do: "currentColor", else: "none"}
                    stroke="currentColor"
                    stroke-width="1.2"
                    stroke-linejoin="round"
                  />
                  <path d="M6.5 7.5V15" stroke="currentColor" stroke-width="1.2" />
                </svg>
              </button>
            </div>
            <div style="flex:1;min-width:0;">
              <p class="q-question">{question.body}</p>

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
                  phx-value-id={question.id}
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
            <div class="q-row-controls">
              <button
                type="button"
                class="q-vote q-vote--closed"
                disabled="disabled"
                aria-label={"Voting closed, #{question.vote_count} #{votes(question.vote_count)}"}
              >
                <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true">
                  <path d="M2 7 L6 11 L12 3" stroke="currentColor" stroke-width="2" fill="none" />
                </svg>
                <span style="font:700 14px var(--q-font-sans);margin-top:2px;">
                  {question.vote_count}
                </span>
              </button>
              <%!-- An answered question can't be pinned, but it holds the pin's
              column so the answered list lines up with the one above it. --%>
              <span class="q-pin-space" aria-hidden="true"></span>
            </div>
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
