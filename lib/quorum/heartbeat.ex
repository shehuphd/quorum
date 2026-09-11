defmodule Quorum.Heartbeat do
  @moduledoc """
  A periodic `SELECT 1` that keeps a serverless database awake while the app is
  running.

  Neon's compute suspends after five idle minutes, and the app scales to zero
  outside its warm window, so between the two the stack is meant to sleep. The
  cost of that sleep is a slower first request while Neon resumes. This ticker
  runs only while the container is up, so it never fights the scale-to-zero: it
  keeps the database warm through a warm window and stops with the app at the
  end of it.

  Off by default. `config :quorum, :heartbeat, enabled: true` turns it on, which
  runtime config does in production. The interval stays under Neon's five-minute
  idle timeout, with room to spare.
  """
  use GenServer
  require Logger

  @default_interval :timer.minutes(4)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, @default_interval)
    {:ok, %{interval: interval}, {:continue, :beat}}
  end

  @impl true
  def handle_continue(:beat, state), do: {:noreply, beat(state)}

  @impl true
  def handle_info(:beat, state), do: {:noreply, beat(state)}

  defp beat(state) do
    try do
      Ecto.Adapters.SQL.query!(Quorum.Repo, "SELECT 1", [])
    rescue
      error -> Logger.warning("Heartbeat query failed: #{Exception.message(error)}")
    end

    Process.send_after(self(), :beat, state.interval)
    state
  end
end
