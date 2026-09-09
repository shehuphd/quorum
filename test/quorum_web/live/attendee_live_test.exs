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

  describe "what the room's limits do to the composer" do
    test "a question past the room's limit is refused, and the length is named", %{conn: conn} do
      room = room()
      Sessions.update_settings(room, %{question_max_length: 140})

      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      html = view |> form("#ask-form") |> render_submit(%{"body" => String.duplicate("a", 141)})

      assert html =~ "longer than 140 characters"
      assert Sessions.list_questions(room.id) == []
    end

    test "a student at their allowance is told what to do about it", %{conn: conn} do
      room = room()
      Sessions.update_settings(room, %{questions_per_student: 1})

      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      view |> form("#ask-form") |> render_submit(%{"body" => "My one question"})

      html = view |> form("#ask-form") |> render_submit(%{"body" => "A second one"})

      assert html =~ "already have a question waiting"
      assert length(Sessions.list_questions(room.id)) == 1
    end

    test "the count of what's left follows each post", %{conn: conn} do
      room = room()
      Sessions.update_settings(room, %{questions_per_student: 2})

      {:ok, view, html} = live(conn, ~p"/r/#{room.join_code}")
      assert html =~ "2 questions left."

      html = view |> form("#ask-form") |> render_submit(%{"body" => "One"})
      assert html =~ "One question left."

      html = view |> form("#ask-form") |> render_submit(%{"body" => "Two"})
      assert html =~ "used your questions for now"
    end

    test "no limit means no count on the screen at all", %{conn: conn} do
      room = room()

      {:ok, _view, html} = live(conn, ~p"/r/#{room.join_code}")

      refute html =~ "questions left"
    end

    test "with signing off, a name sent anyway is dropped", %{conn: conn} do
      room = room()
      Sessions.update_settings(room, %{allow_display_name?: false})

      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      view |> form("#ask-form") |> render_submit(%{"body" => "Anonymous one", "name" => "Amara"})

      assert [%{display_name: nil}] = Sessions.list_questions(room.id)
      refute render(view) =~ "Amara"
    end
  end

  describe "a question held for review" do
    setup %{conn: conn} do
      room = room()
      Sessions.update_settings(room, %{hold_for_review?: true})
      %{room: room, conn: conn}
    end

    test "the composer says the lecturer reads first", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/r/#{room.join_code}")

      assert html =~ "reads each question before the room sees it"
    end

    test "posting says it went for review, not to the queue", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      html = view |> form("#ask-form") |> render_submit(%{"body" => "Held question"})

      assert html =~ "Sent to your lecturer for review."
      refute html =~ "Posted to the queue."
    end

    test "the asker sees their own held question waiting", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      html = view |> form("#ask-form") |> render_submit(%{"body" => "Held question"})

      assert html =~ "Waiting for your lecturer"
      assert html =~ "Held question"
      assert html =~ "Nobody else can see this yet."
    end

    test "another student's held question is invisible", %{conn: conn, room: room} do
      Sessions.ask(room.id, %{body: "Someone else's held one", submitter_token: "other-student"})

      {:ok, _view, html} = live(conn, ~p"/r/#{room.join_code}")

      refute html =~ "Someone else's held one"
      refute html =~ "Waiting for your lecturer"
    end

    test "the asker can retract it while it waits", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      view |> form("#ask-form") |> render_submit(%{"body" => "Held question"})

      html = view |> element("button", "Retract") |> render_click()

      refute html =~ "Held question"
      assert Sessions.list_questions(room.id) == []
    end

    test "once approved it joins the queue for everyone", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      view |> form("#ask-form") |> render_submit(%{"body" => "Held question"})

      [question] = Sessions.list_questions(room.id)
      Sessions.approve(question)

      html = render(view)
      refute html =~ "Waiting for your lecturer"
      assert html =~ "Held question"
    end
  end
end
