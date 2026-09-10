defmodule Quorum.Repo.Migrations.AddObanJobs do
  use Ecto.Migration

  def up, do: Oban.Migration.up(version: 14)

  # Leaves the table behind on the way down for anything still queued, which is
  # what Oban's own guidance asks for.
  def down, do: Oban.Migration.down(version: 1)
end
