defmodule QuorumWeb.RoomController do
  @moduledoc """
  Opening a room, and the list of a lecturer's own.

  A room opened while signed in belongs to that lecturer and shows up in their
  list. One opened without an account has no owner and is reached only by the
  host link, which is what `/start` has always done.
  """
  use QuorumWeb, :controller

  alias Quorum.Sessions

  def create(conn, params) do
    name = params |> Map.get("name", "") |> String.trim()
    name = if name == "", do: "New lecture", else: name
    owner = conn.assigns[:current_user]

    case Sessions.open_room(name, owner_id: owner && owner.id) do
      {:ok, room} ->
        redirect(conn, to: ~p"/host/#{room.host_token}")

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> text("Could not open a room. Please try again.")
    end
  end

  def index(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        redirect(conn, to: ~p"/sign-in")

      user ->
        rooms =
          user.id
          |> Sessions.list_rooms()
          |> Enum.map(fn room ->
            %{visible: visible, answered: answered} =
              room.id |> Sessions.list_questions() |> Sessions.partition()

            Map.put(room, :question_count, length(visible) + length(answered))
          end)

        render(conn, :index, rooms: rooms, current_user: user)
    end
  end
end
