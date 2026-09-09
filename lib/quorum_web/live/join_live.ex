defmodule QuorumWeb.JoinLive do
  @moduledoc "Join a session by typing its code."
  use QuorumWeb, :live_view

  alias Quorum.Sessions
  alias QuorumWeb.Brand

  @impl true
  def mount(params, _session, socket) do
    code = params |> Map.get("code", "") |> String.upcase()
    {:ok, assign(socket, code: code, error: nil, page_title: "Join")}
  end

  @impl true
  def handle_event("update", %{"code" => code}, socket) do
    {:noreply, assign(socket, code: String.upcase(code), error: nil)}
  end

  def handle_event("join", %{"code" => code}, socket) do
    code = code |> String.trim() |> String.upcase()

    case Sessions.get_room_by_code(code) do
      {:ok, %{} = _room} -> {:noreply, push_navigate(socket, to: ~p"/r/#{code}")}
      _ -> {:noreply, assign(socket, code: code, error: :not_found)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main style="min-height:100dvh;display:flex;align-items:center;justify-content:center;padding:22px;">
      <div class="q-surface" style="width:100%;max-width:460px;padding:28px;">
        <div style="margin-bottom:22px;"><Brand.logo size={26} /></div>

        <h1 style="font:700 28px/1.15 var(--q-font-sans);margin:0 0 10px;">Join the session</h1>
        <p class="q-meta" style="font-size:15px;line-height:1.45;margin:0 0 22px;">
          Type the five-character code on the screen at the front. No sign-up needed.
        </p>

        <form id="join-form" phx-submit="join" phx-change="update" autocomplete="off">
          <label class="q-label" for="code" style="display:block;margin-bottom:8px;">Session code</label>
          <input
            id="code"
            name="code"
            value={@code}
            maxlength="5"
            autocapitalize="characters"
            autocomplete="off"
            spellcheck="false"
            placeholder="K7QM4"
            class="q-input"
            style="text-align:center;text-transform:uppercase;letter-spacing:0.28em;font-size:28px;font-weight:600;min-height:64px;"
          />
          <button type="submit" class="q-button" style="width:100%;margin-top:14px;">Join session</button>
        </form>

        <p
          :if={@error == :not_found}
          class="q-status"
          style="color:var(--q-destructive);margin-top:12px;"
        >
          No session uses the code {@code}.
        </p>
        <p class="q-meta" style="margin-top:14px;">
          You remain anonymous unless you choose otherwise.
        </p>
      </div>
    </main>
    """
  end
end
