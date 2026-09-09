defmodule QuorumWeb.SessionHTML do
  @moduledoc "The lecturer sign-in screens."
  use QuorumWeb, :html

  embed_templates "session_html/*"

  @doc "Heading for a link that didn't work, naming which way it failed."
  def title(:expired), do: "That link has expired"
  def title(:spent), do: "That link has been used"
  def title(_), do: "That link doesn't work"

  @doc "What happened and what to do next."
  def explain(:expired),
    do: "Sign-in links last #{Quorum.Accounts.link_ttl_minutes()} minutes. Ask for another one."

  def explain(:spent),
    do: "Each link signs you in once, so this one is spent. Ask for another one."

  def explain(_),
    do: "The link may have been copied incompletely. Ask for another one."
end
