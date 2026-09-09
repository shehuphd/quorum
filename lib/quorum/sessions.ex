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
  alias Quorum.Sessions.{Question, Room, Vote}

  resources do
    resource(Quorum.Sessions.Room)
    resource(Quorum.Sessions.Question)
    resource(Quorum.Sessions.Vote)
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

  def spotlight(room, question_id),
    do:
      room
      |> Ash.Changeset.for_update(:spotlight, %{spotlight_question_id: question_id})
      |> Ash.update()

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

  def rename_room(room, name),
    do: room |> Ash.Changeset.for_update(:rename, %{name: name}) |> Ash.update()

  def new_join_code(room),
    do: room |> Ash.Changeset.for_update(:new_code) |> Ash.update()

  @doc "Load a room by id with its spotlighted question and that question's vote count."
  def get_room(id), do: Ash.get(Room, id, load: [spotlight_question: [:vote_count]])

  ## Questions

  def ask(room_id, attrs),
    do:
      Question
      |> Ash.Changeset.for_create(:ask, Map.put(attrs, :room_id, room_id))
      |> Ash.create()

  def answer(question), do: question |> Ash.Changeset.for_update(:answer) |> Ash.update()
  def hide(question), do: question |> Ash.Changeset.for_update(:hide) |> Ash.update()
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
  Split a room's questions into the live queue and the answered list, each in the
  order its screen shows: visible ranked by votes then oldest first, answered
  most-recently-answered first. Hidden questions appear in neither.
  """
  def partition(questions) do
    %{
      visible:
        questions
        |> Enum.filter(&(&1.status == :visible))
        |> Enum.sort_by(&{-&1.vote_count, DateTime.to_unix(&1.inserted_at, :microsecond)}),
      answered:
        questions
        |> Enum.filter(&(&1.status == :answered))
        |> Enum.sort_by(&DateTime.to_unix(&1.updated_at, :microsecond), :desc)
    }
  end
end
