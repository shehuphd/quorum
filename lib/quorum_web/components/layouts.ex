defmodule QuorumWeb.Layouts do
  @moduledoc """
  Holds the application's layouts. Only the root layout is used: it carries the
  HTML skeleton, loads the stylesheet and socket, and sets the theme before
  paint. The screens render their own chrome through `QuorumWeb.Shell` rather
  than an app layout.
  """
  use QuorumWeb, :html

  # Embed all files in layouts/* within this module.
  embed_templates "layouts/*"
end
