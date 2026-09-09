defmodule QuorumWeb.DemoController do
  @moduledoc """
  Three doors into the seeded demo lecture, one per role. The landing page links
  here rather than to a room code, so the links keep working when the demo room
  is reseeded.
  """
  use QuorumWeb, :controller

  alias Quorum.Sessions.Demo

  def student(conn, _params), do: enter(conn, &~p"/r/#{&1.join_code}")
  def host(conn, _params), do: enter(conn, &~p"/host/#{&1.host_token}")
  def project(conn, _params), do: enter(conn, &~p"/host/#{&1.host_token}/project")

  defp enter(conn, path) do
    case Demo.ensure_room() do
      {:ok, room} ->
        redirect(conn, to: path.(room))

      _ ->
        conn
        |> put_status(:service_unavailable)
        |> text("The demo lecture isn't available right now. Try again in a moment.")
    end
  end
end
