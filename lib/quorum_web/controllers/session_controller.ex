defmodule QuorumWeb.SessionController do
  @moduledoc """
  Demo sign-in for presenters. Students never come through here.

  Sign-in is a stub for the demo build: one access code, shown as the field's own
  placeholder, opens the shared demo presenter. No email is sent. The magic-link
  actions below stay for a later build that authenticates presenters.
  """
  use QuorumWeb, :controller

  alias Quorum.Accounts
  alias QuorumWeb.CurrentUser

  def new(conn, _params), do: render(conn, :new, code: "", error: nil)

  def create(conn, params) do
    code = Map.get(params, "code", "")

    if Accounts.demo_code?(code) do
      {:ok, user} = Accounts.demo_presenter()

      conn
      |> CurrentUser.sign_in(user)
      |> redirect(to: ~p"/rooms")
    else
      conn
      |> put_status(:unprocessable_entity)
      |> render(:new,
        code: String.trim(code),
        error: "That code doesn't open the demo. It's the one shown in the box."
      )
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
