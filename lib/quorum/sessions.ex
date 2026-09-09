defmodule Quorum.Sessions do
  @moduledoc """
  The live-session domain: rooms students join, the questions they post, and the
  votes that rank them. Audience-neutral by design, so the same resources serve
  lectures now and other live audiences later.

  This module also holds the read and command helpers the LiveViews call, so the
  web layer never builds Ash changesets or queries by hand.
  """
  use Ash.Domain, otp_app: :quorum

  require Ash.Query
  alias Quorum.Sessions.{Question, Reading, Room, Vote}

  resources do
    resource(Quorum.Sessions.Room)
    resource(Quorum.Sessions.Question)
    resource(Quorum.Sessions.Vote)
    resource(Quorum.Sessions.Reading)
  end

  ## Live feed

  @doc "PubSub topic for a room's live feed, keyed by the room's id."
  def topic(room_id), do: "room:" <> room_id

  @doc "Subscribe the calling process to a room's live feed."
  def subscribe(room_id), do: Phoenix.PubSub.subscribe(Quorum.PubSub, topic(room_id))

  ## Rooms

  def open_room(name, opts \\ []) do
    attrs = %{
      name: name,
      demo?: Keyword.get(opts, :demo?, false),
      owner_id: Keyword.get(opts, :owner_id)
    }

    Room |> Ash.Changeset.for_create(:open, attrs) |> Ash.create()
  end

  def close_room(room),
    do: room |> Ash.Changeset.for_update(:close) |> Ash.update()

  @doc """
  Put a question on the projection.

  Only a question the room can already see is eligible. Holding a question back
  means nothing if the same id can be projected to the whole hall, so the
  check is here rather than on the console that happens to offer the control.
  """
  def spotlight(room, question_id) do
    case get_question(question_id) do
      {:ok, %{room_id: id, status: :visible}} when id == room.id ->
        room
        |> Ash.Changeset.for_update(:spotlight, %{spotlight_question_id: question_id})
        |> Ash.update()

      _ ->
        {:error, :not_projectable}
    end
  end

  def clear_spotlight(room),
    do: room |> Ash.Changeset.for_update(:clear_spotlight) |> Ash.update()

  @doc "Find a room by the code a student typed (case-insensitive)."
  def get_room_by_code(code) when is_binary(code),
    do: Room |> Ash.Query.filter(join_code == ^String.upcase(code)) |> Ash.read_one()

  @doc "Find a room by its secret host token."
  def get_room_by_host_token(token) when is_binary(token),
    do: Room |> Ash.Query.filter(host_token == ^token) |> Ash.read_one()

  @doc "Every room a lecturer owns, newest first."
  def list_rooms(owner_id) do
    Room
    |> Ash.Query.filter(owner_id == ^owner_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!()
  end

  @doc """
  Apply one settings change. Hot save means every control calls this on change,
  so it takes whatever subset of settings attributes the control owns.
  """
  def update_settings(room, attrs),
    do: room |> Ash.Changeset.for_update(:settings, attrs) |> Ash.update()

  @doc "Delete a room and everything in it. Only ever called on a closed room."
  def delete_room(room), do: Ash.destroy(room)

  @doc "The appearance values a new room starts with, for Reset this tab."
  def appearance_defaults do
    %{
      projection_light_from: "#E9E9E9",
      projection_light_to: "#FAFAFA",
      projection_dark_from: "#1A1A1A",
      projection_dark_to: "#313131",
      projection_angle: 60,
      projection_drift?: true
    }
  end

  ## Readings

  @doc "A room's approved reading list, oldest first."
  def list_readings(room_id) do
    Reading
    |> Ash.Query.filter(room_id == ^room_id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!()
  end

  def add_reading(room_id, attrs),
    do:
      Reading
      |> Ash.Changeset.for_create(:add, Map.put(attrs, :room_id, room_id))
      |> Ash.create()

  def remove_reading(reading), do: Ash.destroy(reading)
  def get_reading(id), do: Ash.get(Reading, id)

  def rename_room(room, name),
    do: room |> Ash.Changeset.for_update(:rename, %{name: name}) |> Ash.update()

  def new_join_code(room),
    do: room |> Ash.Changeset.for_update(:new_code) |> Ash.update()

  @doc "Load a room by id with its spotlighted question and that question's vote count."
  def get_room(id), do: Ash.get(Room, id, load: [spotlight_question: [:vote_count]])

  ## Questions

  @doc """
  Post a question, with the room's own limits applied.

  The limits are per room, so they can't be resource constraints. They're checked
  here, before the write, and each refusal names itself so the screen can say
  which one stopped it:

    * `{:error, :too_long}` past the room's maximum length
    * `{:error, :too_many}` the student already has their allowance waiting

  A question the room's moderation holds is still written, with status `:pending`,
  so the asker can see it waiting rather than wondering whether it posted.
  """
  def ask(room_id, attrs) do
    {:ok, room} = get_room(room_id)
    body = attrs |> Map.get(:body, "") |> to_string()

    cond do
      String.length(body) > room.question_max_length ->
        {:error, :too_long}

      at_question_limit?(room, Map.get(attrs, :submitter_token)) ->
        {:error, :too_many}

      true ->
        attrs =
          attrs
          |> Map.drop([:status, "status", :held?, "held?"])
          |> Map.put(:room_id, room_id)
          |> Map.put(:held?, held?(room, body))
          |> drop_name_if_anonymous(room)

        Question |> Ash.Changeset.for_create(:ask, attrs) |> Ash.create()
    end
  end

  @doc "How many questions this student still has waiting, or nil when there's no limit."
  def questions_left(room, submitter_token) do
    if room.questions_per_student == 0,
      do: nil,
      else: Kernel.max(room.questions_per_student - waiting_count(room.id, submitter_token), 0)
  end

  defp at_question_limit?(%{questions_per_student: 0}, _token), do: false
  defp at_question_limit?(_room, nil), do: false

  defp at_question_limit?(room, token),
    do: waiting_count(room.id, token) >= room.questions_per_student

  # A student's own questions still in play. Answered and hidden ones don't count
  # against them, so a busy lecture doesn't lock out someone who's been answered.
  defp waiting_count(room_id, token) do
    Question
    |> Ash.Query.filter(
      room_id == ^room_id and submitter_token == ^token and status in [:visible, :pending]
    )
    |> Ash.count!()
  end

  defp drop_name_if_anonymous(attrs, %{allow_display_name?: true}), do: attrs
  defp drop_name_if_anonymous(attrs, _room), do: Map.drop(attrs, [:display_name, "display_name"])

  @doc "Whether this room's moderation settings hold a question with this body."
  def held?(%{hold_for_review?: true}, _body), do: true
  def held?(room, body), do: held_word?(room.held_words, body)

  defp held_word?([], _body), do: false

  defp held_word?(words, body) do
    Enum.any?(words, fn word ->
      Regex.match?(~r/\b#{Regex.escape(word)}\b/iu, body)
    end)
  end

  def answer(question), do: question |> Ash.Changeset.for_update(:answer) |> Ash.update()
  def hide(question), do: question |> Ash.Changeset.for_update(:hide) |> Ash.update()

  @doc "Release a held question into the live queue."
  def approve(question), do: question |> Ash.Changeset.for_update(:approve) |> Ash.update()

  @doc "Refuse a held question. It's hidden rather than deleted, so it can be restored."
  def reject(question), do: hide(question)

  def restore(question), do: question |> Ash.Changeset.for_update(:restore) |> Ash.update()
  def retract(question), do: Ash.destroy(question)
  def get_question(id), do: Ash.get(Question, id)

  @doc "Every question in a room, each with its vote_count loaded."
  def list_questions(room_id) do
    Question
    |> Ash.Query.filter(room_id == ^room_id)
    |> Ash.Query.load(:vote_count)
    |> Ash.read!()
  end

  ## Votes

  def vote(question_id, voter_token),
    do:
      Vote
      |> Ash.Changeset.for_create(:cast, %{question_id: question_id, voter_token: voter_token})
      |> Ash.create()

  def unvote(question_id, voter_token) do
    Vote
    |> Ash.Query.filter(question_id == ^question_id and voter_token == ^voter_token)
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> :ok
      {:ok, vote} -> Ash.destroy(vote)
      other -> other
    end
  end

  @doc "The set of question ids in a room this voter has already upvoted."
  def voted_question_ids(room_id, voter_token) do
    Vote
    |> Ash.Query.filter(voter_token == ^voter_token and question.room_id == ^room_id)
    |> Ash.read!()
    |> MapSet.new(& &1.question_id)
  end

  @doc """
  Split a room's questions into the three lists a screen shows, each in its own
  order: the live queue ranked by votes then oldest first, held questions oldest
  first so the lecturer works through them in the order they arrived, and
  answered most-recently-answered first. Hidden questions appear in none of them.
  """
  def partition(questions) do
    %{
      visible:
        questions
        |> Enum.filter(&(&1.status == :visible))
        |> Enum.sort_by(&{-&1.vote_count, DateTime.to_unix(&1.inserted_at, :microsecond)}),
      held:
        questions
        |> Enum.filter(&(&1.status == :pending))
        |> Enum.sort_by(&DateTime.to_unix(&1.inserted_at, :microsecond)),
      answered:
        questions
        |> Enum.filter(&(&1.status == :answered))
        |> Enum.sort_by(&DateTime.to_unix(&1.updated_at, :microsecond), :desc)
    }
  end

  @doc "What a new room allows students to post, for Reset this tab."
  def question_defaults do
    %{question_max_length: 500, questions_per_student: 0, allow_display_name?: true}
  end

  @doc "What a new room moderates, for Reset this tab. Post-hoc, as the room ships."
  def moderation_defaults do
    %{hold_for_review?: false, held_words: []}
  end

  @doc """
  Add a word to the room's held list. Stored lowercase and deduplicated, so the
  same word typed twice in different cases is one entry.
  """
  def add_held_word(room, word) do
    word = word |> to_string() |> String.trim() |> String.downcase()

    cond do
      word == "" -> {:error, :blank}
      word in room.held_words -> {:error, :duplicate}
      true -> update_settings(room, %{held_words: room.held_words ++ [word]})
    end
  end

  def remove_held_word(room, word),
    do: update_settings(room, %{held_words: List.delete(room.held_words, word)})
end
