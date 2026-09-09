defmodule QuorumWeb.RoomController do
  @moduledoc """
  Opens a room and hands the lecturer their host console. This is the plain entry
  point until the onboarding and settings screens exist; visiting `/start` creates
  a room and redirects to it.
  """
  use QuorumWeb, :controller

  alias Quorum.Sessions

  def create(conn, params) do
    name = params |> Map.get("name", "") |> String.trim()
    name = if name == "", do: "New lecture", else: name

    case Sessions.open_room(name) do
      {:ok, room} ->
        redirect(conn, to: ~p"/host/#{room.host_token}")

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> text("Could not open a room. Please try again.")
    end
  end
end
