defmodule QuorumWeb.AttendeeLiveTest do
  use QuorumWeb.ConnCase

  import Phoenix.LiveViewTest
  import Quorum.Fixtures

  alias Quorum.Sessions

  test "an unknown code sends the student back to the join screen", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/join?code=ZZZZZ"}}} = live(conn, ~p"/r/zzzzz")
  end

  test "the composer carries a label and the questions already asked", %{conn: conn} do
    room = room()
    question(room, "How does back-pressure work in Broadway?")

    {:ok, _view, html} = live(conn, ~p"/r/#{room.join_code}")

    assert html =~ ~s(for="body")
    assert html =~ "How does back-pressure work in Broadway?"
  end

  test "posting a question shows it in the feed with a status line", %{conn: conn} do
    room = room()
    {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")

    html = view |> form("form", %{"body" => "What is a supervision tree?"}) |> render_submit()

    assert html =~ "What is a supervision tree?"
    assert html =~ "Posted to the queue."
  end

  test "an unsent draft is held on the server, so a reconnect keeps it", %{conn: conn} do
    room = room()
    {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")

    view |> element("#ask-form") |> render_change(%{"body" => "Half a question so f"})

    assert render(view) =~ "Half a question so f"

    view
    |> form("#ask-form", %{"body" => "Half a question so far, now finished"})
    |> render_submit()

    refute render(view) =~ "Half a question so f</textarea>"
  end

  test "a blank question posts nothing", %{conn: conn} do
    room = room()
    {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")

    view |> form("form", %{"body" => "   "}) |> render_submit()

    assert Sessions.list_questions(room.id) == []
  end

  test "a question posted here can be retracted by its author", %{conn: conn} do
    room = room()
    {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")

    view |> form("form", %{"body" => "Can I take this back?"}) |> render_submit()
    assert render(view) =~ "Your question"

    html = view |> element("button", "Retract it") |> render_click()

    refute html =~ "Can I take this back?"
    assert Sessions.list_questions(room.id) == []
  end

  test "someone else's question offers no retract control", %{conn: conn} do
    room = room()
    question(room, "Posted from another phone")

    {:ok, _view, html} = live(conn, ~p"/r/#{room.join_code}")

    refute html =~ "Retract it"
    assert html =~ "Anonymous"
  end

  test "voting says Voted in words, not colour alone, and unvoting reverses it", %{conn: conn} do
    room = room()
    question = question(room, "Why does the BEAM preempt?")

    {:ok, view, html} = live(conn, ~p"/r/#{room.join_code}")
    assert html =~ "Upvote, 0 votes"

    html = view |> element(~s(button[phx-value-id="#{question.id}"])) |> render_click()

    assert html =~ "Voted, 1 vote. Press to remove your vote"
    assert html =~ "Voted. Held in place while you read."

    html = view |> element(~s(button[phx-value-id="#{question.id}"])) |> render_click()

    assert html =~ "Upvote, 0 votes"
  end

  test "a voted row that is no longer pinned still says Voted", %{conn: conn} do
    room = room()
    question = question(room, "Does the word survive a resort?")

    {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
    view |> element(~s(button[phx-value-id="#{question.id}"])) |> render_click()

    view |> element("button", "Let it move") |> render_click()

    assert has_element?(view, ".q-status--saved", "Voted")
    refute has_element?(view, ".q-status--saved", "Held in place")
    assert render(view) =~ "Voted, 1 vote. Press to remove your vote"
  end

  test "an answered question moves to the answered list with voting closed", %{conn: conn} do
    room = room()
    question = question(room, "Already covered in the lecture")
    Sessions.answer(question)

    {:ok, _view, html} = live(conn, ~p"/r/#{room.join_code}")

    assert html =~ "Answered, 1"
    assert html =~ ~s(disabled="disabled")
    assert html =~ "Voting closed"
  end

  test "a closed room takes the composer away and says why", %{conn: conn} do
    room = room()
    Sessions.close_room(room)

    {:ok, _view, html} = live(conn, ~p"/r/#{room.join_code}")

    assert html =~ "This session is closed"
    assert html =~ "Students can still read."
    refute html =~ "Post question"
  end

  test "a question asked elsewhere arrives without a refresh", %{conn: conn} do
    room = room()
    {:ok, view, html} = live(conn, ~p"/r/#{room.join_code}")
    refute html =~ "Asked from the back row"

    question(room, "Asked from the back row")

    assert render(view) =~ "Asked from the back row"
  end
end
