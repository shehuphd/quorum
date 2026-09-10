defmodule QuorumWeb.SettingsLive do
  @moduledoc """
  A room's settings, one tab per category, each with its own URL.

  Every control applies on change: there is no save button anywhere on these
  screens. A change sets the indicator to "Saving", does the work, and settles on
  "All changes saved", so the header always says where the room stands.

  All seven tabs are drawn. The rail carries them in a fixed order, so the shape of
  the settings doesn't move under someone as panes change.
  """
  use QuorumWeb, :live_view

  alias Quorum.Sessions
  alias QuorumWeb.CurrentUser

  @tabs [
    {"room", "Room"},
    {"questions", "Questions"},
    {"moderation", "Moderation"},
    {"resources", "Readings"},
    {"projection", "Projection"},
    {"appearance", "Appearance"},
    {"ai", "API keys"}
  ]

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
           tz_offset: tz_offset(socket),
           tab: "room",
           status: :idle,
           search: "",
           confirm_delete: false,
           delete_typed: "",
           reading_error: nil,
           word_error: nil,
           word_seq: 0,
           ai_up?: false,
           ai_targets: [],
           ai_providers: [],
           ai_provider: "",
           ai_key_status: nil,
           ai_form_seq: 0,
           ai_spend: nil
         )
         |> load()}

      _ ->
        {:ok, assign(socket, room: nil, current_user: nil, page_title: "Settings")}
    end
  end

  # Minutes east of UTC, from the browser at connect. The first, static render
  # has no socket to ask, so it draws the time in UTC and the connected render
  # replaces it a moment later.
  defp tz_offset(socket) do
    case get_connect_params(socket) do
      %{"tz_offset" => offset} when is_integer(offset) -> offset
      _ -> 0
    end
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{room: nil}} = socket), do: {:noreply, socket}

  def handle_params(params, _uri, socket) do
    tab = params |> Map.get("tab", "room")

    if tab in @slugs do
      socket = assign(socket, tab: tab, page_title: "#{label(tab)} settings")
      socket = if tab == "ai", do: load_ai(socket), else: socket
      {:noreply, socket}
    else
      {:noreply,
       push_patch(socket, to: ~p"/host/#{socket.assigns.room.host_token}/settings/room")}
    end
  end

  @impl true
  def handle_info({:ai_check, provider, key}, socket) do
    socket =
      case Quorum.AI.add_key(%{provider: provider, key: key}) do
        {:ok, %{"models" => models}} ->
          socket
          |> assign(
            ai_key_status: {:ok, "Key accepted: #{length(models)} usable models."},
            ai_form_seq: socket.assigns.ai_form_seq + 1,
            ai_provider: ""
          )
          |> load_ai()

        {:error, {:sidecar, _status, message}} ->
          assign(socket, ai_key_status: {:error, message})

        {:error, _} ->
          assign(socket,
            ai_key_status: {:error, "The AI service isn't answering. Is the sidecar running?"}
          )
      end

    {:noreply, socket}
  end

  def handle_info({:save, attrs}, socket) do
    case Sessions.update_settings(socket.assigns.room, attrs) do
      {:ok, room} -> {:noreply, socket |> assign(room: room, status: :saved) |> load()}
      {:error, _} -> {:noreply, assign(socket, status: :failed)}
    end
  end

  def handle_info(_message, %{assigns: %{room: nil}} = socket), do: {:noreply, socket}
  def handle_info(_message, socket), do: {:noreply, load(socket)}

  @impl true
  # The form hot-saves: a provider pick is kept, and a key is tested the
  # moment it stops being typed (debounced change) or the field is left.
  def handle_event("ai_form", params, socket) do
    provider = Map.get(params, "provider", socket.assigns.ai_provider)
    socket = assign(socket, ai_provider: provider)
    {:noreply, maybe_check_key(socket, provider, Map.get(params, "key", ""))}
  end

  def handle_event("ai_key_blur", %{"value" => key}, socket),
    do: {:noreply, maybe_check_key(socket, socket.assigns.ai_provider, key)}

  def handle_event("ai_pin", %{"target" => name} = params, socket) do
    model = Map.get(params, "model", "")
    Quorum.AI.pin_model(name, if(model == "", do: nil, else: model))
    {:noreply, load_ai(socket)}
  end

  def handle_event("ai_remove", %{"name" => name}, socket) do
    Quorum.AI.remove_key(name)
    {:noreply, socket |> assign(ai_key_status: nil) |> load_ai()}
  end

  def handle_event("ai_reload", _params, socket), do: {:noreply, load_ai(socket)}

  def handle_event("ai_clear_spend", _params, socket) do
    Quorum.AI.clear_spend()
    {:noreply, assign(socket, ai_spend: Quorum.AI.spend())}
  end

  def handle_event("save", params, socket),
    do: {:noreply, start_save(socket, attrs(params, socket.assigns.tz_offset))}

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

  def handle_event("reset_projection", _params, socket),
    do: {:noreply, start_save(socket, Sessions.projection_defaults())}

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
      {:noreply,
       socket
       |> assign(word_error: nil, word_seq: socket.assigns.word_seq + 1)
       |> start_save(Sessions.moderation_defaults())}

  ## Held words

  # The whole list is one field. Blurring saves it, deduped and sorted, and the
  # bumped sequence replaces the textarea so the sorted order is what stays on screen.
  def handle_event("save_words", %{"value" => text}, socket) do
    {:noreply,
     socket
     |> assign(word_error: nil, word_seq: socket.assigns.word_seq + 1)
     |> start_save(%{held_words: Sessions.parse_held_words(text)})}
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

  defp maybe_check_key(socket, provider, key) do
    key = String.trim(key)

    cond do
      key == "" ->
        socket

      provider == "" ->
        assign(socket, ai_key_status: {:error, "Pick the provider the key is for first."})

      true ->
        # Two renders: the checking line appears now, the verdict when the
        # provider answers.
        send(self(), {:ai_check, provider, key})
        assign(socket, ai_key_status: :checking)
    end
  end

  defp load_ai(socket) do
    case Quorum.AI.targets() do
      {:ok, targets} ->
        providers =
          case Quorum.AI.providers() do
            {:ok, providers} -> providers
            _ -> []
          end

        assign(socket,
          ai_up?: true,
          ai_targets: targets,
          ai_providers: providers,
          ai_spend: Quorum.AI.spend()
        )

      {:error, _down} ->
        assign(socket, ai_up?: false, ai_targets: [], ai_spend: Quorum.AI.spend())
    end
  end

  defp attrs(params, offset) do
    params
    |> Map.take(~w(name auto_close_at projection_light_from projection_light_to
                   projection_dark_from projection_dark_to projection_angle
                   question_max_length questions_per_student projection_question_scale))
    |> Enum.reject(fn {_k, v} -> v == nil end)
    |> Map.new(fn {k, v} -> {String.to_existing_atom(k), normalise(k, v, offset)} end)
  end

  defp normalise("auto_close_at", "", _offset), do: nil

  defp normalise("auto_close_at", value, offset) do
    case DateTime.from_iso8601(value <> ":00Z") do
      {:ok, at, _} -> DateTime.add(at, -offset * 60, :second)
      _ -> nil
    end
  end

  defp normalise(key, value, _offset), do: normalise(key, value)

  # The angle turns both gradients, but a pair of close tones reads as flat at
  # preview size, so the arrow shows which way the gradient runs whatever the
  # colours are. It points the way the CSS angle does: 0 up, 90 to the right.
  attr :angle, :integer, required: true

  defp angle_mark(assigns) do
    ~H"""
    <svg class="q-angle-mark" viewBox="0 0 28 28" aria-hidden="true" focusable="false">
      <g transform={"rotate(#{@angle} 14 14)"}>
        <line x1="14" y1="21.5" x2="14" y2="6.5" />
        <polyline points="10,10.5 14,6.5 18,10.5" />
      </g>
    </svg>
    """
  end

  defp normalise("projection_angle", value), do: whole(value, 60)
  defp normalise("question_max_length", value), do: whole(value, 500)
  defp normalise("questions_per_student", value), do: whole(value, 0)
  defp normalise("projection_question_scale", value), do: whole(value, 100)

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

  defp tabs, do: @tabs

  defp status_text(:saving), do: "Saving"
  defp status_text(:saved), do: "All changes saved"
  defp status_text(:failed), do: "That change didn't save. Try again."
  defp status_text(_), do: ""

  # A `datetime-local` field speaks the reader's own clock, and the room stores
  # UTC, so the offset the browser reported at connect carries between them.
  defp local_input(nil, _offset), do: ""

  defp local_input(at, offset) do
    at
    |> DateTime.truncate(:second)
    |> DateTime.add(offset * 60, :second)
    |> DateTime.to_iso8601()
    |> String.slice(0, 16)
  end

  # Named rather than numbered, because a percentage means nothing until it's
  # on a wall. The note beside it says what each one is for.
  defp scales, do: [{75, "Small"}, {100, "Standard"}, {125, "Large"}, {150, "Largest"}]

  defp scale_note(75),
    do: "For a seminar room, or a long question you'd rather not have wrapping."

  defp scale_note(100), do: "What the design fixes: readable from the back of a full hall."
  defp scale_note(125), do: "For a deep room, or a projector that isn't bright enough."
  defp scale_note(150), do: "As large as it goes. A long question will take the whole wall."
  defp scale_note(_), do: ""

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
          <p class="q-meta" style="margin:6px 0 0;">{@room.name}</p>
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
          </.link>
        </nav>

        <main class="q-settings-pane">
          <%= case @tab do %>
            <% "room" -> %>
              <.room_pane
                room={@room}
                tz_offset={@tz_offset}
                confirm_delete={@confirm_delete}
                delete_typed={@delete_typed}
              />
            <% "questions" -> %>
              <.questions_pane room={@room} />
            <% "moderation" -> %>
              <.moderation_pane
                room={@room}
                held={@held}
                current_user={@current_user}
                error={@word_error}
                seq={@word_seq}
              />
            <% "resources" -> %>
              <.resources_pane
                room={@room}
                readings={@readings}
                shown={@shown}
                search={@search}
                error={@reading_error}
              />
            <% "projection" -> %>
              <.projection_pane room={@room} />
            <% "ai" -> %>
              <.ai_pane
                up?={@ai_up?}
                targets={@ai_targets}
                providers={@ai_providers}
                provider={@ai_provider}
                key_status={@ai_key_status}
                form_seq={@ai_form_seq}
                spend={@ai_spend}
              />
            <% "appearance" -> %>
              <.appearance_pane room={@room} />
            <% slug -> %>
              <.undrawn_pane name={label(slug)} />
          <% end %>
        </main>
      </div>

      <QuorumWeb.Shell.footer />
    </div>
    """
  end

  ## Panes

  attr :room, :map, required: true
  attr :tz_offset, :integer, required: true
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
          value={local_input(@room.auto_close_at, @tz_offset)}
        />
        <p class="q-meta">
          At that time the room closes itself: posting and voting stop, and students keep
          reading what's there. Leave it empty to close it yourself.
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
            aria-label="Let students sign a question"
            class={["q-switch", @room.allow_display_name? && "q-switch--on"]}
            phx-click="toggle"
            phx-value-field="allow_display_name?"
          >
            <span class="q-switch-knob"></span>
          </button>
          <span class="q-label">
            Let students sign a question
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
        A term of questions is the record of what a room heard: which weeks drew nothing, which
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

  attr :up?, :boolean, required: true
  attr :targets, :list, required: true
  attr :providers, :list, required: true
  attr :provider, :string, required: true
  attr :key_status, :any, required: true
  attr :form_seq, :integer, required: true
  attr :spend, :any, required: true

  defp ai_pane(assigns) do
    ~H"""
    <section>
      <h2>API keys</h2>

      <div :if={!@up?} class="q-panel" style="padding:18px;">
        <div class="q-label" style="margin-bottom:6px;">The AI service isn't running</div>
        <p class="q-meta" style="margin:0 0 12px;">
          Start it beside the app and restart Quorum with the token it prints:
        </p>
        <pre class="q-code-line">./sidecar/run.sh</pre>
        <button type="button" class="q-button q-button--secondary" phx-click="ai_reload">
          Check again
        </button>
      </div>

      <div :if={@up?}>
        <div :for={target <- @targets} class="q-ai-key">
          <div class="q-ai-key-id">
            <span class="q-label">{target["provider"]}</span>
            <code>{target["key_hint"]}</code>
          </div>
          <form id={"ai-pin-#{target["name"]}"} phx-change="ai_pin" class="q-ai-key-model">
            <input type="hidden" name="target" value={target["name"]} />
            <label class="q-sr-only" for={"model-#{target["name"]}"}>
              Model for {target["provider"]}
            </label>
            <select id={"model-#{target["name"]}"} name="model" class="q-select">
              <option value="" selected={target["model"] == nil}>
                Automatic: newest that answers
              </option>
              <option
                :for={model <- target["models"] || []}
                value={model}
                selected={target["model"] == model}
              >
                {model}
              </option>
            </select>
          </form>
          <button
            type="button"
            class="q-button q-button--destructive"
            phx-click="ai_remove"
            phx-value-name={target["name"]}
          >
            Remove
          </button>
          <p :if={target["error"]} class="q-meta q-ai-key-error">
            This key stopped working: {target["error"]}
          </p>
        </div>

        <p :if={@targets == []} class="q-meta">
          No keys yet. Add one below and everything switches on.
        </p>

        <h3 style="margin:22px 0 12px;">Add a key</h3>
        <form id={"ai-key-form-#{@form_seq}"} phx-change="ai_form" class="q-ai-add" autocomplete="off">
          <div>
            <label class="q-label" for="ai-provider">Provider</label>
            <select id="ai-provider" name="provider" class="q-select">
              <option value="" selected={@provider == ""}>Pick one</option>
              <option :for={p <- @providers} value={p} selected={@provider == p}>{p}</option>
            </select>
          </div>
          <div style="flex:1;min-width:0;">
            <label class="q-label" for="ai-key">API key</label>
            <input
              id="ai-key"
              name="key"
              type="password"
              class="q-input"
              autocomplete="off"
              spellcheck="false"
              placeholder="Paste the key; it's tested the moment you stop typing"
              phx-debounce="800"
              phx-blur="ai_key_blur"
            />
          </div>
        </form>
        <p class="q-status" role="status">
          <%= case @key_status do %>
            <% :checking -> %>
              Checking the key with the provider&hellip;
            <% {:ok, message} -> %>
              <span class="q-status--saved">&check; {message}</span>
            <% {:error, message} -> %>
              <span style="color:var(--q-destructive);">{message}</span>
            <% _ -> %>
          <% end %>
        </p>

        <hr class="q-divider" style="margin:14px 0;" />

        <h3>What the AI has spent</h3>
        <div :if={@spend} class="q-ai-spend">
          <div class="q-ai-spend-figures">
            <span><strong>{@spend.calls}</strong> {if @spend.calls == 1, do: "call", else: "calls"}</span>
            <span><strong>{@spend.input}</strong> tokens in</span>
            <span><strong>{@spend.output}</strong> tokens out</span>
            <span :if={Decimal.gt?(@spend.cost, 0)}><strong>{dollars(@spend.cost)}</strong> spent</span>
          </div>
          <button type="button" class="q-button q-button--secondary" phx-click="ai_clear_spend">
            Clear the counter
          </button>
        </div>
      </div>
    </section>
    """
  end

  # A fraction of a cent still reads as money, not as zero.
  defp dollars(cost) do
    rounded = Decimal.round(cost, 4)

    if Decimal.eq?(rounded, 0),
      do: "under $0.0001",
      else: "$" <> Decimal.to_string(rounded, :normal)
  end

  attr :field, :string, required: true
  attr :on, :boolean, required: true
  attr :label, :string, required: true
  slot :inner_block, required: false

  defp hold_switch(assigns) do
    ~H"""
    <div class="q-field">
      <div class="q-switch-row">
        <button
          type="button"
          role="switch"
          aria-checked={to_string(@on)}
          aria-label={@label}
          class={["q-switch", @on && "q-switch--on"]}
          phx-click="toggle"
          phx-value-field={@field}
        >
          <span class="q-switch-knob"></span>
        </button>
        <span class="q-label">{@label}</span>
      </div>
      <p :if={@inner_block != []} class="q-meta">{render_slot(@inner_block)}</p>
    </div>
    """
  end

  attr :room, :map, required: true
  attr :held, :integer, required: true
  attr :current_user, :map, default: nil
  attr :error, :string, default: nil
  attr :seq, :integer, default: 0

  defp moderation_pane(assigns) do
    ~H"""
    <section class="q-pane">
      <h2>Moderation</h2>

      <p class="q-meta" style="margin-top:0;">
        Five things can hold a question. Any one of them is enough, and every one holds rather
        than refuses, so the worst a mistake costs an asker is a wait.
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

      <.hold_switch
        field="hold_injection?"
        on={@room.hold_injection?}
        label="Hold anything that reads as aimed at the AI"
      >
        A model reads each question and holds the ones written to instruct an AI system rather
        than ask you something. A clean read releases the question on its own, usually within a
        few seconds. Questions <em>about</em> AI go straight through, and while the AI service
        isn't running this switch holds nothing.
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
        Comma separated, sorted when you click away. A word matches whole, so "class" doesn't trip
        on "ass".
      </p>

      <label class="q-sr-only" for={"held-words-#{@seq}"}>Words that hold a question</label>
      <textarea
        id={"held-words-#{@seq}"}
        name="held_words"
        class="q-textarea q-word-area"
        rows="4"
        autocomplete="off"
        spellcheck="false"
        placeholder="No words held"
        phx-blur="save_words"
      >{Enum.join(@room.held_words, ", ")}</textarea>
      <p class="q-status" style={@error && "color:var(--q-destructive);"}>{@error}</p>

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
      <h2>Readings</h2>

      <div class="q-field">
        <div class="q-switch-row">
          <button
            type="button"
            role="switch"
            aria-checked={to_string(@room.readings_pointer?)}
            aria-label="Show readings"
            class={["q-switch", @room.readings_pointer? && "q-switch--on"]}
            phx-click="toggle"
            phx-value-field="readings_pointer?"
          >
            <span class="q-switch-knob"></span>
          </button>
          <span class="q-label">
            Show readings
          </span>
        </div>
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

      <div :if={@readings != []} class="q-reading-search">
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

  defp projection_pane(assigns) do
    ~H"""
    <section class="q-pane">
      <h2>Projection</h2>
      <p class="q-meta" style="margin-top:0;">
        What the screen at the front of the room puts on the wall. Colours are on the Appearance
        tab.
      </p>

      <form id="projection-scale-form" phx-change="save" class="q-field">
        <label class="q-label" for="projection_question_scale">Question size</label>
        <select id="projection_question_scale" name="projection_question_scale" class="q-input">
          <option
            :for={{value, name} <- scales()}
            value={value}
            selected={@room.projection_question_scale == value}
          >
            {name}
          </option>
        </select>
        <p class="q-meta">
          {scale_note(@room.projection_question_scale)}
        </p>
      </form>

      <hr class="q-divider" style="margin:8px 0;" />

      <h3>Under the question</h3>
      <.hold_switch
        field="projection_show_asker?"
        on={@room.projection_show_asker?}
        label="Show who asked"
      />

      <.hold_switch
        field="projection_show_votes?"
        on={@room.projection_show_votes?}
        label="Show the vote count"
      />

      <hr class="q-divider" style="margin:8px 0;" />

      <h3>Around the question</h3>
      <.hold_switch
        field="projection_show_joining?"
        on={@room.projection_show_joining?}
        label="Show join code"
      />

      <.hold_switch
        field="projection_show_counts?"
        on={@room.projection_show_counts?}
        label="Show attendee count"
      />

      <div style="display:flex;gap:18px;flex-wrap:wrap;margin-top:8px;">
        <.link
          navigate={~p"/host/#{@room.host_token}/project"}
          class="q-button--link"
          target="_blank"
        >
          Open the projection
        </.link>
        <button type="button" class="q-button--link" phx-click="reset_projection">
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
            aria-label="Drift the gradient slowly"
            class={["q-switch", @room.projection_drift? && "q-switch--on"]}
            phx-click="toggle"
            phx-value-field="projection_drift?"
          >
            <span class="q-switch-knob"></span>
          </button>
          <span class="q-label">
            Drift the gradient slowly
          </span>
        </div>
        <p class="q-meta">
          Only on the joining screen, and it holds still for anyone who has asked for reduced motion.
        </p>
      </div>

      <h3>Preview</h3>
      <div class="q-appearance-preview">
        <div style={"background:linear-gradient(#{@room.projection_angle}deg, #{@room.projection_light_from}, #{@room.projection_light_to});color:var(--q-ink);"}>
          <.angle_mark angle={@room.projection_angle} />
          <span>Lit hall</span>
        </div>
        <div style={"background:linear-gradient(#{@room.projection_angle}deg, #{@room.projection_dark_from}, #{@room.projection_dark_to});color:var(--q-on-dark);"}>
          <.angle_mark angle={@room.projection_angle} />
          <span>Dark hall</span>
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

  attr :name, :string, required: true

  # A safety net, not a state anyone should reach: every tab in the rail has a
  # pane. It catches a tab added to @tabs without one, so the mistake reads as
  # a note rather than a crash in front of a room.
  defp undrawn_pane(assigns) do
    ~H"""
    <section class="q-pane">
      <h2>{@name}</h2>
      <p class="q-meta">
        This pane hasn't been drawn yet. Nothing is missing from your room in the meantime.
      </p>
    </section>
    """
  end
end
