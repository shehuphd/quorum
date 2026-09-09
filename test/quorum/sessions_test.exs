defmodule Quorum.SessionsTest do
  @moduledoc """
  Behavior of the Sessions domain resources, driven through their real actions
  against the database. Failure paths first, then the happy path.
  """
  use Quorum.DataCase, async: false

  require Ash.Query
  alias Quorum.Sessions
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

    test "rejects a body past the resource's ceiling, whatever a room allows", %{room: room} do
      assert {:error, _} =
               Question
               |> Ash.Changeset.for_create(:ask, %{
                 room_id: room.id,
                 submitter_token: "s",
                 body: String.duplicate("a", 1001)
               })
               |> Ash.create()
    end

    test "rejects a body past the room's own limit, and names why", %{room: room} do
      assert {:error, :too_long} =
               Sessions.ask(room.id, %{submitter_token: "s", body: String.duplicate("a", 501)})

      # The same body posts once the room allows it.
      Sessions.update_settings(room, %{question_max_length: 1000})

      assert {:ok, _} =
               Sessions.ask(room.id, %{submitter_token: "s", body: String.duplicate("a", 501)})
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

  describe "how many a student may have waiting" do
    setup do
      room = open_room()
      {:ok, room} = Sessions.update_settings(room, %{questions_per_student: 2})
      %{room: room}
    end

    test "refuses the one past the allowance, and names why", %{room: room} do
      assert {:ok, _} = Sessions.ask(room.id, %{body: "one", submitter_token: "amara"})
      assert {:ok, _} = Sessions.ask(room.id, %{body: "two", submitter_token: "amara"})

      assert {:error, :too_many} =
               Sessions.ask(room.id, %{body: "three", submitter_token: "amara"})
    end

    test "counts each student separately", %{room: room} do
      Sessions.ask(room.id, %{body: "one", submitter_token: "amara"})
      Sessions.ask(room.id, %{body: "two", submitter_token: "amara"})

      assert {:ok, _} = Sessions.ask(room.id, %{body: "mine", submitter_token: "ben"})
    end

    test "an answered question stops counting against its asker", %{room: room} do
      {:ok, first} = Sessions.ask(room.id, %{body: "one", submitter_token: "amara"})
      Sessions.ask(room.id, %{body: "two", submitter_token: "amara"})

      assert {:error, :too_many} =
               Sessions.ask(room.id, %{body: "three", submitter_token: "amara"})

      Sessions.answer(first)
      assert {:ok, _} = Sessions.ask(room.id, %{body: "three", submitter_token: "amara"})
    end

    test "a held question counts, so holding isn't a way around the limit", %{room: room} do
      Sessions.update_settings(room, %{hold_for_review?: true})
      {:ok, room} = Sessions.get_room(room.id)

      assert {:ok, %{status: :pending}} =
               Sessions.ask(room.id, %{body: "one", submitter_token: "amara"})

      assert {:ok, %{status: :pending}} =
               Sessions.ask(room.id, %{body: "two", submitter_token: "amara"})

      assert {:error, :too_many} =
               Sessions.ask(room.id, %{body: "three", submitter_token: "amara"})
    end

    test "no limit is the default, and lets a student keep going" do
      room = open_room("Unlimited")

      for n <- 1..8 do
        assert {:ok, _} = Sessions.ask(room.id, %{body: "q#{n}", submitter_token: "amara"})
      end

      assert Sessions.questions_left(room, "amara") == nil
    end

    test "reports what a student has left", %{room: room} do
      assert Sessions.questions_left(room, "amara") == 2
      Sessions.ask(room.id, %{body: "one", submitter_token: "amara"})
      assert Sessions.questions_left(room, "amara") == 1
    end
  end

  describe "signing a question" do
    test "a name is kept when the room allows it" do
      room = open_room()

      assert {:ok, %{display_name: "Amara"}} =
               Sessions.ask(room.id, %{body: "hi", submitter_token: "a", display_name: "Amara"})
    end

    test "a name is dropped when the room doesn't, however it was sent" do
      room = open_room()
      {:ok, room} = Sessions.update_settings(room, %{allow_display_name?: false})

      assert {:ok, %{display_name: nil}} =
               Sessions.ask(room.id, %{body: "hi", submitter_token: "a", display_name: "Amara"})
    end
  end

  describe "holding questions for review" do
    test "off, a question goes straight to the room" do
      room = open_room()

      assert {:ok, %{status: :visible}} =
               Sessions.ask(room.id, %{body: "hi", submitter_token: "a"})
    end

    test "on, every question is held" do
      room = open_room()
      {:ok, room} = Sessions.update_settings(room, %{hold_for_review?: true})

      assert {:ok, %{status: :pending}} =
               Sessions.ask(room.id, %{body: "hi", submitter_token: "a"})
    end

    test "a held question is in neither the queue nor the answered list" do
      room = open_room()
      Sessions.update_settings(room, %{hold_for_review?: true})
      Sessions.ask(room.id, %{body: "held", submitter_token: "a"})

      %{visible: visible, held: held, answered: answered} =
        room.id |> Sessions.list_questions() |> Sessions.partition()

      assert visible == []
      assert answered == []
      assert [%{body: "held"}] = held
    end

    test "approving puts it in the queue, refusing hides it" do
      room = open_room()
      Sessions.update_settings(room, %{hold_for_review?: true})
      {:ok, yes} = Sessions.ask(room.id, %{body: "yes", submitter_token: "a"})
      {:ok, no} = Sessions.ask(room.id, %{body: "no", submitter_token: "b"})

      Sessions.approve(yes)
      Sessions.reject(no)

      %{visible: visible, held: held} =
        room.id |> Sessions.list_questions() |> Sessions.partition()

      assert [%{body: "yes"}] = visible
      assert held == []
      assert {:ok, %{status: :hidden}} = Sessions.get_question(no.id)
    end

    test "a status can't be posted straight past the queue by a crafted caller" do
      room = open_room()
      Sessions.update_settings(room, %{hold_for_review?: true})

      assert {:ok, %{status: :pending}} =
               Sessions.ask(room.id, %{body: "sneaky", submitter_token: "a", status: :visible})
    end
  end

  describe "holding a student's first question" do
    setup do
      room = open_room()
      {:ok, room} = Sessions.update_settings(room, %{hold_first_question?: true})
      %{room: room}
    end

    test "the first is held and the rest go through once one is approved", %{room: room} do
      assert {:ok, first} = Sessions.ask(room.id, %{body: "my first", submitter_token: "amara"})
      assert first.status == :pending

      # Still held while the first one waits: nothing has been approved yet.
      assert {:ok, %{status: :pending}} =
               Sessions.ask(room.id, %{body: "my second", submitter_token: "amara"})

      Sessions.approve(first)

      assert {:ok, %{status: :visible}} =
               Sessions.ask(room.id, %{body: "my third", submitter_token: "amara"})
    end

    test "a student refused once stays held", %{room: room} do
      {:ok, first} = Sessions.ask(room.id, %{body: "no thanks", submitter_token: "amara"})
      Sessions.reject(first)

      assert {:ok, %{status: :pending}} =
               Sessions.ask(room.id, %{body: "trying again", submitter_token: "amara"})
    end

    test "an answered question also counts as approved", %{room: room} do
      {:ok, first} = Sessions.ask(room.id, %{body: "my first", submitter_token: "amara"})
      Sessions.approve(first)
      Sessions.answer(first)

      assert {:ok, %{status: :visible}} =
               Sessions.ask(room.id, %{body: "my second", submitter_token: "amara"})
    end

    test "one student being trusted doesn't let another through", %{room: room} do
      {:ok, first} = Sessions.ask(room.id, %{body: "mine", submitter_token: "amara"})
      Sessions.approve(first)

      assert {:ok, %{status: :pending}} =
               Sessions.ask(room.id, %{body: "theirs", submitter_token: "ben"})
    end

    test "trust is per room, not across rooms", %{room: room} do
      {:ok, first} = Sessions.ask(room.id, %{body: "mine here", submitter_token: "amara"})
      Sessions.approve(first)

      other = open_room("Another session")
      {:ok, other} = Sessions.update_settings(other, %{hold_first_question?: true})

      assert {:ok, %{status: :pending}} =
               Sessions.ask(other.id, %{body: "mine there", submitter_token: "amara"})
    end
  end

  describe "holding anything with a link" do
    setup do
      room = open_room()
      {:ok, room} = Sessions.update_settings(room, %{hold_links?: true})
      %{room: room}
    end

    test "holds a web address, a bare domain, and a www host", %{room: room} do
      for body <- [
            "See https://spam.example/deal",
            "go to buy-now.example/cheap",
            "www.spam.example has it",
            "Try HTTP://SHOUTY.EXAMPLE"
          ] do
        assert {:ok, %{status: :pending}} =
                 Sessions.ask(room.id, %{body: body, submitter_token: "s-#{body}"})
      end
    end

    test "leaves a file name and ordinary prose alone", %{room: room} do
      for body <- [
            "How does Node.js handle this?",
            "Is it in main.py or app.exs?",
            "So, i.e. the epistemic gap etc.",
            "What is a supervision tree?"
          ] do
        assert {:ok, %{status: :visible}} =
                 Sessions.ask(room.id, %{body: body, submitter_token: "s-#{body}"})
      end
    end

    test "off, a link posts straight to the room" do
      room = open_room()

      assert {:ok, %{status: :visible}} =
               Sessions.ask(room.id, %{body: "https://fine.example", submitter_token: "a"})
    end
  end

  describe "why a question was held" do
    test "names the trigger, in the order a presenter would explain them" do
      room = open_room()

      {:ok, room} =
        Sessions.update_settings(room, %{hold_links?: true, hold_first_question?: true})

      {:ok, room} = Sessions.add_held_word(room, "grade")

      assert Sessions.hold_reason(room, "anything", "newcomer") == :first

      # Once they're trusted, the remaining triggers still apply in turn.
      {:ok, q} = Sessions.ask(room.id, %{body: "first one", submitter_token: "amara"})
      Sessions.approve(q)
      {:ok, room} = Sessions.get_room(room.id)

      assert Sessions.hold_reason(room, "about my grade", "amara") == :word
      assert Sessions.hold_reason(room, "see spam.example/x", "amara") == :link
      assert Sessions.hold_reason(room, "a plain question", "amara") == nil

      {:ok, room} = Sessions.update_settings(room, %{hold_for_review?: true})
      assert Sessions.hold_reason(room, "a plain question", "amara") == :room
    end
  end

  describe "what a new room starts with" do
    test "a room opened by a presenter who moderates starts moderated" do
      {:ok, user, _token} = Quorum.Accounts.request_link("moderates@example.ac.uk")
      Quorum.Accounts.set_moderation_default(user, true)

      {:ok, room} = Sessions.open_room("Held from the start", owner_id: user.id)
      assert room.hold_for_review?
    end

    test "their next room follows the preference as it stands now" do
      {:ok, user, _token} = Quorum.Accounts.request_link("changes-mind@example.ac.uk")
      Quorum.Accounts.set_moderation_default(user, true)
      {:ok, first} = Sessions.open_room("Moderated", owner_id: user.id)

      {:ok, user} = Quorum.Accounts.get_user(user.id)
      Quorum.Accounts.set_moderation_default(user, false)
      {:ok, second} = Sessions.open_room("Not moderated", owner_id: user.id)

      assert first.hold_for_review?
      refute second.hold_for_review?
    end

    test "changing the preference never touches a room already running" do
      {:ok, user, _token} = Quorum.Accounts.request_link("mid-term@example.ac.uk")
      {:ok, room} = Sessions.open_room("Already running", owner_id: user.id)
      refute room.hold_for_review?

      Quorum.Accounts.set_moderation_default(user, true)

      assert {:ok, %{hold_for_review?: false}} = Sessions.get_room(room.id)
    end

    test "a room with no owner has nowhere to have remembered one" do
      {:ok, room} = Sessions.open_room("No account behind it")
      refute room.hold_for_review?
    end
  end

  describe "what happens to questions when the session ends" do
    test "they're kept by default, because they're the record the room is for" do
      room = open_room()
      Sessions.ask(room.id, %{body: "Worth reading back in week 9", submitter_token: "a"})

      {:ok, closed} = Sessions.close_room(room)

      assert closed.keep_questions?
      assert [%{body: "Worth reading back in week 9"}] = Sessions.list_questions(room.id)
    end

    test "a room set to discard them takes them, and their votes, on close" do
      room = open_room()
      {:ok, room} = Sessions.update_settings(room, %{keep_questions?: false})
      {:ok, question} = Sessions.ask(room.id, %{body: "Gone at the bell", submitter_token: "a"})
      Sessions.vote(question.id, "voter-1")

      Sessions.close_room(room)

      assert Sessions.list_questions(room.id) == []
      assert Vote |> Ash.Query.filter(question_id == ^question.id) |> Ash.read!() == []
    end

    test "discarding takes held and answered ones too, not only the live queue" do
      room = open_room()

      {:ok, room} =
        Sessions.update_settings(room, %{keep_questions?: false, hold_for_review?: true})

      {:ok, held} = Sessions.ask(room.id, %{body: "still waiting", submitter_token: "a"})
      Sessions.approve(held)
      Sessions.answer(held)
      Sessions.ask(room.id, %{body: "never approved", submitter_token: "b"})

      Sessions.close_room(room)

      assert Sessions.list_questions(room.id) == []
    end

    test "the room itself survives, so its link still opens" do
      room = open_room()
      {:ok, room} = Sessions.update_settings(room, %{keep_questions?: false})
      Sessions.ask(room.id, %{body: "gone", submitter_token: "a"})

      Sessions.close_room(room)

      assert {:ok, %{status: :closed}} = Sessions.get_room(room.id)
    end
  end

  describe "retracting a question that has votes" do
    test "the votes go with it, rather than the delete failing" do
      room = open_room()

      {:ok, question} =
        Sessions.ask(room.id, %{body: "upvoted, then retracted", submitter_token: "a"})

      Sessions.vote(question.id, "voter-1")
      Sessions.vote(question.id, "voter-2")

      assert :ok = Sessions.retract(question)
      assert Sessions.list_questions(room.id) == []
      assert Vote |> Ash.Query.filter(question_id == ^question.id) |> Ash.read!() == []
    end
  end

  describe "words that hold a question" do
    setup do
      room = open_room()
      {:ok, room} = Sessions.add_held_word(room, "Grade")
      %{room: room}
    end

    test "a new room starts with the default list, so it isn't ungated on day one" do
      room = open_room()
      assert room.held_words == Sessions.default_held_words()
      assert length(room.held_words) == 20
    end

    test "a word is stored lowercase", %{room: room} do
      assert "grade" in room.held_words
      refute "Grade" in room.held_words
    end

    test "the same word twice is one entry", %{room: room} do
      assert {:error, :duplicate} = Sessions.add_held_word(room, "GRADE")
    end

    test "a blank word is refused", %{room: room} do
      assert {:error, :blank} = Sessions.add_held_word(room, "   ")
    end

    test "a question using the word is held, whatever case it's typed in", %{room: room} do
      assert {:ok, %{status: :pending}} =
               Sessions.ask(room.id, %{body: "Will this be on the GRADE?", submitter_token: "a"})
    end

    test "a question that doesn't use it goes straight through", %{room: room} do
      assert {:ok, %{status: :visible}} =
               Sessions.ask(room.id, %{body: "What's the reading?", submitter_token: "a"})
    end

    test "it matches whole words, so an innocent word containing it is left alone", %{room: room} do
      {:ok, room} = Sessions.update_settings(room, %{held_words: []})
      {:ok, room} = Sessions.add_held_word(room, "ass")

      assert {:ok, %{status: :visible}} =
               Sessions.ask(room.id, %{
                 body: "Can you repeat the class outline?",
                 submitter_token: "a"
               })

      assert {:ok, %{status: :pending}} =
               Sessions.ask(room.id, %{body: "Don't be an ass", submitter_token: "b"})
    end

    test "a removed word stops holding", %{room: room} do
      {:ok, room} = Sessions.remove_held_word(room, "grade")
      refute "grade" in room.held_words

      assert {:ok, %{status: :visible}} =
               Sessions.ask(room.id, %{body: "What about my grade?", submitter_token: "a"})
    end

    test "the default list holds what it says it holds", %{room: room} do
      assert {:ok, %{status: :pending}} =
               Sessions.ask(room.id, %{body: "What the fuck was that", submitter_token: "a"})

      assert {:ok, %{status: :pending}} =
               Sessions.ask(room.id, %{body: "This is a STUPID question", submitter_token: "b"})
    end

    test "emptying the list turns the trigger off entirely", %{room: room} do
      {:ok, room} = Sessions.update_settings(room, %{held_words: []})

      assert {:ok, %{status: :visible}} =
               Sessions.ask(room.id, %{body: "What the fuck was that", submitter_token: "a"})
    end
  end
end
