defmodule QuorumWeb.SettingsLive do
  @moduledoc """
  A room's settings, one tab per category, each with its own URL.

  Every control applies on change: there is no save button anywhere on these
  screens. A change sets the indicator to "Saving", does the work, and settles on
  "All changes saved", so the header always says where the room stands.

  Five tabs are drawn and one, Projection, is named but not drawn yet. The rail
  carries all six either way, so the shape of the settings never changes
  underneath someone as panes are added.
  """
  use QuorumWeb, :live_view

  alias Quorum.Sessions
  alias QuorumWeb.CurrentUser

  @tabs [
    {"room", "Room"},
    {"questions", "Questions"},
    {"moderation", "Moderation"},
    {"resources", "Readings and AI"},
    {"projection", "Projection"},
    {"appearance", "Appearance"}
  ]

  @built ~w(room questions moderation resources appearance)
  @slugs Enum.map(@tabs, &elem(&1, 0))

  @impl true
  def mount(%{"host_token" => token}, session, socket) do
    case Sessions.get_room_by_host_token(token) do
      {:ok, %{} = room} ->
        if connected?(socket), do: Sessions.subscribe(room.id)

        {:ok,
         socket
         |> assign(
           current_user: CurrentUser.from_session(session),
           room: room,
           tab: "room",
           status: :idle,
           search: "",
           confirm_delete: false,
           delete_typed: "",
           reading_error: nil,
           word_error: nil
         )
         |> load()}

      _ ->
        {:ok, assign(socket, room: nil, current_user: nil, page_title: "Settings")}
    end
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{room: nil}} = socket), do: {:noreply, socket}

  def handle_params(params, _uri, socket) do
    tab = params |> Map.get("tab", "room")

    if tab in @slugs do
      {:noreply, assign(socket, tab: tab, page_title: "#{label(tab)} settings")}
    else
      {:noreply,
       push_patch(socket, to: ~p"/host/#{socket.assigns.room.host_token}/settings/room")}
    end
  end

  @impl true
  def handle_info({:save, attrs}, socket) do
    case Sessions.update_settings(socket.assigns.room, attrs) do
      {:ok, room} -> {:noreply, socket |> assign(room: room, status: :saved) |> load()}
      {:error, _} -> {:noreply, assign(socket, status: :failed)}
    end
  end

  def handle_info(_message, %{assigns: %{room: nil}} = socket), do: {:noreply, socket}
  def handle_info(_message, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("save", params, socket), do: {:noreply, start_save(socket, attrs(params))}

  def handle_event("toggle", %{"field" => field}, socket) do
    key = String.to_existing_atom(field)
    {:noreply, start_save(socket, %{key => !Map.get(socket.assigns.room, key)})}
  end

  def handle_event("reset_appearance", _params, socket),
    do: {:noreply, start_save(socket, Sessions.appearance_defaults())}

  def handle_event("reset_room", _params, socket),
    do: {:noreply, start_save(socket, %{auto_close_at: nil})}

  def handle_event("reset_resources", _params, socket),
    do: {:noreply, start_save(socket, %{readings_pointer?: false})}

  def handle_event("reset_questions", _params, socket),
    do: {:noreply, start_save(socket, Sessions.question_defaults())}

  def handle_event("toggle_account_default", _params, %{assigns: %{current_user: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("toggle_account_default", _params, socket) do
    user = socket.assigns.current_user

    case Quorum.Accounts.set_moderation_default(user, !user.hold_for_review_default?) do
      {:ok, user} -> {:noreply, assign(socket, current_user: user, status: :saved)}
      {:error, _} -> {:noreply, assign(socket, status: :failed)}
    end
  end

  def handle_event("reset_moderation", _params, socket),
    do:
      {:noreply, socket |> assign(word_error: nil) |> start_save(Sessions.moderation_defaults())}

  ## Held words

  def handle_event("add_word", params, socket) do
    case Sessions.add_held_word(socket.assigns.room, Map.get(params, "word", "")) do
      {:ok, room} ->
        {:noreply, socket |> assign(room: room, word_error: nil, status: :saved) |> load()}

      {:error, :blank} ->
        {:noreply, assign(socket, word_error: "Type a word to hold.")}

      {:error, :duplicate} ->
        {:noreply, assign(socket, word_error: "That word is already on the list.")}

      {:error, _} ->
        {:noreply, assign(socket, word_error: "That word couldn't be added.")}
    end
  end

  def handle_event("remove_word", %{"word" => word}, socket) do
    {:ok, room} = Sessions.remove_held_word(socket.assigns.room, word)
    {:noreply, socket |> assign(room: room, word_error: nil, status: :saved) |> load()}
  end

  ## Readings

  # An element carrying phx-keyup takes the event instead of the window
  # binding, so Escape has to be answered here as well as in "key" below.
  def handle_event("search", %{"key" => "Escape"}, socket),
    do: {:noreply, socket |> assign(search: "") |> load()}

  def handle_event("search", %{"value" => value}, socket),
    do: {:noreply, socket |> assign(search: value) |> load()}

  def handle_event("add_reading", params, socket) do
    title = params |> Map.get("title", "") |> String.trim()

    if title == "" do
      {:noreply, assign(socket, reading_error: "A reading needs a title.")}
    else
      attrs = %{
        title: title,
        detail: blank_to_nil(Map.get(params, "detail", "")),
        url: blank_to_nil(Map.get(params, "url", ""))
      }

      case Sessions.add_reading(socket.assigns.room.id, attrs) do
        {:ok, _} ->
          {:noreply, socket |> assign(reading_error: nil, status: :saved) |> load()}

        {:error, _} ->
          {:noreply, assign(socket, reading_error: "That reading couldn't be added.")}
      end
    end
  end

  def handle_event("remove_reading", %{"id" => id}, socket) do
    with {:ok, reading} <- Sessions.get_reading(id),
         true <- reading.room_id == socket.assigns.room.id do
      Sessions.remove_reading(reading)
    end

    {:noreply, socket |> assign(status: :saved) |> load()}
  end

  ## Deleting the room

  def handle_event("confirm_delete", _params, socket),
    do: {:noreply, assign(socket, confirm_delete: true, delete_typed: "")}

  def handle_event("cancel_delete", _params, socket),
    do: {:noreply, assign(socket, confirm_delete: false, delete_typed: "")}

  def handle_event("delete_typing", %{"key" => "Escape"}, socket),
    do: {:noreply, assign(socket, confirm_delete: false, delete_typed: "")}

  def handle_event("delete_typing", %{"value" => value}, socket),
    do: {:noreply, assign(socket, delete_typed: value)}

  def handle_event("delete", _params, socket) do
    room = socket.assigns.room

    # Belt and braces: the button is disabled until the name matches, and the
    # server refuses anyway rather than trusting the client.
    if room.status == :closed and String.trim(socket.assigns.delete_typed) == room.name do
      Sessions.delete_room(room)
      {:noreply, push_navigate(socket, to: ~p"/")}
    else
      {:noreply, assign(socket, confirm_delete: false)}
    end
  end

  def handle_event("key", %{"key" => "Escape"}, socket),
    do: {:noreply, assign(socket, confirm_delete: false, delete_typed: "")}

  def handle_event("key", _params, socket), do: {:noreply, socket}

  ## Helpers

  defp start_save(socket, attrs) do
    send(self(), {:save, attrs})
    assign(socket, status: :saving)
  end

  defp attrs(params) do
    params
    |> Map.take(~w(name auto_close_at projection_light_from projection_light_to
                   projection_dark_from projection_dark_to projection_angle
                   question_max_length questions_per_student))
    |> Enum.reject(fn {_k, v} -> v == nil end)
    |> Map.new(fn {k, v} -> {String.to_existing_atom(k), normalise(k, v)} end)
  end

  defp normalise("auto_close_at", ""), do: nil

  defp normalise("auto_close_at", value) do
    case DateTime.from_iso8601(value <> ":00Z") do
      {:ok, at, _} -> at
      _ -> nil
    end
  end

  defp normalise("projection_angle", value), do: whole(value, 60)
  defp normalise("question_max_length", value), do: whole(value, 500)
  defp normalise("questions_per_student", value), do: whole(value, 0)

  defp normalise(_key, value), do: value

  defp whole(value, fallback) do
    case Integer.parse(to_string(value)) do
      {n, _} -> n
      _ -> fallback
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: String.trim(value)

  defp load(socket) do
    room_id = socket.assigns.room.id
    {:ok, room} = Sessions.get_room(room_id)
    readings = Sessions.list_readings(room_id)

    shown =
      case String.trim(socket.assigns.search) do
        "" -> readings
        term -> Enum.filter(readings, &matches?(&1, term))
      end

    %{held: held} = room_id |> Sessions.list_questions() |> Sessions.partition()

    assign(socket, room: room, readings: readings, shown: shown, held: length(held))
  end

  defp matches?(reading, term) do
    term = String.downcase(term)

    [reading.title, reading.detail, reading.url]
    |> Enum.filter(&is_binary/1)
    |> Enum.any?(&String.contains?(String.downcase(&1), term))
  end

  defp label(slug), do: @tabs |> Enum.find({slug, slug}, &(elem(&1, 0) == slug)) |> elem(1)

  defp built?(slug), do: slug in @built

  defp tabs, do: @tabs

  defp status_text(:saving), do: "Saving"
  defp status_text(:saved), do: "All changes saved"
  defp status_text(:failed), do: "That change didn't save. Try again."
  defp status_text(_), do: ""

  defp local_input(nil), do: ""

  defp local_input(at),
    do: at |> DateTime.truncate(:second) |> DateTime.to_iso8601() |> String.slice(0, 16)

  defp allowance_note(0),
    do: "A student can post as many as they like. Answered questions never count against anyone."

  defp allowance_note(1),
    do: "A student posts again once you've answered or hidden the one they have waiting."

  defp allowance_note(n),
    do: "A student posts again once you've answered or hidden one of the #{n} they have waiting."

  # The reserved-height tally under an instant-search field.
  defp tally("", _shown, _total), do: ""

  defp tally(_term, shown, total),
    do: "Showing #{shown} of #{total} #{if total == 1, do: "reading", else: "readings"}"

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
    <div class="q-reconnecting">Reconnecting now. Your settings are saved.</div>

    <div class="q-page" phx-window-keyup="key">
      <QuorumWeb.Shell.header current_user={@current_user} />

      <div class="q-room-bar">
        <div style="min-width:0;">
          <div class="q-room-title">
            <h1>Settings</h1>
          </div>
          <p class="q-meta" style="margin:6px 0 0;">
            {@room.name}. Every change applies as you make it.
          </p>
        </div>
        <div class="q-room-actions">
          <p class="q-status q-room-status" aria-live="polite">
            {status_text(@status)}
          </p>
          <.link navigate={~p"/host/#{@room.host_token}"} class="q-button q-button--secondary">
            Back to the console
          </.link>
        </div>
      </div>

      <div class="q-settings">
        <nav class="q-settings-rail" aria-label="Settings">
          <.link
            :for={{slug, name} <- tabs()}
            patch={~p"/host/#{@room.host_token}/settings/#{slug}"}
            class="q-tab"
            aria-current={@tab == slug && "page"}
          >
            {name}
            <span :if={!built?(slug)} class="q-tab-note">Not drawn yet</span>
          </.link>
        </nav>

        <main class="q-settings-pane">
          <%= case @tab do %>
            <% "room" -> %>
              <.room_pane room={@room} confirm_delete={@confirm_delete} delete_typed={@delete_typed} />
            <% "questions" -> %>
              <.questions_pane room={@room} />
            <% "moderation" -> %>
              <.moderation_pane
                room={@room}
                held={@held}
                current_user={@current_user}
                error={@word_error}
              />
            <% "resources" -> %>
              <.resources_pane
                room={@room}
                readings={@readings}
                shown={@shown}
                search={@search}
                error={@reading_error}
              />
            <% "appearance" -> %>
              <.appearance_pane room={@room} />
            <% slug -> %>
              <.undrawn_pane slug={slug} name={label(slug)} />
          <% end %>
        </main>
      </div>

      <QuorumWeb.Shell.footer />
    </div>
    """
  end

  ## Panes

  attr :room, :map, required: true
  attr :confirm_delete, :boolean, required: true
  attr :delete_typed, :string, required: true

  defp room_pane(assigns) do
    ~H"""
    <section class="q-pane">
      <h2>Room</h2>

      <form id="room-name-form" phx-change="save" class="q-field">
        <label class="q-label" for="name">Name</label>
        <input id="name" name="name" class="q-input" value={@room.name} maxlength="200" />
        <p class="q-meta">Students never see this. It's how you tell your own rooms apart.</p>
      </form>

      <form id="auto-close-form" phx-change="save" class="q-field">
        <label class="q-label" for="auto_close_at">Close automatically at</label>
        <input
          id="auto_close_at"
          name="auto_close_at"
          type="datetime-local"
          class="q-input"
          value={local_input(@room.auto_close_at)}
        />
        <p class="q-meta">
          Leave it empty to keep the room open until you close it yourself.
        </p>
      </form>

      <hr class="q-divider" style="margin:8px 0;" />

      <h3>Join code</h3>
      <p class="q-meta">
        The code students type is <strong>{@room.join_code}</strong>. Issue a new one from the
        console if it reaches the wrong room.
      </p>

      <hr class="q-divider" style="margin:8px 0;" />

      <h3>Delete this room</h3>
      <p class="q-meta">
        Deleting removes the room, every question in it, and every vote. It can't be undone.
      </p>
      <%= if @room.status == :open do %>
        <button type="button" class="q-button q-button--destructive" disabled="disabled">
          Delete room
        </button>
        <p class="q-meta">Close the session first. Deleting is permanent.</p>
      <% else %>
        <button type="button" class="q-button q-button--destructive" phx-click="confirm_delete">
          Delete room
        </button>
      <% end %>

      <div style="margin-top:8px;">
        <button type="button" class="q-button--link" phx-click="reset_room">Reset this tab</button>
      </div>
    </section>

    <div
      :if={@confirm_delete}
      role="dialog"
      aria-modal="true"
      aria-labelledby="delete-title"
      class="q-dialog"
    >
      <div class="q-dialog-card">
        <div id="delete-title" class="q-label" style="font-size:18px;margin-bottom:8px;">
          Delete {@room.name}?
        </div>
        <p class="q-meta" style="margin-bottom:16px;">
          This removes the room, its questions, and its votes. It can't be undone. Type the room's
          name to confirm.
        </p>
        <label class="q-label" for="delete-confirm" style="display:block;margin-bottom:8px;">
          Room name
        </label>
        <input
          id="delete-confirm"
          class="q-input"
          value={@delete_typed}
          phx-keyup="delete_typing"
          autocomplete="off"
        />
        <div style="display:flex;justify-content:flex-end;gap:12px;margin-top:20px;flex-wrap:wrap;">
          <button
            type="button"
            class="q-button q-button--secondary"
            phx-click="cancel_delete"
            phx-mounted={JS.focus()}
          >
            Keep the room
          </button>
          <button
            :if={String.trim(@delete_typed) == @room.name}
            type="button"
            class="q-button q-button--destructive-solid"
            phx-click="delete"
          >
            Delete room
          </button>
          <button
            :if={String.trim(@delete_typed) != @room.name}
            type="button"
            class="q-button q-button--destructive-solid"
            disabled="disabled"
          >
            Delete room
          </button>
        </div>
        <p :if={String.trim(@delete_typed) != @room.name} class="q-meta" style="text-align:right;">
          Type the room's name to turn this on.
        </p>
      </div>
    </div>
    """
  end

  attr :room, :map, required: true

  defp questions_pane(assigns) do
    ~H"""
    <section class="q-pane">
      <h2>Questions</h2>

      <form id="question-limits-form" phx-change="save" class="q-field">
        <label class="q-label" for="question_max_length">Longest question</label>
        <select id="question_max_length" name="question_max_length" class="q-input">
          <option
            :for={n <- [140, 280, 500, 1000]}
            value={n}
            selected={@room.question_max_length == n}
          >
            {n} characters
          </option>
        </select>
        <p class="q-meta">
          The composer counts down to this, and a longer question is refused rather than cut short.
        </p>
      </form>

      <form id="question-allowance-form" phx-change="save" class="q-field">
        <label class="q-label" for="questions_per_student">Questions waiting per student</label>
        <select id="questions_per_student" name="questions_per_student" class="q-input">
          <option value="0" selected={@room.questions_per_student == 0}>No limit</option>
          <option :for={n <- 1..5} value={n} selected={@room.questions_per_student == n}>
            {n} at a time
          </option>
        </select>
        <p class="q-meta">
          {allowance_note(@room.questions_per_student)}
        </p>
      </form>

      <hr class="q-divider" style="margin:8px 0;" />

      <div class="q-field">
        <div class="q-switch-row">
          <button
            type="button"
            role="switch"
            aria-checked={to_string(@room.allow_display_name?)}
            class={["q-switch", @room.allow_display_name? && "q-switch--on"]}
            phx-click="toggle"
            phx-value-field="allow_display_name?"
          >
            <span class="q-switch-knob"></span>
          </button>
          <span class="q-label">
            Let students sign a question, {if @room.allow_display_name?, do: "on", else: "off"}
          </span>
        </div>
        <p class="q-meta">
          Signing is the student's choice either way. Turning this off drops the name field and
          posts every question anonymously, including any name a stale page still sends.
        </p>
      </div>

      <hr class="q-divider" style="margin:8px 0;" />

      <h3>After the session</h3>
      <.hold_switch
        field="keep_questions?"
        on={@room.keep_questions?}
        label="Keep this room's questions"
      >
        A term of questions is the record of what didn't land: which weeks drew nothing, which
        drew the same question forty times, what to put in the next tutorial. Turning this off
        deletes every question in this room, and its votes, the moment you close the session.
        There's no undo.
      </.hold_switch>

      <div style="margin-top:8px;">
        <button type="button" class="q-button--link" phx-click="reset_questions">
          Reset this tab
        </button>
      </div>
    </section>
    """
  end

  attr :field, :string, required: true
  attr :on, :boolean, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  defp hold_switch(assigns) do
    ~H"""
    <div class="q-field">
      <div class="q-switch-row">
        <button
          type="button"
          role="switch"
          aria-checked={to_string(@on)}
          class={["q-switch", @on && "q-switch--on"]}
          phx-click="toggle"
          phx-value-field={@field}
        >
          <span class="q-switch-knob"></span>
        </button>
        <span class="q-label">{@label}, {if @on, do: "on", else: "off"}</span>
      </div>
      <p class="q-meta">{render_slot(@inner_block)}</p>
    </div>
    """
  end

  attr :room, :map, required: true
  attr :held, :integer, required: true
  attr :current_user, :map, default: nil
  attr :error, :string, default: nil

  defp moderation_pane(assigns) do
    ~H"""
    <section class="q-pane">
      <h2>Moderation</h2>

      <p class="q-meta" style="margin-top:0;">
        Four things can hold a question. Any one of them is enough, and every one holds rather than
        refuses, so the worst a mistake costs an asker is a wait.
      </p>

      <.hold_switch
        field="hold_for_review?"
        on={@room.hold_for_review?}
        label="Hold every question for review"
      >
        Off, a question reaches the room as soon as it's posted and you can hide it from the
        console. On, nothing reaches the room until you approve it, and the asker sees their own
        question waiting so they don't post it twice.
      </.hold_switch>

      <.hold_switch
        field="hold_first_question?"
        on={@room.hold_first_question?}
        label="Hold a student's first question"
      >
        Students have no accounts here, so the only history a room can read is what this browser
        has had approved in it. Once you approve one question from someone, the rest go straight
        through.
      </.hold_switch>

      <.hold_switch field="hold_links?" on={@room.hold_links?} label="Hold anything with a link">
        A link is how a room full of phones gets advertised at. Web addresses count, and so does a
        bare domain; file names like Node.js don't.
      </.hold_switch>

      <div :if={@current_user} class="q-field">
        <label class="q-check">
          <input
            type="checkbox"
            checked={@current_user.hold_for_review_default?}
            phx-click="toggle_account_default"
          />
          <span class="q-label">Start the rooms I open with the first of these on</span>
        </label>
        <p class="q-meta">
          Seeds a new room only. This one keeps whatever it says above, so changing it now doesn't
          rewrite a session that's already running.
        </p>
      </div>

      <p :if={@held > 0} class="q-meta">
        <.link navigate={~p"/host/#{@room.host_token}"} class="q-button--link">
          {@held} {if @held == 1, do: "question is", else: "questions are"} waiting for review
        </.link>
        on the console.
      </p>

      <hr class="q-divider" style="margin:8px 0;" />

      <h3>Hold anything using these words</h3>
      <p class="q-meta" style="margin-top:0;">
        The fourth trigger, and the only one you write yourself. A word matches whole, so "class"
        doesn't trip on "ass".
      </p>

      <form id="add-word-form" phx-submit="add_word" class="q-word-form">
        <div>
          <label class="q-sr-only" for="word">Word to hold</label>
          <input
            id="word"
            name="word"
            class="q-input"
            maxlength="40"
            autocomplete="off"
            placeholder="A word or name"
          />
        </div>
        <button type="submit" class="q-button">Add word</button>
      </form>
      <p class="q-status" style={@error && "color:var(--q-destructive);"}>{@error}</p>

      <p :if={@room.held_words == []} class="q-meta">
        No words held. Add one above, or leave the list empty and use the switch when you need it.
      </p>

      <ul :if={@room.held_words != []} class="q-word-list">
        <li :for={word <- @room.held_words}>
          <span class="q-label">{word}</span>
          <button
            type="button"
            class="q-button q-button--destructive"
            phx-click="remove_word"
            phx-value-word={word}
            aria-label={"Stop holding #{word}"}
          >
            Remove
          </button>
        </li>
      </ul>

      <div style="margin-top:8px;">
        <button type="button" class="q-button--link" phx-click="reset_moderation">
          Reset this tab
        </button>
      </div>
    </section>
    """
  end

  attr :room, :map, required: true
  attr :readings, :list, required: true
  attr :shown, :list, required: true
  attr :search, :string, required: true
  attr :error, :string, default: nil

  defp resources_pane(assigns) do
    ~H"""
    <section class="q-pane">
      <h2>Readings and AI</h2>

      <div class="q-field">
        <div class="q-switch-row">
          <button
            type="button"
            role="switch"
            aria-checked={to_string(@room.readings_pointer?)}
            class={["q-switch", @room.readings_pointer? && "q-switch--on"]}
            phx-click="toggle"
            phx-value-field="readings_pointer?"
          >
            <span class="q-switch-knob"></span>
          </button>
          <span class="q-label">
            Point students to approved readings, {if @room.readings_pointer?, do: "on", else: "off"}
          </span>
        </div>
        <p class="q-meta">
          When it's on, a student who posts a question is shown items from the list below and
          nothing else. Matching arrives with the model work; the list is stored and ready for it.
        </p>
      </div>

      <hr class="q-divider" style="margin:8px 0;" />

      <h3>Approved readings</h3>

      <form id="add-reading-form" phx-submit="add_reading" class="q-reading-form">
        <div>
          <label class="q-label" for="title">Title</label>
          <input
            id="title"
            name="title"
            class="q-input"
            maxlength="200"
            placeholder="Nagel, What Is It Like to Be a Bat?"
          />
        </div>
        <div>
          <label class="q-label" for="detail">Where</label>
          <input
            id="detail"
            name="detail"
            class="q-input"
            maxlength="120"
            placeholder="pp. 435 to 441"
          />
        </div>
        <div>
          <label class="q-label" for="url">Link</label>
          <input
            id="url"
            name="url"
            type="url"
            class="q-input"
            maxlength="500"
            placeholder="https://"
          />
        </div>
        <button type="submit" class="q-button">Add reading</button>
      </form>
      <p class="q-status" style={@error && "color:var(--q-destructive);"}>{@error}</p>

      <div :if={@readings != []}>
        <label class="q-sr-only" for="reading-search">Search readings</label>
        <input
          id="reading-search"
          class="q-input"
          value={@search}
          placeholder="Search readings"
          autocomplete="off"
          phx-keyup="search"
          aria-label="Search readings"
        />
        <p class="q-status" aria-live="polite">{tally(@search, length(@shown), length(@readings))}</p>
      </div>

      <p :if={@readings == []} class="q-meta">
        No readings yet. Add the first one above, and it becomes the only material a suggestion can
        draw on.
      </p>

      <p :if={@readings != [] and @shown == []} class="q-meta">
        No readings match that search.
      </p>

      <ul :if={@shown != []} class="q-reading-list">
        <li :for={reading <- @shown}>
          <div style="min-width:0;">
            <div class="q-label">{reading.title}</div>
            <p class="q-meta" style="margin:2px 0 0;">
              <span :if={reading.detail}>{reading.detail}</span>
              <a :if={reading.url} href={reading.url} target="_blank" rel="noopener">{reading.url}</a>
              <span :if={is_nil(reading.detail) and is_nil(reading.url)}>No page reference</span>
            </p>
          </div>
          <button
            type="button"
            class="q-button q-button--destructive"
            phx-click="remove_reading"
            phx-value-id={reading.id}
          >
            Remove
          </button>
        </li>
      </ul>

      <div style="margin-top:8px;">
        <button type="button" class="q-button--link" phx-click="reset_resources">
          Reset this tab
        </button>
      </div>
    </section>
    """
  end

  attr :room, :map, required: true

  defp appearance_pane(assigns) do
    ~H"""
    <section class="q-pane">
      <h2>Appearance</h2>
      <p class="q-meta">
        These change the projection for this room only. Every value starts at the design default.
      </p>

      <form id="appearance-form" phx-change="save">
        <h3>Lit hall</h3>
        <div class="q-colour-row">
          <.colour id="projection_light_from" label="From" value={@room.projection_light_from} />
          <.colour id="projection_light_to" label="To" value={@room.projection_light_to} />
        </div>

        <h3>Dark hall</h3>
        <div class="q-colour-row">
          <.colour id="projection_dark_from" label="From" value={@room.projection_dark_from} />
          <.colour id="projection_dark_to" label="To" value={@room.projection_dark_to} />
        </div>

        <div class="q-field">
          <label class="q-label" for="projection_angle">Gradient angle</label>
          <div style="display:flex;align-items:center;gap:14px;">
            <input
              id="projection_angle"
              name="projection_angle"
              type="range"
              min="0"
              max="360"
              step="15"
              value={@room.projection_angle}
              style="flex:1;"
            />
            <span class="q-label" style="min-width:56px;">{@room.projection_angle} deg</span>
          </div>
        </div>
      </form>

      <div class="q-field">
        <div class="q-switch-row">
          <button
            type="button"
            role="switch"
            aria-checked={to_string(@room.projection_drift?)}
            class={["q-switch", @room.projection_drift? && "q-switch--on"]}
            phx-click="toggle"
            phx-value-field="projection_drift?"
          >
            <span class="q-switch-knob"></span>
          </button>
          <span class="q-label">
            Drift the gradient slowly, {if @room.projection_drift?, do: "on", else: "off"}
          </span>
        </div>
        <p class="q-meta">
          Only on the joining screen, and it holds still for anyone who has asked for reduced motion.
        </p>
      </div>

      <h3>Preview</h3>
      <div class="q-appearance-preview">
        <div style={"background:linear-gradient(#{@room.projection_angle}deg, #{@room.projection_light_from}, #{@room.projection_light_to});"}>
          <span style="color:var(--q-ink);">Lit hall</span>
        </div>
        <div style={"background:linear-gradient(#{@room.projection_angle}deg, #{@room.projection_dark_from}, #{@room.projection_dark_to});"}>
          <span style="color:var(--q-on-dark);">Dark hall</span>
        </div>
      </div>

      <div style="margin-top:8px;">
        <button type="button" class="q-button--link" phx-click="reset_appearance">
          Reset this tab
        </button>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true

  defp colour(assigns) do
    ~H"""
    <div class="q-colour">
      <label class="q-label" for={@id}>{@label}</label>
      <div class="q-colour-controls">
        <input type="color" name={@id} value={@value} aria-label={"#{@label} colour picker"} />
        <input
          id={@id}
          name={@id}
          class="q-input"
          value={@value}
          maxlength="7"
          spellcheck="false"
          aria-label={"#{@label} hex value"}
        />
      </div>
    </div>
    """
  end

  attr :slug, :string, required: true
  attr :name, :string, required: true

  defp undrawn_pane(assigns) do
    ~H"""
    <section class="q-pane">
      <h2>{@name}</h2>
      <p class="q-meta">{undrawn_copy(@slug)}</p>
      <p class="q-meta">
        The tab is here so the settings keep their shape as panes are added. Nothing is missing
        from your room in the meantime.
      </p>
    </section>
    """
  end

  defp undrawn_copy("projection"),
    do:
      "What the projection shows and how large it draws it will live here. " <>
        "Today it shows the join code, then whichever question you spotlight."

  defp undrawn_copy(_), do: "This pane hasn't been drawn yet."
end
