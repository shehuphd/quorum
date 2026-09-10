defmodule Quorum.Sessions.AutoClose do
  @moduledoc """
  The minute hand behind **Close automatically at**. A presenter who sets a time
  and then walks out of the hall has the room closed for them, on the same terms
  as pressing Close session: posting and voting stop, students keep reading, and
  a room set not to keep its questions loses them.

  Runs every minute, and reads only open rooms, so a room it closes is not
  picked up again.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Ash.Query

  alias Quorum.Sessions
  alias Quorum.Sessions.Room

  @impl Oban.Worker
  def perform(_job), do: close_due(DateTime.utc_now())

  @doc "Close every open room whose own clock has run out by `now`."
  def close_due(now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)

    Room
    |> Ash.Query.filter(status == :open and not is_nil(auto_close_at) and auto_close_at <= ^now)
    |> Ash.read!()
    |> Enum.each(&Sessions.close_room/1)

    :ok
  end
end
