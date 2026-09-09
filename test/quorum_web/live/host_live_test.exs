defmodule QuorumWeb.HostLiveTest do
  use QuorumWeb.ConnCase

  import Phoenix.LiveViewTest
  import Quorum.Fixtures

  alias Quorum.Sessions

  test "a host token that matches nothing says so instead of crashing", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/host/not-a-token")

    assert html =~ "That host link doesn&#39;t match a room."
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
    assert html =~ "Nothing is on the projection."

    view
    |> element(~s(button[phx-click="spotlight"][phx-value-id="#{question.id}"]))
    |> render_click()

    html = render(view)

    assert html =~ "On the projection now"
    refute html =~ "Nothing is on the projection."
    assert {:ok, %{spotlight_question_id: id}} = Sessions.get_room(room.id)
    assert id == question.id
  end

  test "clearing the spotlight empties the panel", %{conn: conn} do
    room = room()
    question = question(room, "Briefly spotlighted")
    Sessions.spotlight(room, question.id)

    {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}")
    view |> element("button", "Clear the spotlight") |> render_click()

    assert render(view) =~ "Nothing is on the projection."
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
    assert html =~ "Waiting, 0"
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
    assert html =~ "No questions waiting."

    question(room, "Just arrived from the back row")

    assert render(view) =~ "Just arrived from the back row"
  end
end
