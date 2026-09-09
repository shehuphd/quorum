defmodule QuorumWeb.SessionController do
  @moduledoc """
  Magic-link sign-in for presenters. Students never come through here.

  The "check your email" screen says the same thing whether or not the address
  was already known, so the page can't be used to find out who has an account.
  """
  use QuorumWeb, :controller

  alias Quorum.Accounts
  alias Quorum.Accounts.Notifier
  alias QuorumWeb.CurrentUser

  def new(conn, _params), do: render(conn, :new, email: "", error: nil)

  def create(conn, params) do
    email = params |> Map.get("email", "") |> String.trim()

    case Accounts.request_link(email) do
      {:ok, user, token} ->
        Notifier.deliver_sign_in_link(user, url(~p"/sign-in/#{token.token}"))
        redirect(conn, to: ~p"/sign-in/sent?#{[email: user.email]}")

      {:wait, _seconds} ->
        # Already sent one moments ago. Show the same screen rather than saying so.
        redirect(conn, to: ~p"/sign-in/sent?#{[email: String.downcase(email)]}")

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:new, email: email, error: "That doesn't look like an email address.")
    end
  end

  def sent(conn, params) do
    email = params |> Map.get("email", "") |> String.trim()

    cooldown =
      case Accounts.get_user_by_email(email) do
        {:ok, %{} = user} -> Accounts.seconds_remaining(user)
        _ -> Accounts.cooldown_seconds()
      end

    render(conn, :sent, email: email, cooldown: cooldown)
  end

  def claim(conn, %{"token" => token}) do
    case Accounts.claim_link(token) do
      {:ok, user} ->
        conn
        |> CurrentUser.sign_in(user)
        |> redirect(to: ~p"/rooms")

      reason ->
        render(conn, :invalid, reason: reason)
    end
  end

  def delete(conn, _params) do
    conn
    |> CurrentUser.sign_out()
    |> redirect(to: ~p"/")
  end
end
