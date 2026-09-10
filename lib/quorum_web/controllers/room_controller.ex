defmodule QuorumWeb.RoomController do
  @moduledoc """
  Opening a room, and the list of a presenter's own.

  A room opened while signed in belongs to that presenter and shows up in their
  list. One opened without an account has no owner and is reached only by the
  host link, which is what `/start` has always done.
  """
  use QuorumWeb, :controller

  alias Quorum.Sessions

  def create(conn, params) do
    name = params |> Map.get("name", "") |> String.trim()
    name = if name == "", do: "New session", else: name
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

  @display_name_key "quorum_display_name"

  @doc "The key the join page's display name is kept under, for the feed to read."
  def display_name_key, do: @display_name_key

  @doc """
  The way in from the join page. It's a plain form post rather than a live
  navigation so a display name can reach the session cookie: the feed reads it
  there and signs the student's questions with it, and the name is never put in
  a URL.
  """
  def join(conn, params) do
    code = params |> Map.get("code", "") |> to_string() |> String.trim() |> String.upcase()
    name = params |> Map.get("name", "") |> to_string() |> String.trim() |> String.slice(0, 60)

    case Sessions.get_room_by_code(code) do
      {:ok, %{} = room} ->
        conn
        |> put_session(@display_name_key, name)
        |> redirect(to: ~p"/r/#{room.join_code}")

      _ ->
        redirect(conn, to: ~p"/join?code=#{code}")
    end
  end

  def index(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        redirect(conn, to: ~p"/sign-in")

      user ->
        rooms = Sessions.list_rooms_with_counts(user.id)
        render(conn, :index, rooms: rooms, current_user: user)
    end
  end
end
