defmodule Quorum.Sessions do
  @moduledoc """
  The live-session domain: rooms students join, the questions they post, and the
  votes that rank them. Audience-neutral by design, so the same resources serve
  university teaching now and any other live audience later.

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

  @doc """
  Drop a room's live feed. The join page resolves a room on the fifth character,
  so it can leave one room's feed for another's while the student edits.
  """
  def unsubscribe(room_id), do: Phoenix.PubSub.unsubscribe(Quorum.PubSub, topic(room_id))

  ## Rooms

  def open_room(name, opts \\ []) do
    owner_id = Keyword.get(opts, :owner_id)

    attrs = %{
      name: name,
      demo?: Keyword.get(opts, :demo?, false),
      owner_id: owner_id,
      hold_for_review?: Keyword.get(opts, :hold_for_review?, moderates_by_default?(owner_id))
    }

    Room |> Ash.Changeset.for_create(:open, attrs) |> Ash.create()
  end

  # A presenter who moderates one session usually moderates the next, so a new
  # room starts where their last preference left it. A room with no owner has
  # nowhere to have remembered one.
  defp moderates_by_default?(nil), do: false

  defp moderates_by_default?(owner_id) do
    case Quorum.Accounts.get_user(owner_id) do
      {:ok, %{hold_for_review_default?: hold?}} -> hold?
      _ -> false
    end
  end

  @doc """
  Close a room to new questions and votes.

  The questions stay unless the room says otherwise. A term of them is what
  tells a presenter which material didn't land, so keeping them is the point of
  the room rather than a default nobody chose. A room with `keep_questions?`
  off has them deleted here, with their votes, and there's no undo.
  """
  def close_room(room) do
    with {:ok, closed} <- room |> Ash.Changeset.for_update(:close) |> Ash.update() do
      unless closed.keep_questions?, do: delete_questions(closed.id)
      {:ok, closed}
    end
  end

  defp delete_questions(room_id) do
    Question
    |> Ash.Query.filter(room_id == ^room_id)
    |> Ash.read!()
    |> Enum.each(&Ash.destroy!/1)
  end

  @doc """
  Put a question on the projection.

  Only a question the room can already see is eligible. Holding a question back
  means nothing if the same id can be projected to the whole hall, so the
  check is here rather than on the console that happens to offer the control.
  """
  def spotlight(room, question_id) do
    case get_question(question_id) do
      {:ok, %{room_id: id, status: :visible} = question} when id == room.id ->
        with {:ok, updated} <-
               room
               |> Ash.Changeset.for_update(:spotlight, %{spotlight_question_id: question_id})
               |> Ash.update() do
          draft_answer(room, question)
          {:ok, updated}
        end

      _ ->
        {:error, :not_projectable}
    end
  end

  # A suggested answer starts drafting the moment the presenter picks the
  # question, so it's usually there by the time they've read it aloud. Once
  # drafted it stays; a re-spotlight doesn't bill a second call.
  defp draft_answer(room, question) do
    if Quorum.AI.enabled?() and is_nil(question.answer_draft) do
      Oban.insert(Quorum.AI.DraftJob.new(%{question_id: question.id, room_id: room.id}))
    end

    :ok
  end

  def clear_spotlight(room),
    do: room |> Ash.Changeset.for_update(:clear_spotlight) |> Ash.update()

  @doc "Find a room by the code a student typed (case-insensitive)."
  def get_room_by_code(code) when is_binary(code),
    do: Room |> Ash.Query.filter(join_code == ^String.upcase(code)) |> Ash.read_one()

  @doc "Find a room by its secret host token."
  def get_room_by_host_token(token) when is_binary(token),
    do: Room |> Ash.Query.filter(host_token == ^token) |> Ash.read_one()

  @doc "Every room a presenter owns, newest first."
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

  @doc """
  Switch the hall between lit and dark. The projection's L and D keys go through
  here rather than holding the state in their own process, so a second screen
  and every join page in the room follow the switch.
  """
  def set_hall(room, dark?) when is_boolean(dark?),
    do: update_settings(room, %{projection_dark?: dark?})

  @doc "Delete a room and everything in it. Only ever called on a closed room."
  def delete_room(room), do: Ash.destroy(room)

  @doc "What a new room's projection shows, for Reset this tab."
  def projection_defaults do
    %{
      projection_question_scale: 100,
      projection_show_asker?: true,
      projection_show_votes?: true,
      projection_show_joining?: true,
      projection_show_counts?: true
    }
  end

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

    * `{:error, :closed}` the session ended before this arrived
    * `{:error, :too_long}` past the room's maximum length
    * `{:error, :too_many}` the student already has their allowance waiting

  A question the room's moderation holds is still written, with status `:pending`,
  so the asker can see it waiting rather than wondering whether it posted.
  """
  def ask(room_id, attrs) do
    {:ok, room} = get_room(room_id)
    body = attrs |> Map.get(:body, "") |> to_string()

    cond do
      room.status == :closed ->
        {:error, :closed}

      String.length(body) > room.question_max_length ->
        {:error, :too_long}

      at_question_limit?(room, Map.get(attrs, :submitter_token)) ->
        {:error, :too_many}

      true ->
        attrs =
          attrs
          |> Map.drop([:status, "status", :held_reason, "held_reason"])
          |> Map.put(:room_id, room_id)
          |> Map.put(:held_reason, hold_reason(room, body, Map.get(attrs, :submitter_token)))
          |> drop_name_if_anonymous(room)

        with {:ok, question} <- Question |> Ash.Changeset.for_create(:ask, attrs) |> Ash.create() do
          follow_up(room, question)
          {:ok, question}
        end
    end
  end

  # What a freshly posted question sets in motion: the injection screen where
  # that's what held it, and the reading pointer once the room can see it.
  defp follow_up(room, %{held_reason: :screening} = question),
    do: Oban.insert(Quorum.AI.ScreenJob.new(%{question_id: question.id, room_id: room.id}))

  defp follow_up(room, %{status: :visible} = question), do: point_at_readings(room, question)
  defp follow_up(_room, _question), do: :ok

  @doc false
  def point_at_readings(room, question) do
    if room.readings_pointer? and Quorum.AI.enabled?() do
      Oban.insert(Quorum.AI.PointerJob.new(%{question_id: question.id, room_id: room.id}))
    end

    :ok
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
  # against them, so a busy session doesn't lock out someone who's been answered.
  defp waiting_count(room_id, token) do
    Question
    |> Ash.Query.filter(
      room_id == ^room_id and submitter_token == ^token and status in [:visible, :pending]
    )
    |> Ash.count!()
  end

  defp drop_name_if_anonymous(attrs, %{allow_display_name?: true}), do: attrs
  defp drop_name_if_anonymous(attrs, _room), do: Map.drop(attrs, [:display_name, "display_name"])

  @doc """
  Why this room's moderation would hold this question, or `nil` to let it pass.

  Four triggers, checked in the order a presenter would explain them. Each one
  holds; none refuses, so the cost of a false positive is a wait.

    * `:room` the room holds everything
    * `:first` the asker has had nothing approved here yet
    * `:word` the body uses a word on the room's held list
    * `:link` the body carries a link
  """
  def hold_reason(room, body, submitter_token) do
    cond do
      room.hold_for_review? -> :room
      room.hold_first_question? and newcomer?(room.id, submitter_token) -> :first
      held_word?(room.held_words, body) -> :word
      room.hold_links? and link?(body) -> :link
      room.hold_injection? and Quorum.AI.enabled?() -> :screening
      true -> nil
    end
  end

  @doc "Whether this room's moderation settings hold a question."
  def held?(room, body, submitter_token),
    do: hold_reason(room, body, submitter_token) != nil

  # Students have no accounts, so the only trust a room can read is what this
  # browser has had approved here. A question still waiting doesn't count, or
  # the first one would let the second through while it was still unread.
  defp newcomer?(_room_id, nil), do: true

  defp newcomer?(room_id, token) do
    count =
      Question
      |> Ash.Query.filter(
        room_id == ^room_id and submitter_token == ^token and status in [:visible, :answered]
      )
      |> Ash.count!()

    count == 0
  end

  defp held_word?([], _body), do: false

  defp held_word?(words, body) do
    Enum.any?(words, fn word ->
      Regex.match?(~r/\b#{Regex.escape(word)}\b/iu, body)
    end)
  end

  # Extensions that read as a domain but aren't one. A session on Node.js
  # shouldn't hold every question that names it.
  @not_a_domain ~w(js ts py rb ex exs go rs md json html css sh yml yaml txt csv pdf png jpg)

  @doc "Whether a body carries something a student could follow out of the room."
  def link?(body) do
    cond do
      Regex.match?(~r{\w+://}u, body) -> true
      Regex.match?(~r{\bwww\.\S}iu, body) -> true
      true -> bare_domain?(body)
    end
  end

  defp bare_domain?(body) do
    ~r/\b[\w-]+\.([a-z]{2,24})\b/iu
    |> Regex.scan(body)
    |> Enum.any?(fn [_match, tld] -> String.downcase(tld) not in @not_a_domain end)
  end

  def answer(question), do: question |> Ash.Changeset.for_update(:answer) |> Ash.update()
  def hide(question), do: question |> Ash.Changeset.for_update(:hide) |> Ash.update()

  @doc "Release a held question into the live queue."
  def approve(question) do
    with {:ok, approved} <- question |> Ash.Changeset.for_update(:approve) |> Ash.update(),
         {:ok, room} <- get_room(approved.room_id) do
      point_at_readings(room, approved)
      {:ok, approved}
    end
  end

  @doc "Store what the pointer matched on a question."
  def point(question, reading_ids),
    do:
      question
      |> Ash.Changeset.for_update(:point, %{pointer_reading_ids: reading_ids})
      |> Ash.update()

  @doc "Store the suggested answer only the presenter sees."
  def store_draft(question, draft),
    do: question |> Ash.Changeset.for_update(:draft, %{answer_draft: draft}) |> Ash.update()

  @doc "The screen read a held question as an instruction to the AI. Mark it so."
  def confirm_injection(question),
    do: question |> Ash.Changeset.for_update(:confirm_injection) |> Ash.update()

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

  @doc """
  Every session a presenter has run, newest first, each carrying the questions
  it drew. This is the term's record: what the room asked, week by week, which
  is what the next term's plan is built from.

  Held and hidden questions are left out. A question that never reached the room
  isn't part of what the room asked.
  """
  def archive(owner_id) do
    rooms = list_rooms(owner_id)
    by_room = questions_by_room(Enum.map(rooms, & &1.id))

    Enum.map(rooms, fn room ->
      %{visible: visible, answered: answered} =
        by_room |> Map.get(room.id, []) |> partition()

      Map.merge(room, %{questions: visible ++ answered, answered_count: length(answered)})
    end)
  end

  defp questions_by_room([]), do: %{}

  defp questions_by_room(room_ids) do
    Question
    |> Ash.Query.filter(room_id in ^room_ids)
    |> Ash.Query.load(:vote_count)
    |> Ash.read!()
    |> Enum.group_by(& &1.room_id)
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
  first so the presenter works through them in the order they arrived, and
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
    %{
      question_max_length: 500,
      questions_per_student: 0,
      allow_display_name?: true,
      keep_questions?: true
    }
  end

  # A starting list, not a policy. Twenty words a room would rather see before
  # the hall does, so a new room has a gate on day one instead of an empty box
  # nobody thinks to fill. Every one of them is removable, and a presenter who
  # wants none of it empties the list.
  #
  # Deliberately profanity and insults rather than slurs: a hardcoded slur list
  # in a repo ages badly and belongs in the institutional registry on the
  # roadmap, maintained by people whose job that is.
  @default_held_words ~w(
    fuck fucking fucker shit bullshit bitch bastard cunt dick prick
    asshole arsehole wanker twat slut whore idiot moron retard stupid
  )

  @doc "The held words a new room starts with. Removable, one at a time or all at once."
  def default_held_words, do: @default_held_words

  @doc "What a new room moderates, for Reset this tab. Post-hoc, as the room ships."
  def moderation_defaults do
    %{
      hold_for_review?: false,
      hold_links?: false,
      hold_first_question?: false,
      hold_injection?: false,
      held_words: @default_held_words
    }
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

  @doc """
  Read a comma-separated list of held words, applying the same rules one word
  gets: trimmed, lowercased, no blanks, no repeats. Sorted, so the settings
  field reads back tidy however it was typed.
  """
  def parse_held_words(text) do
    text
    |> to_string()
    |> String.split(",")
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end
end
