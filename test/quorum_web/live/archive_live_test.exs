defmodule QuorumWeb.ArchiveLiveTest do
  use QuorumWeb.ConnCase

  import Phoenix.LiveViewTest
  import Quorum.Fixtures

  alias Quorum.Accounts
  alias Quorum.Sessions

  setup %{conn: conn} do
    {:ok, user, _token} = Accounts.request_link("presenter@example.com")
    %{conn: sign_in(conn, user), user: user}
  end

  defp sign_in(conn, user) do
    Plug.Test.init_test_session(conn, %{QuorumWeb.CurrentUser.session_key() => user.id})
  end

  defp session(user, name, bodies) do
    {:ok, room} = Sessions.open_room(name, owner_id: user.id)
    questions = Enum.map(bodies, &question(room, &1))
    {room, questions}
  end

  test "a presenter with no sessions is told what the page will hold", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/archive")

    assert html =~ "Nothing to read back yet"
    refute html =~ "Download CSV"
  end

  test "signing in is required", %{} do
    assert {:error, {:live_redirect, %{to: "/sign-in"}}} = live(build_conn(), ~p"/archive")
  end

  test "every session is listed with what it drew, newest first", %{conn: conn, user: user} do
    session(user, "Week one", ["What is a process?"])
    session(user, "Week two", ["What is a supervisor?", "What is a mailbox?"])

    {:ok, view, html} = live(conn, ~p"/archive")

    assert html =~ "Week one"
    assert html =~ "What is a supervisor?"
    assert has_element?(view, ".q-stat", "sessions")
    assert has_element?(view, ".q-stat", "questions asked")
    assert before?(html, "Week two", "Week one")
  end

  test "questions rank the way the hall ranked them, and the order can be flipped", %{
    conn: conn,
    user: user
  } do
    {_room, [first, second]} = session(user, "Week one", ["Asked first", "Asked second"])
    votes(second, 4)
    votes(first, 1)

    {:ok, view, html} = live(conn, ~p"/archive")
    assert before?(html, "Asked second", "Asked first")

    html = view |> form("#archive-filters", %{"sort" => "newest"}) |> render_change()
    assert before?(html, "Asked second", "Asked first")
  end

  test "the search runs over every session at once", %{conn: conn, user: user} do
    session(user, "Week one", ["What is a mailbox?"])
    session(user, "Week two", ["Is the mailbox unbounded?", "What is a supervisor?"])

    {:ok, view, _html} = live(conn, ~p"/archive")
    html = view |> element("#search") |> render_change(%{"search" => "mailbox"})

    assert html =~ "2 questions matching"
    assert html =~ "Is the mailbox unbounded?"
    refute html =~ "What is a supervisor?"

    html = view |> element("#search") |> render_change(%{"search" => "cabbage"})
    assert html =~ "Nothing matches"
  end

  test "the filter narrows to one session", %{conn: conn, user: user} do
    {room, _} = session(user, "Week one", ["What is a process?"])
    session(user, "Week two", ["What is a supervisor?"])

    {:ok, view, _html} = live(conn, ~p"/archive")
    html = view |> form("#archive-filters", %{"room" => room.id}) |> render_change()

    assert html =~ "What is a process?"
    refute html =~ "What is a supervisor?"
  end

  test "a long session shows its top questions and expands to the rest", %{conn: conn, user: user} do
    session(user, "A busy week", Enum.map(1..7, &"Question number #{&1}"))

    {:ok, view, html} = live(conn, ~p"/archive")
    refute html =~ "Question number 7"
    assert html =~ "Show all 7 questions"

    html = view |> element("button", "Show all 7 questions") |> render_click()
    assert html =~ "Question number 7"
    assert html =~ "Show fewer"
  end

  test "a session that drew nothing says so, since a quiet week is the point", %{
    conn: conn,
    user: user
  } do
    session(user, "Nobody asked anything", [])

    {:ok, _view, html} = live(conn, ~p"/archive")

    assert html =~ "This session drew no questions."
  end

  test "one presenter never sees another's questions", %{conn: conn, user: user} do
    session(user, "Mine", ["My own question"])

    {:ok, other, _token} = Accounts.request_link("someone@example.com")
    session(other, "Theirs", ["Someone else's question"])

    {:ok, _view, html} = live(conn, ~p"/archive")

    assert html =~ "My own question"
    refute html =~ "Someone else's question"
  end

  test "held and hidden questions are left out of the record", %{conn: conn, user: user} do
    {room, _} = session(user, "Week one", ["A question the room saw"])
    {:ok, _} = Sessions.update_settings(room, %{hold_for_review?: true})
    question(room, "A question the room never saw")

    {:ok, _view, html} = live(conn, ~p"/archive")

    assert html =~ "A question the room saw"
    refute html =~ "A question the room never saw"
  end

  test "the CSV carries a row per question, quoted", %{conn: conn, user: user} do
    session(user, "Week one", [~s(A question with a comma, and "quotes")])

    conn = get(conn, ~p"/archive/export")

    assert response_content_type(conn, :csv) =~ "text/csv"
    assert conn.resp_body =~ ~s("Session","Date","Question","Votes","Status","Asker")
    assert conn.resp_body =~ ~s("A question with a comma, and ""quotes""")
  end

  test "the CSV is for the signed-in presenter only" do
    assert build_conn() |> get(~p"/archive/export") |> redirected_to() == "/sign-in"
  end

  defp before?(html, first, second) do
    {a, _} = :binary.match(html, first)
    {b, _} = :binary.match(html, second)
    a < b
  end
end
