defmodule QuorumWeb.RoomHTML do
  @moduledoc "The presenter's list of their own rooms."
  use QuorumWeb, :html

  embed_templates "room_html/*"
end
