defmodule QuorumWeb.SessionControllerTest do
  use QuorumWeb.ConnCase

  import Swoosh.TestAssertions

  alias Quorum.Accounts
  alias QuorumWeb.CurrentUser

  test "the sign-in page offers the email link and holds SSO back honestly", %{conn: conn} do
    html = conn |> get(~p"/sign-in") |> html_response(200)

    assert html =~ "Sign in"
    assert html =~ ~s(for="email")
    assert html =~ "Email me a sign-in link"
    # The SSO control is disabled rather than inert-looking, and says what turns it on.
    assert html =~ ~s(disabled="disabled")
    assert html =~ "Single sign-on turns on once your institution"
    assert html =~ "Join a lecture with a code"
  end

  test "asking for a link emails one and moves to the check-your-email screen", %{conn: conn} do
    conn = post(conn, ~p"/sign-in", %{"email" => "a.adeyemi@university.ac.uk"})

    assert redirected_to(conn) =~ "/sign-in/sent"

    assert_email_sent(fn email ->
      assert {_, "a.adeyemi@university.ac.uk"} = hd(email.to)
      assert email.subject == "Your Quorum sign-in link"
      assert email.text_body =~ "/sign-in/"
    end)
  end

  test "a bad address is refused on the page rather than silently accepted", %{conn: conn} do
    html = conn |> post(~p"/sign-in", %{"email" => "nope"}) |> html_response(422)

    assert html =~ "That doesn&#39;t look like an email address."
    assert_no_email_sent()
  end

  test "the check-your-email screen names the address and the wait", %{conn: conn} do
    post(conn, ~p"/sign-in", %{"email" => "a.adeyemi@university.ac.uk"})
    html = conn |> get(~p"/sign-in/sent?email=a.adeyemi@university.ac.uk") |> html_response(200)

    assert html =~ "Check your email"
    assert html =~ "a.adeyemi@university.ac.uk"
    assert html =~ "Send it again"
    assert html =~ "You can ask for a new link in"
  end

  test "a second request inside the cooldown sends no second email", %{conn: conn} do
    post(conn, ~p"/sign-in", %{"email" => "a.adeyemi@university.ac.uk"})
    assert_email_sent()

    conn = post(conn, ~p"/sign-in", %{"email" => "a.adeyemi@university.ac.uk"})

    assert redirected_to(conn) =~ "/sign-in/sent"
    assert_no_email_sent()
  end

  test "clicking the link signs the lecturer in and opens their rooms", %{conn: conn} do
    {:ok, user, token} = Accounts.request_link("a.adeyemi@university.ac.uk")

    conn = get(conn, ~p"/sign-in/#{token.token}")

    assert redirected_to(conn) == ~p"/rooms"
    assert get_session(conn, CurrentUser.session_key()) == user.id
  end

  test "a used link says so rather than signing anyone in", %{conn: conn} do
    {:ok, _user, token} = Accounts.request_link("a.adeyemi@university.ac.uk")
    get(conn, ~p"/sign-in/#{token.token}")

    html = build_conn() |> get(~p"/sign-in/#{token.token}") |> html_response(200)

    assert html =~ "That link has been used"
    assert html =~ "Ask for a new link"
  end

  test "a token that never existed says so", %{conn: conn} do
    html = conn |> get(~p"/sign-in/not-a-token") |> html_response(200)

    assert html =~ "That link doesn&#39;t work"
  end

  test "signing out drops the session", %{conn: conn} do
    {:ok, _user, token} = Accounts.request_link("a.adeyemi@university.ac.uk")
    conn = get(conn, ~p"/sign-in/#{token.token}")

    assert get_session(conn, CurrentUser.session_key())

    conn = delete(conn, ~p"/sign-out")
    assert redirected_to(conn) == ~p"/"

    # The next request carries no session, so /rooms sends them back to sign in.
    assert conn |> recycle() |> get(~p"/rooms") |> redirected_to() == ~p"/sign-in"
  end

  test "rooms is for signed-in lecturers, and sends anyone else to sign in", %{conn: conn} do
    assert conn |> get(~p"/rooms") |> redirected_to() == ~p"/sign-in"
  end

  test "a signed-in lecturer sees the rooms they opened, and not other people's", %{conn: conn} do
    {:ok, _user, token} = Accounts.request_link("a.adeyemi@university.ac.uk")
    conn = get(conn, ~p"/sign-in/#{token.token}")

    conn = get(conn, ~p"/start")
    {:ok, _other} = Quorum.Sessions.open_room("Someone else's lecture")

    html = conn |> recycle() |> get(~p"/rooms") |> html_response(200)

    assert html =~ "New lecture"
    refute html =~ "Someone else&#39;s lecture"
  end
end
