defmodule QuorumWeb.Presence do
  @moduledoc """
  Tracks how many people are connected to each room, for the live count on the
  host console and the projection. Keyed by the room's live-feed topic.
  """
  use Phoenix.Presence,
    otp_app: :quorum,
    pubsub_server: Quorum.PubSub
end
