defmodule QuorumWeb.SessionControllerTest do
  use QuorumWeb.ConnCase

  alias Quorum.Accounts
  alias QuorumWeb.CurrentUser

  test "the sign-in page shows the access code as its own field placeholder", %{conn: conn} do
    html = conn |> get(~p"/sign-in") |> html_response(200)

    assert html =~ "Sign in"
    assert html =~ ~s(for="code")
    # The placeholder is the code, so the hint and the key are one value.
    assert html =~ ~s(placeholder="#{Accounts.demo_code()}")
    # The SSO control is disabled rather than inert-looking.
    assert html =~ ~s(disabled="disabled")
    assert html =~ "Join a session with a code"
  end

  test "the code opens the demo presenter and their rooms", %{conn: conn} do
    conn = post(conn, ~p"/sign-in", %{"code" => Accounts.demo_code()})

    assert redirected_to(conn) == ~p"/rooms"
    assert get_session(conn, CurrentUser.session_key())
  end

  test "the code is forgiven its case and surrounding space", %{conn: conn} do
    padded = "  " <> String.upcase(Accounts.demo_code()) <> "  "
    conn = post(conn, ~p"/sign-in", %{"code" => padded})

    assert redirected_to(conn) == ~p"/rooms"
  end

  test "a wrong code is refused on the page, with no session started", %{conn: conn} do
    conn = post(conn, ~p"/sign-in", %{"code" => "nope"})
    html = html_response(conn, 422)

    assert html =~ "That code doesn&#39;t open the demo."
    refute get_session(conn, CurrentUser.session_key())
  end

  test "signing out drops the session", %{conn: conn} do
    conn = post(conn, ~p"/sign-in", %{"code" => Accounts.demo_code()})
    assert get_session(conn, CurrentUser.session_key())

    conn = delete(conn, ~p"/sign-out")
    assert redirected_to(conn) == ~p"/"

    # The next request carries no session, so /rooms sends them back to sign in.
    assert conn |> recycle() |> get(~p"/rooms") |> redirected_to() == ~p"/sign-in"
  end

  test "rooms is for signed-in presenters, and sends anyone else to sign in", %{conn: conn} do
    assert conn |> get(~p"/rooms") |> redirected_to() == ~p"/sign-in"
  end

  test "a signed-in presenter sees the rooms they opened, and not other people's", %{conn: conn} do
    conn = post(conn, ~p"/sign-in", %{"code" => Accounts.demo_code()})

    conn = get(conn, ~p"/start")
    {:ok, _other} = Quorum.Sessions.open_room("Someone else's session")

    html = conn |> recycle() |> get(~p"/rooms") |> html_response(200)

    assert html =~ "New session"
    refute html =~ "Someone else&#39;s session"
  end
end
