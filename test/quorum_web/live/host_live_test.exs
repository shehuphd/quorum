defmodule QuorumWeb.HostLiveTest do
  use QuorumWeb.ConnCase

  import Phoenix.LiveViewTest
  import Quorum.Fixtures

  alias Quorum.Sessions

  test "a host token that matches nothing says so instead of crashing", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/host/not-a-token")

    assert html =~ "That host link doesn&#39;t match a room"
  end

  test "the queue is ranked by votes", %{conn: conn} do
    room = room()
    question(room, "Asked first, one vote") |> votes(1)
    question(room, "Asked second, four votes") |> votes(4)

    {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}")

    assert html =~ "Waiting, 2"
    [first, second] = String.split(html, "Asked second, four votes")
    assert second =~ "Asked first, one vote"
    refute first =~ "Asked first, one vote"
  end

  test "spotlighting a question puts it on the projection panel", %{conn: conn} do
    room = room()
    question = question(room, "What is a linked process?")

    {:ok, view, html} = live(conn, ~p"/host/#{room.host_token}")
    assert html =~ "Nothing spotlighted"

    view
    |> element(~s(button[phx-click="spotlight"][phx-value-id="#{question.id}"]))
    |> render_click()

    html = render(view)

    assert html =~ "On the projection now"
    refute html =~ "Nothing spotlighted"
    assert {:ok, %{spotlight_question_id: id}} = Sessions.get_room(room.id)
    assert id == question.id
  end

  test "clearing the spotlight empties the panel", %{conn: conn} do
    room = room()
    question = question(room, "Briefly spotlighted")
    Sessions.spotlight(room, question.id)

    {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}")
    view |> element("button", "Clear the spotlight") |> render_click()

    assert render(view) =~ "Nothing spotlighted"
  end

  test "marking answered moves the question out of the queue, and reopening returns it", %{
    conn: conn
  } do
    room = room()
    question = question(room, "Covered already")

    {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}")

    view
    |> element(~s(button[phx-click="answer"][phx-value-id="#{question.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Waiting, 0"
    assert html =~ "Answered, 1"

    view |> element("button", "Reopen") |> render_click()
    html = render(view)
    assert html =~ "Waiting, 1"
    refute html =~ "Answered, 1"
  end

  test "hiding a question takes it off both lists", %{conn: conn} do
    room = room()
    question = question(room, "Off topic entirely")

    {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}")
    view |> element(~s(button[phx-click="hide"][phx-value-id="#{question.id}"])) |> render_click()
    html = render(view)

    refute html =~ "Off topic entirely"
    # The room is empty again, so the joining panel takes the space back.
    assert html =~ "No questions yet"
    assert html =~ "Students join at quorum.app/join with"
  end

  test "search filters the queue and reports the tally", %{conn: conn} do
    room = room()
    question(room, "How do supervisors restart children?")
    question(room, "What does GenServer.call block on?")

    {:ok, view, html} = live(conn, ~p"/host/#{room.host_token}")
    assert html =~ ~s(for="search")

    html = view |> element("#search") |> render_keyup(%{"value" => "supervisor"})

    assert html =~ "Showing 1 of 2 questions"
    assert html =~ "How do supervisors restart children?"
    refute html =~ "What does GenServer.call block on?"

    html = view |> element("#search") |> render_keyup(%{"value" => "zzz"})
    assert html =~ "No questions match that search."
  end

  test "the close dialog carries the action, and Escape keeps the session open", %{conn: conn} do
    room = room()
    {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}")

    html = view |> element("button", "Close session") |> render_click()
    assert html =~ "Close this session?"
    assert html =~ "Keep it open"
    refute html =~ ">Cancel<"

    html = render_keyup(view, "key", %{"key" => "Escape"})
    refute html =~ "Close this session?"
    assert {:ok, %{status: :open}} = Sessions.get_room(room.id)
  end

  test "keeping it open leaves the room open", %{conn: conn} do
    room = room()
    {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}")

    view |> element("button", "Close session") |> render_click()
    html = view |> element("button", "Keep it open") |> render_click()

    refute html =~ "Close this session?"
    assert {:ok, %{status: :open}} = Sessions.get_room(room.id)
  end

  test "confirming closes the room and swaps the control for a status", %{conn: conn} do
    room = room()
    {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}")

    view |> element("button", "Close session") |> render_click()

    html =
      view |> element("button.q-button--destructive-solid", "Close session") |> render_click()

    assert html =~ "Session closed"
    assert {:ok, %{status: :closed}} = Sessions.get_room(room.id)
  end

  test "J and K move the selection, and Enter spotlights it", %{conn: conn} do
    room = room()
    first = question(room, "Top of the queue") |> votes(3)
    second = question(room, "Below it")

    {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}")

    render_keyup(view, "key", %{"key" => "j"})
    render_keyup(view, "key", %{"key" => "Enter"})
    assert {:ok, %{spotlight_question_id: id}} = Sessions.get_room(room.id)
    assert id == second.id

    render_keyup(view, "key", %{"key" => "k"})
    render_keyup(view, "key", %{"key" => "Enter"})
    assert {:ok, %{spotlight_question_id: id}} = Sessions.get_room(room.id)
    assert id == first.id
  end

  test "A answers the selected question and H hides it", %{conn: conn} do
    room = room()
    question(room, "Answer me with A")

    {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}")
    render_keyup(view, "key", %{"key" => "a"})
    assert render(view) =~ "Answered, 1"

    question(room, "Hide me with H")
    assert render(view) =~ "Hide me with H"

    render_keyup(view, "key", %{"key" => "h"})
    refute render(view) =~ "Hide me with H"
  end

  test "shortcuts stay quiet while the close dialog is open", %{conn: conn} do
    room = room()
    question(room, "Should survive the dialog")

    {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}")
    view |> element("button", "Close session") |> render_click()

    render_keyup(view, "key", %{"key" => "a"})

    assert render(view) =~ "Should survive the dialog"
    assert [%{status: :visible}] = Sessions.list_questions(room.id)
  end

  test "a question asked by a student appears in the queue live", %{conn: conn} do
    room = room()
    {:ok, view, html} = live(conn, ~p"/host/#{room.host_token}")
    assert html =~ "No questions yet"

    question(room, "Just arrived from the back row")

    assert render(view) =~ "Just arrived from the back row"
  end

  test "an empty room gives the join code the space, with both code actions", %{conn: conn} do
    room = room()

    {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}")

    assert html =~ "Students join at quorum.app/join with"
    assert html =~ room.join_code
    assert html =~ "Copy student link"
    assert html =~ "New code"
    assert html =~ "Nobody has joined yet."
    # The rail carries the keyboard map, per the accessibility rule.
    assert html =~ "Before you start"
    assert html =~ "Keyboard"
  end

  test "the join panel shrinks to a strip once a question arrives", %{conn: conn} do
    room = room()
    {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}")

    question(room, "First of the lecture")
    html = render(view)

    assert html =~ "Still joining at quorum.app/join"
    refute html =~ "Students join at quorum.app/join with"
    assert html =~ "Search questions"
  end

  test "renaming the room keeps its code and host link", %{conn: conn} do
    room = room()
    {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}")

    view |> element("button", "Rename") |> render_click()

    html =
      view
      |> form("form[phx-submit='rename']", %{"name" => "PHIL 210, lecture 7"})
      |> render_submit()

    assert html =~ "PHIL 210, lecture 7"
    assert {:ok, renamed} = Sessions.get_room(room.id)
    assert renamed.name == "PHIL 210, lecture 7"
    assert renamed.join_code == room.join_code
    assert renamed.host_token == room.host_token
  end

  test "a blank rename keeps the old name", %{conn: conn} do
    room = room()
    {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}")

    view |> element("button", "Rename") |> render_click()
    view |> form("form[phx-submit='rename']", %{"name" => "   "}) |> render_submit()

    assert {:ok, kept} = Sessions.get_room(room.id)
    assert kept.name == room.name
  end

  test "a new code replaces the old one and says the old one stops working", %{conn: conn} do
    room = room()
    {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}")

    html = view |> element("button", "New code") |> render_click()

    assert html =~ "New code. The old one stops working now."
    assert {:ok, reissued} = Sessions.get_room(room.id)
    refute reissued.join_code == room.join_code
    assert Sessions.get_room_by_code(room.join_code) == {:ok, nil}
  end

  test "the reading list panel leads to the readings tab, and counts what's there", %{conn: conn} do
    room = room()

    {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}")
    assert html =~ "Attach a reading list"
    assert html =~ "Add readings"
    assert html =~ ~s(href="/host/#{room.host_token}/settings/resources")

    Sessions.add_reading(room.id, %{title: "Nagel, What Is It Like to Be a Bat?"})

    {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}")
    assert html =~ "Edit 1 reading"
    refute html =~ "Edit 1 readings"

    Sessions.add_reading(room.id, %{title: "Chalmers, Facing Up"})

    {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}")
    assert html =~ "Edit 2 readings"
  end

  test "the console links to settings", %{conn: conn} do
    room = room()

    {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}")

    assert html =~ ~s(href="/host/#{room.host_token}/settings/room")
  end
end
