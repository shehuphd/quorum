defmodule Quorum.Sessions.Demo do
  @moduledoc """
  The seeded session the landing page points at, so anyone can look at all three
  views without opening a room of their own. One demo room is kept open at a
  time; `ensure_room/0` returns it and seeds a new one only when none exists.
  """

  require Ash.Query

  alias Quorum.Sessions
  alias Quorum.Sessions.Room

  @name "Distributed Systems 301"

  # A fixed, memorable code for the demo room, printed on the landing page so
  # anyone can type it and land in the demo. The room-code generator drops the
  # ambiguous glyphs I, O, 0, 1, so a code carrying an O can never be handed to
  # a presenter's own room, and this one won't collide.
  @code "DEMO7"

  # body, display name (nil is anonymous), votes
  @questions [
    {"If a supervisor restarts a crashed child, what happens to the messages that were already in its mailbox?",
     nil, 31},
    {"How do you decide between one_for_one and rest_for_one in practice?", "Amara", 24},
    {"Why is the mailbox unbounded by default? Doesn't that just move the failure somewhere worse?",
     nil, 18},
    {"What's the difference between a link and a monitor, and when would you want both?", nil,
     12},
    {"Does the scheduler preempt a process in the middle of a long list comprehension?", "Tobias",
     9},
    {"Is it ever correct to catch an exit rather than let the process die?", nil, 5},
    {"Could you go over the reduction count example from last week again?", nil, 2},
    {"Will the distributed section be on the exam?", nil, 1}
  ]

  @answered {"What does it mean for the BEAM to be soft real-time?", nil, 14}

  @doc "The room's default name, for anything that needs to name it before it exists."
  def name, do: @name

  @doc "The fixed join code the demo room always carries, for the landing page to print."
  def code, do: @code

  @doc "How many questions a freshly seeded demo room holds."
  def question_count, do: length(@questions) + 1

  @doc """
  The open demo room, seeded on first use. Returns `{:ok, room}`, or an error
  tuple if the room can't be opened, so a caller can render without the demo
  rather than failing the page.
  """
  def ensure_room do
    case current() do
      %Room{join_code: @code} = room ->
        {:ok, room}

      # A demo room left over from before the code was fixed: close it so the
      # next one carries the code the landing page prints.
      %Room{} = stale ->
        Sessions.close_room(stale)
        seed()

      nil ->
        seed()
    end
  end

  @doc """
  The room a join code opens, seeding the demo room when the code is the demo's
  own and no room answers to it yet. Every other code is a plain lookup, so this
  can stand in for `Sessions.get_room_by_code/1` wherever a visitor might be
  arriving with the printed demo code.
  """
  def room_for_code(code) do
    upcased = code |> to_string() |> String.upcase()

    # The demo code always opens a live demo room, seeding or reseeding one when
    # the last was closed, so the printed code never opens onto a shut session.
    # Every other code is the plain lookup, which resolves open and closed rooms
    # alike so the join flow can show a closed room's archive.
    if upcased == @code do
      ensure_room()
    else
      case Sessions.get_room_by_code(upcased) do
        {:ok, %Room{} = room} -> {:ok, room}
        _ -> {:error, :not_found}
      end
    end
  end

  @doc """
  The open demo room, or nil. Reads without seeding, so a page can render the
  demo band without a GET writing to the database.
  """
  def current do
    case current_room() do
      {:ok, %Room{} = room} -> room
      _ -> nil
    end
  end

  @doc "Open a new demo room, whether or not one is already open."
  def seed(name \\ @name) do
    # A join code is unique whether its room is open or closed, and the demo's is
    # fixed, so a closed demo room still holds the code. Free it before taking it
    # again. The delete cascades to the room's questions and their votes.
    Room
    |> Ash.Query.filter(join_code == ^@code)
    |> Ash.read!()
    |> Enum.each(&Sessions.delete_room/1)

    with {:ok, room} <- Sessions.open_room(name, demo?: true, code: @code) do
      Enum.each(@questions, &add(room, &1))

      case add(room, @answered) do
        {:ok, question} -> Sessions.answer(question)
        _ -> :ok
      end

      {:ok, room}
    end
  end

  @doc "Close every open demo room, so the next visit seeds a fresh one."
  def clear do
    Room
    |> Ash.Query.filter(demo? == true and status == :open)
    |> Ash.read!()
    |> Enum.each(&Sessions.close_room/1)
  end

  defp current_room do
    Room
    |> Ash.Query.filter(demo? == true and status == :open)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one()
  end

  defp add(room, {body, display_name, votes}) do
    attrs = %{body: body, submitter_token: token()}
    attrs = if display_name, do: Map.put(attrs, :display_name, display_name), else: attrs

    with {:ok, question} <- Sessions.ask(room.id, attrs) do
      for _ <- 1..votes, do: Sessions.vote(question.id, token())
      {:ok, question}
    end
  end

  defp token, do: 12 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
