defmodule Quorum.Contact.Limit do
  @moduledoc """
  How often the contact form may be used, held on the server.

  The form already asks the browser to wait between messages, but a session
  cookie is the sender's to delete, so the wait it enforces is a courtesy. This
  holds the same rule where the sender can't reach it: one message per address
  per window, and a ceiling on everyone together so a spread of addresses can't
  empty a day's mail allowance in a minute.

  State is in ETS, so it belongs to this instance and goes when it restarts.
  One replica serves Quorum, which makes that the whole picture; a second
  replica would want a shared store instead.
  """
  use GenServer

  @table __MODULE__
  @per_sender_seconds 300
  @window_seconds 3600
  @window_limit 20

  @doc "How many messages everyone together may send in an hour."
  def window_limit, do: @window_limit

  @doc """
  Ask whether this sender may send now.

  `:ok`, `{:wait, seconds}` while their own window is still open, or `:busy`
  when the form as a whole has taken its hour's worth.
  """
  def check(sender, now \\ System.system_time(:second)) do
    cond do
      not started?() -> :ok
      (waiting = wait_for(sender, now)) > 0 -> {:wait, waiting}
      count_since(now - @window_seconds) >= @window_limit -> :busy
      true -> :ok
    end
  end

  @doc "Record a message that was accepted, so the next one waits."
  def record(sender, now \\ System.system_time(:second)) do
    if started?(), do: :ets.insert(@table, {key(sender), now})
    :ok
  end

  @doc "Forget everything. For tests, so one doesn't limit the next."
  def reset do
    if started?(), do: :ets.delete_all_objects(@table)
    :ok
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:bag, :named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  # Every message from this sender still inside their window, so the wait is
  # measured from the most recent one.
  defp wait_for(sender, now) do
    case :ets.lookup(@table, key(sender)) do
      [] ->
        0

      entries ->
        latest = entries |> Enum.map(&elem(&1, 1)) |> Enum.max()
        remaining = @per_sender_seconds - (now - latest)
        max(remaining, 0)
    end
  end

  # Counting walks the table, which stays small: anything past the window is
  # dropped as it's found, so the table holds an hour of messages at most.
  defp count_since(cutoff) do
    @table
    |> :ets.tab2list()
    |> Enum.reduce(0, fn {_sender, at} = entry, count ->
      if at < cutoff do
        :ets.delete_object(@table, entry)
        count
      else
        count + 1
      end
    end)
  end

  defp key(sender), do: to_string(sender)

  defp started?, do: :ets.whereis(@table) != :undefined
end
