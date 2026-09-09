defmodule Quorum.SessionsTest do
  @moduledoc """
  Behavior of the Sessions domain resources, driven through their real actions
  against the database. Failure paths first, then the happy path.
  """
  use Quorum.DataCase, async: false

  require Ash.Query
  alias Quorum.Sessions.{Question, Room, Vote}

  defp open_room(name \\ "Test Room") do
    Room |> Ash.Changeset.for_create(:open, %{name: name}) |> Ash.create!()
  end

  defp ask(room, attrs) do
    base = %{room_id: room.id, submitter_token: "s-#{System.unique_integer([:positive])}"}
    Question |> Ash.Changeset.for_create(:ask, Map.merge(base, attrs)) |> Ash.create!()
  end

  defp cast(question, token) do
    Vote
    |> Ash.Changeset.for_create(:cast, %{question_id: question.id, voter_token: token})
    |> Ash.create!()
  end

  defp vote_count(question) do
    Question |> Ash.get!(question.id, load: [:vote_count]) |> Map.fetch!(:vote_count)
  end

  defp visible_questions(room) do
    Question |> Ash.Query.filter(room_id == ^room.id and status == :visible) |> Ash.read!()
  end

  describe "opening a room" do
    test "rejects a room with no name" do
      assert {:error, _} = Room |> Ash.Changeset.for_create(:open, %{}) |> Ash.create()
    end

    test "generates a join code and a host token and starts open" do
      room = open_room("Intro to OTP")
      assert room.status == :open
      assert is_binary(room.join_code) and byte_size(room.join_code) > 0
      assert is_binary(room.host_token) and byte_size(room.host_token) >= 20
    end

    test "join codes and host tokens are unique across many rooms" do
      rooms = for _ <- 1..25, do: open_room()
      assert length(Enum.uniq(Enum.map(rooms, & &1.join_code))) == 25
      assert length(Enum.uniq(Enum.map(rooms, & &1.host_token))) == 25
    end

    test "closing moves the room to closed" do
      room = open_room() |> Ash.Changeset.for_update(:close) |> Ash.update!()
      assert room.status == :closed
    end
  end

  describe "asking a question" do
    setup do: %{room: open_room()}

    test "rejects an empty body", %{room: room} do
      assert {:error, _} =
               Question
               |> Ash.Changeset.for_create(:ask, %{
                 room_id: room.id,
                 submitter_token: "s",
                 body: ""
               })
               |> Ash.create()
    end

    test "rejects a body past the length limit", %{room: room} do
      too_long = String.duplicate("a", 501)

      assert {:error, _} =
               Question
               |> Ash.Changeset.for_create(:ask, %{
                 room_id: room.id,
                 submitter_token: "s",
                 body: too_long
               })
               |> Ash.create()
    end

    test "requires a room", %{room: _room} do
      assert {:error, _} =
               Question
               |> Ash.Changeset.for_create(:ask, %{submitter_token: "s", body: "orphan"})
               |> Ash.create()
    end

    test "requires a submitter token", %{room: room} do
      assert {:error, _} =
               Question
               |> Ash.Changeset.for_create(:ask, %{room_id: room.id, body: "who am i"})
               |> Ash.create()
    end

    test "is anonymous to peers unless a display name is given", %{room: room} do
      anon = ask(room, %{body: "no name here"})
      named = ask(room, %{body: "with a name", display_name: "Ada"})
      assert is_nil(anon.display_name)
      assert named.display_name == "Ada"
      assert anon.status == :visible
    end
  end

  describe "voting" do
    setup do
      room = open_room()
      %{room: room, question: ask(room, %{body: "count me"})}
    end

    test "each distinct voter adds one vote", %{question: q} do
      cast(q, "v-a")
      cast(q, "v-b")
      assert vote_count(q) == 2
    end

    test "the same voter voting twice is a no-op, not an error and not a second row", %{
      question: q
    } do
      cast(q, "v-a")
      cast(q, "v-a")
      assert vote_count(q) == 1
      assert Vote |> Ash.Query.filter(question_id == ^q.id) |> Ash.read!() |> length() == 1
    end

    test "unvoting removes the vote", %{question: q} do
      cast(q, "v-a")

      vote =
        Vote
        |> Ash.Query.filter(question_id == ^q.id and voter_token == "v-a")
        |> Ash.read_one!()

      Ash.destroy!(vote)
      assert vote_count(q) == 0
    end
  end

  describe "moderating and ranking" do
    setup do: %{room: open_room()}

    test "answer and hide drop a question out of the visible feed, restore returns it", %{
      room: room
    } do
      answered =
        ask(room, %{body: "movable"}) |> Ash.Changeset.for_update(:answer) |> Ash.update!()

      assert answered.status == :answered

      hidden = ask(room, %{body: "hide me"}) |> Ash.Changeset.for_update(:hide) |> Ash.update!()
      assert hidden.status == :hidden

      assert visible_questions(room) == []

      restored = answered |> Ash.Changeset.for_update(:restore) |> Ash.update!()
      assert restored.status == :visible
      assert length(visible_questions(room)) == 1
    end

    test "ranking orders visible questions by vote count, highest first", %{room: room} do
      low = ask(room, %{body: "one vote"})
      high = ask(room, %{body: "three votes"})
      cast(low, "a")
      for t <- ["a", "b", "c"], do: cast(high, t)

      ranked =
        Question
        |> Ash.Query.filter(room_id == ^room.id and status == :visible)
        |> Ash.Query.load(:vote_count)
        |> Ash.read!()
        |> Enum.sort_by(&(-&1.vote_count))

      assert Enum.map(ranked, & &1.body) == ["three votes", "one vote"]
      assert Enum.map(ranked, & &1.vote_count) == [3, 1]
    end
  end

  describe "live updates" do
    test "asking a question broadcasts a room change to subscribers" do
      room = open_room()
      Quorum.Sessions.subscribe(room.id)
      ask(room, %{body: "ping"})
      assert_receive {:room_changed, room_id}
      assert room_id == room.id
    end

    test "voting broadcasts a room change to subscribers" do
      room = open_room()
      question = ask(room, %{body: "vote target"})
      Quorum.Sessions.subscribe(room.id)
      cast(question, "v-a")
      assert_receive {:room_changed, changed_room_id}
      assert changed_room_id == room.id
    end
  end

  describe "spotlight" do
    test "a room spotlights a question and clears it", %{} do
      room = open_room()
      question = ask(room, %{body: "put me on the projector"})

      lit =
        room
        |> Ash.Changeset.for_update(:spotlight, %{spotlight_question_id: question.id})
        |> Ash.update!()

      assert lit.spotlight_question_id == question.id

      cleared = lit |> Ash.Changeset.for_update(:clear_spotlight) |> Ash.update!()
      assert is_nil(cleared.spotlight_question_id)
    end

    test "deleting the spotlighted question clears the projection", %{} do
      room = open_room()
      question = ask(room, %{body: "fleeting"})

      lit =
        room
        |> Ash.Changeset.for_update(:spotlight, %{spotlight_question_id: question.id})
        |> Ash.update!()

      assert lit.spotlight_question_id == question.id

      Ash.destroy!(question)

      reloaded = Ash.get!(Quorum.Sessions.Room, room.id)
      assert is_nil(reloaded.spotlight_question_id)
    end
  end
end
