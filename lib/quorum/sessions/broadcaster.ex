defmodule Quorum.Sessions.Broadcaster do
  @moduledoc """
  On every room, question, or vote change, broadcasts a "this room changed"
  signal so each LiveView watching the room reloads its ranked feed. Subscribers
  listen on `Quorum.Sessions.topic/1`.

  The signal names the room, not the delta: a viewer re-reads the room's
  questions on receipt. That keeps every viewer consistent without the notifier
  having to describe what changed, and it collapses a burst of votes into cheap,
  idempotent reloads.
  """
  use Ash.Notifier

  alias Quorum.Sessions
  alias Quorum.Sessions.{Question, Room, Vote}

  @impl Ash.Notifier
  def notify(%Ash.Notifier.Notification{resource: resource, data: data}) do
    case room_id(resource, data) do
      nil ->
        :ok

      room_id ->
        Phoenix.PubSub.broadcast(
          Quorum.PubSub,
          Sessions.topic(room_id),
          {:room_changed, room_id}
        )
    end
  end

  # A vote carries only its question; look up the room the question belongs to.
  defp room_id(Room, %{id: id}), do: id
  defp room_id(Question, %{room_id: room_id}), do: room_id

  defp room_id(Vote, %{question_id: question_id}) do
    case Ash.get(Question, question_id) do
      {:ok, question} -> question.room_id
      _ -> nil
    end
  end

  defp room_id(_resource, _data), do: nil
end
