defmodule Quorum.Accounts.Notifier do
  @moduledoc """
  The one email Quorum sends: a presenter's sign-in link.

  In development it goes to the local mailbox at `/dev/mailbox` rather than out
  to the internet, so the whole loop is testable without a mail provider.
  """
  import Swoosh.Email

  alias Quorum.Accounts
  alias Quorum.Mailer

  def deliver_sign_in_link(user, url) do
    minutes = Accounts.link_ttl_minutes()

    new()
    |> to({Accounts.display_name(user), user.email})
    |> from({"Quorum", "no-reply@quorum.app"})
    |> subject("Your Quorum sign-in link")
    |> text_body("""
    Sign in to Quorum:

    #{url}

    The link works once and expires in #{minutes} minutes.

    If you didn't ask for it, you can ignore this email.
    """)
    |> Mailer.deliver()
  end
end
