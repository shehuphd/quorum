defmodule QuorumWeb.ProjectionLive do
  @moduledoc """
  The screen at the front of the hall. Joining owns the screen while nothing is
  spotlighted and shrinks to a rail once the presenter picks a question. L and D
  each toggle the hall light, Q clears the spotlight.
  """
  use QuorumWeb, :live_view

  import QuorumWeb.Wording

  alias Quorum.Sessions
  alias QuorumWeb.Brand

  @impl true
  def mount(%{"host_token" => token}, _session, socket) do
    case Sessions.get_room_by_host_token(token) do
      {:ok, %{} = room} ->
        if connected?(socket), do: Sessions.subscribe(room.id)
        {:ok, socket |> assign(page_title: "Projection") |> load(room)}

      _ ->
        {:ok, assign(socket, room: nil, dark: true, page_title: "Projection")}
    end
  end

  @impl true
  def handle_info(_message, %{assigns: %{room: nil}} = socket), do: {:noreply, socket}
  def handle_info(_message, socket), do: {:noreply, load(socket, socket.assigns.room)}

  # Either key flips the hall light, so a presenter who reaches for the wrong one
  # still gets the switch rather than nothing. The room holds which hall it is,
  # so a second screen and the students' join pages follow.
  @impl true
  def handle_event("key", %{"key" => key}, socket) when key in ["l", "L", "d", "D"] do
    Sessions.set_hall(socket.assigns.room, !socket.assigns.dark)
    {:noreply, socket}
  end

  def handle_event("key", %{"key" => key}, socket) when key in ["q", "Q"] do
    room = socket.assigns.room
    if room && room.spotlight_question_id, do: Sessions.clear_spotlight(room)
    {:noreply, socket}
  end

  def handle_event("key", _key, socket), do: {:noreply, socket}

  defp load(socket, room) do
    {:ok, room} = Sessions.get_room(room.id)
    connected = room.id |> Sessions.topic() |> QuorumWeb.Presence.list() |> map_size()

    assign(socket,
      room: room,
      dark: room.projection_dark?,
      spotlight: room.spotlight_question,
      connected: connected,
      question_count: Sessions.count_questions(room.id)
    )
  end

  defp muted(true), do: "color:var(--q-on-dark-muted);"
  defp muted(false), do: "color:var(--q-ink-muted);"

  defp faint(true), do: "color:var(--q-on-dark-faint);"
  defp faint(false), do: "color:var(--q-ink-muted);"

  # The rail behind the join code is a flat fill, taking the darker end of
  # whichever gradient the hall is using.
  defp rail_fill(room, true), do: "background:#{room.projection_dark_from};"
  defp rail_fill(room, false), do: "background:#{room.projection_light_from};"

  # A white QR card has no edge of its own against a lit hall, so give it one.
  defp qr_frame(true), do: ""
  defp qr_frame(false), do: "border:1px solid var(--q-ink);"

  # The line under the question. Either half can be turned off, and with both
  # off there's no line at all rather than an empty one.
  defp attribution(room, question) do
    [
      room.projection_show_asker? && asked_by(question, "Asked anonymously"),
      room.projection_show_votes? && "#{question.vote_count} #{votes(question.vote_count)}"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(", ")
    |> case do
      "" -> nil
      line -> line
    end
  end

  # 62px is what the design fixes for a full hall; the room scales from there.
  defp question_size(%{projection_question_scale: 100}), do: ""

  defp question_size(room),
    do: "font-size:#{round(62 * room.projection_question_scale / 100)}px;"

  @impl true
  def render(%{room: nil} = assigns) do
    ~H"""
    <main
      class="q-projection q-projection--dark"
      style="min-height:100dvh;display:flex;align-items:center;justify-content:center;"
    >
      <p style="font:400 20px var(--q-font-sans);color:var(--q-on-dark);">
        That host link doesn't match a room.
      </p>
    </main>
    """
  end

  def render(assigns) do
    ~H"""
    <div
      phx-window-keyup="key"
      class={[
        "q-projection",
        @dark && "q-projection--dark",
        is_nil(@spotlight) && @room.projection_drift? && "q-projection--waiting"
      ]}
      style={"min-height:100dvh;display:flex;flex-direction:column;#{hall(@room, @dark)}"}
    >
      <%= if @spotlight do %>
        <main style="flex:1;display:flex;min-height:0;">
          <aside
            :if={@room.projection_show_joining?}
            style={"width:268px;flex:none;padding:28px 22px;display:flex;flex-direction:column;gap:12px;#{rail_fill(@room, @dark)}"}
          >
            <.link navigate={~p"/"} aria-label="Quorum home">
              <Brand.logo on_dark={@dark} size={22} />
            </.link>
            <p style={"font:400 15px var(--q-font-sans);margin:14px 0 0;#{muted(@dark)}"}>
              Scan to ask a question
            </p>
            <div style={"background:#fff;padding:10px;border-radius:8px;width:fit-content;#{qr_frame(@dark)}"}>
              {raw(qr_svg(@room.join_code, 180))}
            </div>
            <p class="q-code" style="font-size:42px;margin:0;">{@room.join_code}</p>
            <p style={"font:400 13px var(--q-font-sans);margin:0;#{faint(@dark)}"}>
              or go to {QuorumWeb.Shell.join_hint()}
            </p>
          </aside>

          <section style="flex:1;min-width:0;display:flex;flex-direction:column;justify-content:center;padding:48px 5% 48px 48px;">
            <p style="font:600 20px var(--q-font-sans);color:var(--q-accent-on-dark);margin:0 0 18px;">
              Answering now
            </p>
            <p class="q-question--projected" style={"margin:0;#{question_size(@room)}"}>
              {@spotlight.body}
            </p>
            <p
              :if={attribution(@room, @spotlight)}
              style={"font:400 20px var(--q-font-sans);margin:28px 0 0;#{muted(@dark)}"}
            >
              {attribution(@room, @spotlight)}
            </p>
          </section>
        </main>
      <% else %>
        <header style="padding:28px 32px;">
          <.link navigate={~p"/"} aria-label="Quorum home">
            <Brand.logo on_dark={@dark} size={26} />
          </.link>
        </header>

        <main style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;gap:22px;padding:0 32px;">
          <p style={"font:400 30px var(--q-font-sans);margin:0;#{muted(@dark)}"}>
            Scan to ask a question
          </p>
          <div style={"background:#fff;padding:18px;border-radius:12px;line-height:0;#{qr_frame(@dark)}"}>
            {raw(qr_svg(@room.join_code, 300))}
          </div>
          <p class="q-code" style="margin:0;">{@room.join_code}</p>
          <p style={"font:400 15px var(--q-font-sans);margin:0;#{faint(@dark)}"}>
            or go to {QuorumWeb.Shell.join_hint()} to type it in
          </p>
        </main>
      <% end %>

      <footer style="position:relative;display:flex;justify-content:space-between;align-items:flex-end;gap:22px;padding:24px 32px;">
        <div
          :if={@room.projection_show_counts?}
          style={"font:400 18px var(--q-font-sans);line-height:1.5;#{muted(@dark)}"}
        >
          <div>
            <strong>{@connected}</strong> {if @connected == 1, do: "student", else: "students"} connected
          </div>
          <div :if={@question_count > 0}>
            <strong>{@question_count}</strong> {if @question_count == 1,
              do: "question",
              else: "questions"} asked
          </div>
          <div :if={@question_count == 0}>No questions yet</div>
        </div>
        <div style={"font:400 13px var(--q-font-sans);text-align:right;#{faint(@dark)}"}>
          Press <strong>L</strong>
          or <strong>D</strong>{if @dark,
            do: " for a lit hall.",
            else: " for a dark hall."}
          <span :if={@spotlight}>Press <strong>Q</strong> to hide the spotlight.</span>
        </div>
        <span style={"position:absolute;left:50%;bottom:24px;transform:translateX(-50%);white-space:nowrap;font:400 13px var(--q-font-sans);#{faint(@dark)}"}>
          By
          <a
            href="https://mohammedshehu.com"
            target="_blank"
            rel="noopener"
            style="color:inherit;text-decoration:underline;"
          >Mo Shehu</a>
        </span>
      </footer>
    </div>
    """
  end
end
