defmodule QuorumWeb.Shell do
  @moduledoc """
  The site header and footer that wrap every full page.

  Nav entries appear only when the page behind them exists, so the header never
  offers a link that goes nowhere. Readings and Settings are drawn on the design
  board and go in here when their pages do.
  """
  use QuorumWeb, :html

  alias Quorum.Accounts
  alias QuorumWeb.Brand

  @doc """
  The site header. `variant` is `:app` for a signed-in page, `:guest` for the
  sign-in screens, which offer students a way out instead of nav, and `:student`
  for a room, where the only two places to go are home and another code.
  """
  attr :current_user, :any, default: nil
  attr :variant, :atom, default: :app

  def header(assigns) do
    ~H"""
    <header class="q-shell-header">
      <.link navigate={~p"/"} class="q-shell-brand"><Brand.logo size={23} /></.link>

      <nav :if={@variant == :app} class="q-shell-nav">
        <.link :if={@current_user} navigate={~p"/rooms"}>Rooms</.link>
        <span :if={@current_user} class="q-shell-user">{Accounts.display_name(@current_user)}</span>
        <.link :if={@current_user} href={~p"/sign-out"} method="delete" class="q-shell-signout">
          Sign out
        </.link>
        <.link
          :if={is_nil(@current_user)}
          navigate={~p"/sign-in"}
          class="q-button q-button--secondary"
        >
          Sign in
        </.link>
      </nav>

      <div :if={@variant == :student} class="q-shell-nav">
        <.link navigate={~p"/join"} class="q-button q-button--secondary">Enter a code</.link>
      </div>

      <div :if={@variant == :guest} class="q-shell-nav">
        <span class="q-shell-aside">Joining a session as a student?</span>
        <.link navigate={~p"/join"} class="q-button q-button--secondary">Enter a code</.link>
      </div>
    </header>
    """
  end

  def footer(assigns) do
    ~H"""
    <footer class="q-shell-footer">
      <Brand.logo size={19} />
      <nav class="q-shell-nav" aria-label="Site">
        <.link navigate={~p"/privacy"}>Privacy</.link>
        <.link navigate={~p"/accessibility"}>Accessibility</.link>
        <.link navigate={~p"/contact"}>Contact</.link>
      </nav>
    </footer>
    """
  end
end
