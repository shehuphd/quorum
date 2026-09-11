defmodule Quorum.HeartbeatTest do
  @moduledoc """
  The database ticker keeps querying on its interval and rides out a failed
  query rather than taking the app down with it.
  """
  use Quorum.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox

  test "it keeps ticking and querying the database" do
    pid = start_supervised!({Quorum.Heartbeat, interval_ms: 30})
    Sandbox.allow(Quorum.Repo, self(), pid)

    # Across several intervals it stays up and the database stays reachable.
    Process.sleep(120)
    assert Process.alive?(pid)
    assert %{rows: [[1]]} = Ecto.Adapters.SQL.query!(Quorum.Repo, "SELECT 1", [])
  end

  test "a failing query doesn't crash it" do
    # No sandbox allowance, so its own query has no connection and raises. The
    # process should log and carry on rather than die.
    pid = start_supervised!({Quorum.Heartbeat, interval_ms: 30})
    Process.sleep(80)
    assert Process.alive?(pid)
  end
end
