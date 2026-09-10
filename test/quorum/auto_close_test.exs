defmodule Quorum.AutoCloseTest do
  use Quorum.DataCase

  import Quorum.Fixtures

  alias Quorum.Sessions
  alias Quorum.Sessions.AutoClose

  defp closing_at(room, at) do
    {:ok, room} = Sessions.update_settings(room, %{auto_close_at: at})
    room
  end

  defp minutes(n), do: DateTime.add(DateTime.utc_now(), n * 60, :second)

  defp status(room) do
    {:ok, room} = Sessions.get_room(room.id)
    room.status
  end

  test "a room whose own clock has run out is closed" do
    room = room() |> closing_at(minutes(-1))

    AutoClose.close_due()

    assert status(room) == :closed
  end

  test "a room with time left, or no time set, is left alone" do
    later = room() |> closing_at(minutes(30))
    never = room()

    AutoClose.close_due()

    assert status(later) == :open
    assert status(never) == :open
  end

  test "closing this way takes the questions with it, where the room says not to keep them" do
    kept = room() |> closing_at(minutes(-1))
    question(kept, "This one is the term's record.")

    dropped = room()
    {:ok, dropped} = Sessions.update_settings(dropped, %{keep_questions?: false})
    dropped = closing_at(dropped, minutes(-1))
    question(dropped, "This one goes with the session.")

    AutoClose.close_due()

    assert length(Sessions.list_questions(kept.id)) == 1
    assert Sessions.list_questions(dropped.id) == []
  end

  test "a room already closed by hand isn't closed twice" do
    room = room() |> closing_at(minutes(-1))
    {:ok, _} = Sessions.close_room(room)

    # The query only reads open rooms, so this is a no-op rather than an error.
    assert AutoClose.close_due() == :ok
    assert status(room) == :closed
  end

  test "the worker runs the same sweep as the function behind it" do
    room = room() |> closing_at(minutes(-1))

    assert :ok = perform_job(AutoClose, %{})
    assert status(room) == :closed
  end

  defp perform_job(worker, args), do: worker.perform(%Oban.Job{args: args})
end
