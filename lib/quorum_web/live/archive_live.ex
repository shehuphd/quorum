defmodule QuorumWeb.ArchiveLive do
  @moduledoc """
  What a presenter reads back when planning the next term.

  Every session they have run, newest first, with the questions it drew ranked
  the way the hall ranked them. A term of this is the record of what didn't get
  through: which weeks drew nothing, which drew the same question forty times,
  what belongs in the next tutorial.

  The search runs over every question in every session at once, since the point
  is finding the thread that runs through a term rather than reading one week.
  """
  use QuorumWeb, :live_view

  alias Quorum.Sessions
  alias QuorumWeb.CurrentUser

  @preview 5

  # Read through a function: @preview in the template would be an assign.
  defp preview, do: @preview

  @impl true
  def mount(_params, session, socket) do
    case CurrentUser.from_session(session) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/sign-in")}

      user ->
        {:ok,
         socket
         |> assign(
           current_user: user,
           page_title: "Archive",
           search: "",
           room_filter: "all",
           sort: "votes",
           expanded: MapSet.new()
         )
         |> load()}
    end
  end

  @impl true
  def handle_event("search", params, socket),
    do: {:noreply, assign(socket, search: Map.get(params, "search", ""))}

  def handle_event("clear_search", _params, socket), do: {:noreply, assign(socket, search: "")}

  def handle_event("filter", params, socket),
    do:
      {:noreply,
       assign(socket,
         room_filter: Map.get(params, "room", "all"),
         sort: Map.get(params, "sort", "votes")
       )}

  def handle_event("expand", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, id),
        do: MapSet.delete(expanded, id),
        else: MapSet.put(expanded, id)

    {:noreply, assign(socket, expanded: expanded)}
  end

  defp load(socket) do
    sessions = Sessions.archive(socket.assigns.current_user.id)
    questions = Enum.flat_map(sessions, & &1.questions)

    assign(socket,
      sessions: sessions,
      totals: %{
        sessions: length(sessions),
        questions: length(questions),
        answered: Enum.count(questions, &(&1.status == :answered)),
        busiest: busiest(sessions)
      }
    )
  end

  defp busiest([]), do: nil

  defp busiest(sessions) do
    case Enum.max_by(sessions, &length(&1.questions), fn -> nil end) do
      nil -> nil
      %{questions: []} -> nil
      room -> room
    end
  end

  # The three controls compose: the filter narrows to one session, the search
  # runs over whatever is left, and the sort orders what matches.
  defp shown(assigns) do
    assigns.sessions
    |> Enum.filter(&(assigns.room_filter == "all" or assigns.room_filter == &1.id))
    |> Enum.map(fn room ->
      %{room | questions: sorted(matching(room.questions, assigns.search), assigns.sort)}
    end)
    |> Enum.reject(&(assigns.search != "" and &1.questions == []))
  end

  defp matching(questions, ""), do: questions

  defp matching(questions, search) do
    needle = String.downcase(String.trim(search))
    Enum.filter(questions, &String.contains?(String.downcase(&1.body), needle))
  end

  defp sorted(questions, "newest"),
    do: Enum.sort_by(questions, &DateTime.to_unix(&1.inserted_at, :microsecond), :desc)

  defp sorted(questions, _votes),
    do: Enum.sort_by(questions, &{-&1.vote_count, DateTime.to_unix(&1.inserted_at, :microsecond)})

  defp visible_questions(room, expanded) do
    if MapSet.member?(expanded, room.id),
      do: room.questions,
      else: Enum.take(room.questions, @preview)
  end

  defp hidden_count(room, expanded) do
    if MapSet.member?(expanded, room.id), do: 0, else: max(length(room.questions) - @preview, 0)
  end

  defp day(dt), do: Calendar.strftime(dt, "%-d %b %Y")

  defp asker(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp asker(_), do: "Anonymous"

  # The session's own line. While a search is running it counts what matched,
  # since the answered figure for the whole session would disagree with the one
  # row under it.
  defp session_meta(room, "") do
    Enum.join(
      [
        day(room.inserted_at),
        counted(length(room.questions), "question"),
        "#{room.answered_count} answered"
      ],
      " · "
    )
  end

  defp session_meta(room, _search),
    do:
      day(room.inserted_at) <>
        " · " <> counted(length(room.questions), "question") <> " matching"

  # Who asked, when, and whether it was answered in the room, as one line.
  defp meta(question) do
    [asker(question), day(question.inserted_at)]
    |> then(&if question.status == :answered, do: &1 ++ ["answered"], else: &1)
    |> Enum.join(" · ")
  end

  defp counted(1, word), do: "1 #{word}"
  defp counted(n, word), do: "#{n} #{word}s"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, shown: shown(assigns))

    ~H"""
    <div class="q-page">
      <QuorumWeb.Shell.header current_user={@current_user} />

      <div class="q-room-bar">
        <div class="q-room-title">
          <h1>Question archive</h1>
        </div>
        <div class="q-room-actions">
          <.link
            :if={@totals.questions > 0}
            href={~p"/archive/export"}
            class="q-button q-button--secondary"
          >
            Download CSV
          </.link>
        </div>
      </div>

      <main class="q-archive">
        <div :if={@totals.sessions == 0} class="q-panel q-archive-empty">
          <div class="q-label" style="font-size:17px;margin-bottom:6px;">
            Nothing to read back yet
          </div>
          <p class="q-meta" style="margin:0 0 18px;">
            Every session you run is kept here with the questions it drew, unless you set a room
            to delete them when it closes.
          </p>
          <.link href={~p"/start"} class="q-button">Open a room</.link>
        </div>

        <div :if={@totals.sessions > 0}>
          <div class="q-stats">
            <div class="q-stat">
              <span class="q-stat-figure">{@totals.sessions}</span>
              <span class="q-stat-label">{if @totals.sessions == 1, do: "session", else: "sessions"}</span>
            </div>
            <div class="q-stat">
              <span class="q-stat-figure">{@totals.questions}</span>
              <span class="q-stat-label">{if @totals.questions == 1, do: "question", else: "questions"} asked</span>
            </div>
            <div class="q-stat">
              <span class="q-stat-figure">{@totals.answered}</span>
              <span class="q-stat-label">answered in the room</span>
            </div>
            <div :if={@totals.busiest} class="q-stat">
              <span class="q-stat-figure">{length(@totals.busiest.questions)}</span>
              <span class="q-stat-label">the most one session drew</span>
              <span class="q-stat-note" title={@totals.busiest.name}>{@totals.busiest.name}</span>
            </div>
          </div>

          <form id="archive-filters" class="q-archive-bar" phx-change="filter">
            <div class="q-archive-search">
              <label class="q-sr-only" for="search">Search every question</label>
              <input
                id="search"
                name="search"
                class="q-input"
                value={@search}
                placeholder="Search every question you've been asked"
                autocomplete="off"
                phx-change="search"
                phx-debounce="150"
              />
              <button
                :if={@search != ""}
                type="button"
                class="q-button--link"
                phx-click="clear_search"
              >
                Clear
              </button>
            </div>

            <label class="q-sr-only" for="room">Session</label>
            <select id="room" name="room" class="q-select">
              <option value="all" selected={@room_filter == "all"}>Every session</option>
              <option :for={room <- @sessions} value={room.id} selected={@room_filter == room.id}>
                {room.name}
              </option>
            </select>

            <label class="q-sr-only" for="sort">Order</label>
            <select id="sort" name="sort" class="q-select">
              <option value="votes" selected={@sort == "votes"}>Most voted first</option>
              <option value="newest" selected={@sort == "newest"}>Newest first</option>
            </select>
          </form>

          <p :if={@search != ""} class="q-meta q-archive-count">
            {counted(Enum.sum(Enum.map(@shown, &length(&1.questions))), "question")} matching <strong>{@search}</strong>, across {counted(
              length(@shown),
              "session"
            )}.
          </p>

          <div :if={@shown == []} class="q-panel q-archive-empty">
            <div class="q-label" style="font-size:17px;margin-bottom:6px;">Nothing matches</div>
            <p class="q-meta" style="margin:0;">
              Try a shorter word, or put the session filter back to every session.
            </p>
          </div>

          <section :for={room <- @shown} class="q-panel q-archive-session">
            <header class="q-archive-head">
              <div style="min-width:0;">
                <h2>{room.name}</h2>
                <p class="q-meta">{session_meta(room, @search)}</p>
              </div>
              <.link navigate={~p"/host/#{room.host_token}"} class="q-button q-button--secondary">
                Open console
              </.link>
            </header>

            <p :if={room.questions == []} class="q-meta q-archive-none">
              This session drew no questions.
            </p>

            <ol :if={room.questions != []} class="q-archive-list">
              <li :for={question <- visible_questions(room, @expanded)} class="q-archive-row">
                <span class="q-archive-votes" aria-label={counted(question.vote_count, "vote")}>
                  {question.vote_count}
                </span>
                <div style="min-width:0;">
                  <p class="q-question">{question.body}</p>
                  <p class="q-meta">{meta(question)}</p>
                </div>
              </li>
            </ol>

            <button
              :if={hidden_count(room, @expanded) > 0}
              type="button"
              class="q-button--link"
              phx-click="expand"
              phx-value-id={room.id}
            >
              Show all {counted(length(room.questions), "question")}
            </button>
            <button
              :if={MapSet.member?(@expanded, room.id) and length(room.questions) > preview()}
              type="button"
              class="q-button--link"
              phx-click="expand"
              phx-value-id={room.id}
            >
              Show fewer
            </button>
          </section>
        </div>
      </main>

      <QuorumWeb.Shell.footer />
    </div>
    """
  end
end
