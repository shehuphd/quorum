defmodule Mix.Tasks.Quorum.Demo do
  @shortdoc "Opens the demo session and prints its links"

  @moduledoc """
  Opens the seeded demo session the landing page points at, and prints the join
  code plus the student, host, and projection links.

      mix quorum.demo                 # the open demo room, seeded if there isn't one
      mix quorum.demo --fresh         # close the old one and seed a new room
      mix quorum.demo --name "Ethics 201"

  The room is created in whatever database the current `MIX_ENV` points at, so
  run it against the same environment as the server you're looking at.
  """

  use Mix.Task

  alias Quorum.Sessions.Demo

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest} = OptionParser.parse!(args, strict: [name: :string, fresh: :boolean])

    room =
      cond do
        opts[:name] ->
          Demo.clear()
          seed(opts[:name])

        opts[:fresh] ->
          Demo.clear()
          seed(Demo.name())

        true ->
          case Demo.ensure_room() do
            {:ok, room} -> room
            other -> Mix.raise("Could not open the demo room: #{inspect(other)}")
          end
      end

    print(room)
  end

  defp seed(name) do
    case Demo.seed(name) do
      {:ok, room} -> room
      other -> Mix.raise("Could not seed the demo room: #{inspect(other)}")
    end
  end

  defp print(room) do
    base = QuorumWeb.Endpoint.url()

    Mix.shell().info("""

    #{room.name} is open.

      Join code    #{room.join_code}
      Student      #{base}/r/#{room.join_code}
      Host console #{base}/host/#{room.host_token}
      Projection   #{base}/host/#{room.host_token}/project

    The landing page links to the same room at /demo, /demo/host, and
    /demo/project, so those keep working after a reseed.
    """)
  end
end
