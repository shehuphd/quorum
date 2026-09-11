defmodule QuorumWeb.JoinLive do
  @moduledoc """
  Join a session by typing its code. Five slots rather than one text field: the
  code on the wall is five characters, so the screen asks for five characters
  and shows where the next one goes.

  The fifth character resolves the room. From that point the page names the
  session, counts who is already in it, and takes the room's own gradient, so
  the phone in a student's hand reads as a second window on the wall in front
  of them. The way in appears only once there is a room to go into.
  """
  use QuorumWeb, :live_view

  import QuorumWeb.Wording

  alias Quorum.Sessions
  alias QuorumWeb.Brand

  @length 5

  # The template reads this through a function: @length in HEEx would be an
  # assign, not the module attribute.
  defp code_length, do: @length

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: "Join",
        code: "",
        room: nil,
        state: :typing,
        connected: 0,
        question_count: 0,
        show_name: false,
        name: "",
        watching: nil
      )
      |> resolve(Map.get(params, "code", ""))

    {:ok, socket}
  end

  @impl true
  def handle_event("typed", params, socket),
    do: {:noreply, resolve(socket, Map.get(params, "code", ""))}

  def handle_event("name", params, socket),
    do: {:noreply, assign(socket, name: params |> Map.get("name", "") |> String.slice(0, 60))}

  def handle_event("toggle_name", _params, socket) do
    show? = !socket.assigns.show_name

    {:noreply,
     assign(socket, show_name: show?, name: if(show?, do: socket.assigns.name, else: ""))}
  end

  # Any change in the room the student is looking at: a question posted, someone
  # else joining, the presenter switching the hall light.
  @impl true
  def handle_info(_message, %{assigns: %{room: nil}} = socket), do: {:noreply, socket}
  def handle_info(_message, socket), do: {:noreply, reload(socket)}

  # Everything the screen shows follows from the five characters, so one path
  # handles the query-string prefill, every keystroke, and a paste.
  defp resolve(socket, typed) do
    code = typed |> to_string() |> String.replace(~r/[^A-Za-z0-9]/, "") |> String.upcase()
    code = String.slice(code, 0, @length)

    if String.length(code) == @length do
      case Sessions.get_room_by_code(code) do
        {:ok, %{} = room} -> socket |> assign(code: code) |> watch(room) |> reload()
        _ -> socket |> unwatch() |> assign(code: code, room: nil, state: :not_found)
      end
    else
      socket |> unwatch() |> assign(code: code, room: nil, state: :typing, show_name: false)
    end
  end

  defp watch(socket, room) do
    if connected?(socket) and socket.assigns.watching != room.id do
      unwatch(socket)
      Sessions.subscribe(room.id)
      assign(socket, room: room, watching: room.id)
    else
      assign(socket, room: room)
    end
  end

  defp unwatch(%{assigns: %{watching: nil}} = socket), do: socket

  defp unwatch(socket) do
    Sessions.unsubscribe(socket.assigns.watching)
    assign(socket, watching: nil)
  end

  defp reload(socket) do
    {:ok, room} = Sessions.get_room(socket.assigns.room.id)
    connected = room.id |> Sessions.topic() |> QuorumWeb.Presence.list() |> map_size()

    assign(socket,
      room: room,
      state: if(room.status == :open, do: :resolved, else: :closed),
      connected: connected,
      question_count: Sessions.count_questions(room.id)
    )
  end

  defp dark?(nil), do: true
  defp dark?(room), do: room.projection_dark?

  defp drift?(nil), do: true
  defp drift?(room), do: room.projection_drift?

  # The room's own gradient, as the longhand: the `background` shorthand would
  # reset background-size and the drift animates the position across it.
  defp slots(code) do
    typed = String.graphemes(code)
    for i <- 0..(@length - 1), do: {i, Enum.at(typed, i), i == length(typed)}
  end

  # The button names the room it opens. A full title would wrap it, and a
  # session's title is usually its first clause: "Physics 201, Waves and
  # Optics" is Physics 201 to everyone in the hall.
  defp short_name(name) do
    name = name |> String.split(",") |> hd() |> String.trim()
    if String.length(name) > 24, do: String.slice(name, 0, 23) <> "…", else: name
  end

  defp badge(""), do: "Anonymous"
  defp badge(name), do: name

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class={["q-join", dark?(@room) && "q-join--dark", drift?(@room) && "q-join--drift"]}
      style={hall(@room, @room && @room.projection_dark?)}
    >
      <header class="q-join-top">
        <.link navigate={~p"/"} aria-label="Quorum home">
          <Brand.logo on_dark={dark?(@room)} size={22} />
        </.link>
        <span class="q-join-badge">{badge(@name)}</span>
      </header>

      <main class="q-join-main">
        <div class="q-join-inner">
          <h1 :if={@state in [:typing, :not_found]} class="q-join-title">
            Type the code<br />on the screen.
          </h1>
          <h1 :if={@state in [:resolved, :closed]} class="q-join-title">{@room.name}</h1>

          <.form for={to_form(%{})} action={~p"/join"} method="post" autocomplete="off">
            <label class="q-sr-only" for="code">Session code</label>

            <div class="q-slots">
              <input
                id="code"
                name="code"
                class="q-slots-input"
                value={@code}
                maxlength={code_length()}
                autocomplete="off"
                autocapitalize="characters"
                autocorrect="off"
                spellcheck="false"
                autofocus
                inputmode="text"
                aria-describedby="join-status"
                phx-change="typed"
                phx-debounce="60"
              />
              <span
                :for={{i, char, caret?} <- slots(@code)}
                class={["q-slot", caret? && "q-slot--caret"]}
                aria-hidden="true"
                id={"slot-#{i}"}
              >
                {char}
              </span>
            </div>

            <div
              id="join-status"
              class={["q-join-status", @state == :not_found && "q-join-status--warn"]}
              aria-live="polite"
            >
              <%= case @state do %>
                <% :typing -> %>
                  <span class="q-skeleton" style="width:54px;"></span>
                  <span class="q-skeleton" style="width:96px;"></span>
                  <span class="q-sr-only">
                    {code_length() - String.length(@code)} characters to go.
                  </span>
                <% :not_found -> %>
                  No session uses the code {@code}.
                <% :resolved -> %>
                  <span class="q-dot"></span>
                  In session &middot; {@connected} connected &middot; {counted(
                    @question_count,
                    "question"
                  )}
                <% :closed -> %>
                  <span class="q-dot q-dot--off"></span>
                  Session closed &middot; {counted(@question_count, "question")} asked
              <% end %>
            </div>

            <div :if={@show_name} class="q-join-name">
              <label class="q-sr-only" for="name">Your display name</label>
              <input
                id="name"
                name="name"
                value={@name}
                maxlength="60"
                placeholder="Your name"
                phx-change="name"
                phx-debounce="200"
              />
            </div>

            <div class="q-join-actions">
              <button
                type="submit"
                class="q-button q-join-go"
                disabled={@state in [:typing, :not_found]}
              >
                <%= case @state do %>
                  <% :resolved -> %>
                    Join {short_name(@room.name)}
                  <% :closed -> %>
                    Read what was asked
                  <% _ -> %>
                    Join session
                <% end %>
              </button>
              <a href={~p"/demo"} class="q-join-demo">See demo</a>
            </div>
          </.form>
        </div>
      </main>

      <footer class="q-join-foot">
        <div>
          <p>You remain anonymous unless you choose otherwise.</p>
        </div>
        <QuorumWeb.Shell.byline />
        <button
          :if={@state == :resolved and @room.allow_display_name?}
          type="button"
          class="q-join-link"
          phx-click="toggle_name"
        >
          {if @show_name, do: "Stay anonymous", else: "Add a display name"}
        </button>
      </footer>
    </div>
    """
  end
end
