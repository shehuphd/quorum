defmodule QuorumWeb.BrowserToken do
  @moduledoc """
  Ensures every browser session carries an opaque token. Questions and votes use
  it as their `submitter_token` / `voter_token`, so a student can retract their
  own question and vote once, while staying anonymous to peers. The token lives
  in the signed session cookie, never in a rendered page.
  """
  import Plug.Conn

  @session_key "quorum_token"

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, @session_key) do
      nil -> put_session(conn, @session_key, generate())
      _token -> conn
    end
  end

  def session_key, do: @session_key

  defp generate, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
