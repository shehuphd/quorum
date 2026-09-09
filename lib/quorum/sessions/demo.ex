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

  @doc "How many questions a freshly seeded demo room holds."
  def question_count, do: length(@questions) + 1

  @doc """
  The open demo room, seeded on first use. Returns `{:ok, room}`, or an error
  tuple if the room can't be opened, so a caller can render without the demo
  rather than failing the page.
  """
  def ensure_room do
    case current() do
      %Room{} = room -> {:ok, room}
      nil -> seed()
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
    with {:ok, room} <- Sessions.open_room(name, demo?: true) do
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
