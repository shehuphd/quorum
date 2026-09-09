defmodule QuorumWeb.PageController do
  @moduledoc """
  The landing page. It reads the demo room without seeding one, so a visit never
  writes; the demo links seed on click instead. Until a demo room exists the
  hero shows the sample code from the design, which the join screen answers for.
  """
  use QuorumWeb, :controller

  alias Quorum.Sessions
  alias Quorum.Sessions.Demo

  @sample %{code: "K7QM4", posted: 12, answered: 1, connected: 38, live?: false}

  def home(conn, _params) do
    render(conn, :home, demo: demo())
  end

  defp demo do
    case Demo.current() do
      nil ->
        @sample

      room ->
        %{visible: visible, answered: answered} =
          room.id |> Sessions.list_questions() |> Sessions.partition()

        %{
          code: room.join_code,
          posted: length(visible) + length(answered),
          answered: length(answered),
          connected: room.id |> Sessions.topic() |> QuorumWeb.Presence.list() |> map_size(),
          live?: true
        }
    end
  end
end
