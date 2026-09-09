defmodule QuorumWeb.CurrentUser do
  @moduledoc """
  Puts the signed-in lecturer on the connection as `:current_user`, or nil.

  Signing in stores only the user's id, so a stale cookie for a deleted account
  resolves to nil rather than to a stranger's session.
  """
  @behaviour Plug

  import Plug.Conn

  alias Quorum.Accounts

  @session_key "quorum_user_id"

  def session_key, do: @session_key

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts), do: assign(conn, :current_user, fetch(conn))

  @doc "Start a signed-in session. The session id is renewed, so a fixed cookie can't be reused."
  def sign_in(conn, user) do
    conn
    |> configure_session(renew: true)
    |> put_session(@session_key, user.id)
  end

  @doc "End the session and drop everything in it."
  def sign_out(conn), do: configure_session(conn, drop: true)

  @doc "The lecturer for a LiveView session map, or nil."
  def from_session(%{@session_key => id}) when is_binary(id) do
    case Accounts.get_user(id) do
      {:ok, user} -> user
      _ -> nil
    end
  end

  def from_session(_session), do: nil

  defp fetch(conn) do
    case get_session(conn, @session_key) do
      nil -> nil
      id -> from_session(%{@session_key => id})
    end
  end
end
