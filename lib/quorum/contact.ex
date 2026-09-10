defmodule Quorum.Contact do
  @moduledoc """
  The contact form's one job: validate a message and mail it on.

  Mail is sent from Quorum's own address with the sender on `reply-to`, rather
  than forged from the sender's address, so it doesn't fail SPF or DKIM at the
  receiving end.
  """
  import Swoosh.Email

  alias Quorum.Mailer

  @max_message 4000
  @max_name 120
  @email ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/

  @doc "Where contact mail goes. Configured, not hardcoded, so it differs per environment."
  def recipient, do: Application.get_env(:quorum, :contact_email, "mo@mohammedshehu.com")

  @doc """
  The address the mail comes from.

  A provider will only send from a domain the account holds, so this follows the
  sending domain rather than being written down once.
  """
  def sender, do: Application.get_env(:quorum, :contact_from, "no-reply@quorum.app")

  @doc """
  Check a submitted message.

  Returns `{:ok, message}` or `{:error, errors}`, a keyword list of field to
  sentence, so the form can put each one beside its own field.
  """
  def validate(params) do
    name = params |> Map.get("name", "") |> String.trim()
    email = params |> Map.get("email", "") |> String.trim()
    body = params |> Map.get("message", "") |> String.trim()

    errors =
      []
      |> check(name == "", :name, "Tell us who you are.")
      |> check(String.length(name) > @max_name, :name, "That name is too long.")
      |> check(email == "", :email, "We need an address to reply to.")
      |> check(
        email != "" and not Regex.match?(@email, email),
        :email,
        "That doesn't look like an email address."
      )
      |> check(body == "", :message, "Write your message first.")
      |> check(
        String.length(body) > @max_message,
        :message,
        "Keep it under #{@max_message} characters."
      )

    case errors do
      [] -> {:ok, %{name: name, email: email, message: body}}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  @doc """
  Send a validated message on to the contact address.

  Returns `{:ok, term}` or `{:error, term}`. A mailer that raises or exits, an
  unreachable provider or an adapter with nothing behind it, comes back as an
  error rather than taking the request down with it, so the form can say the
  message didn't send and keep what was typed.
  """
  def deliver(%{name: name, email: email, message: body}) do
    email =
      new()
      |> to(recipient())
      |> from({"Quorum", sender()})
      |> reply_to({name, email})
      |> subject("Quorum contact from #{name}")
      |> text_body("""
      #{name} <#{email}> wrote through the Quorum contact form:

      #{body}
      """)

    try do
      Mailer.deliver(email)
    catch
      :exit, reason -> {:error, {:exit, reason}}
      kind, reason -> {:error, {kind, reason}}
    end
  end

  defp check(errors, true, field, message), do: [{field, message} | errors]
  defp check(errors, false, _field, _message), do: errors
end
