defmodule QuorumWeb.AttendeeLiveTest do
  use QuorumWeb.ConnCase

  import Phoenix.LiveViewTest
  import Quorum.Fixtures

  alias Quorum.Sessions

  # Posting opens a ten-second window before anything is written. Most tests are
  # about what happens after it, so they send the question straight through.
  defp ask(view, params) do
    view |> form("#ask-form") |> render_submit(params)
    view |> element("button", "Send it now") |> render_click()
  end

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

    html = ask(view, %{"body" => "What is a supervision tree?"})

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

    ask(view, %{"body" => "Can I take this back?"})
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

  test "voting moves the count and fills the box, and says so to a screen reader", %{conn: conn} do
    room = room()
    question = question(room, "Why does the BEAM preempt?")

    {:ok, view, html} = live(conn, ~p"/r/#{room.join_code}")
    assert html =~ "Upvote, 0 votes"

    html = vote(view, question)

    # The box fills and the count moves. That's the whole of what a vote does.
    assert html =~ "Voted, 1 vote. Press to remove your vote"
    assert has_element?(view, ".q-vote--voted")
    refute html =~ "Held in place"

    html = vote(view, question)

    assert html =~ "Upvote, 0 votes"
    refute has_element?(view, ".q-vote--voted")
  end

  test "a pin lifts one student's question to the top of their own list", %{conn: conn} do
    room = room()
    top = question(room, "The one the room wants")
    votes(top, 3)
    other = question(room, "The one this student is watching")

    {:ok, view, html} = live(conn, ~p"/r/#{room.join_code}")
    assert above?(html, top.body, other.body)

    html = view |> element(~s(.q-pin[phx-value-id="#{other.id}"])) |> render_click()

    assert above?(html, other.body, top.body)

    # The row is unchanged apart from the pin, which fills in.
    assert has_element?(view, ~s(.q-pin--on[phx-value-id="#{other.id}"]))
    refute has_element?(view, ~s(.q-pin--on[phx-value-id="#{top.id}"]))

    # The pin is one browser's own. Another student sees the room's ranking.
    {:ok, _view, html} = live(build_conn(), ~p"/r/#{room.join_code}")
    assert above?(html, top.body, other.body)
  end

  defp vote(view, question),
    do: view |> element(~s(.q-vote[phx-value-id="#{question.id}"])) |> render_click()

  # Which of two questions the list draws first.
  defp above?(html, first, second) do
    {a, _} = :binary.match(html, first)
    {b, _} = :binary.match(html, second)
    a < b
  end

  test "an answered question moves to the answered list with voting closed", %{conn: conn} do
    room = room()
    question = question(room, "Already covered in the session")
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

  describe "the window before a question is written" do
    test "posting counts down instead of writing, and says what the window is for", %{conn: conn} do
      room = room()
      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")

      html = view |> form("#ask-form") |> render_submit(%{"body" => "Am I sure about this?"})

      assert html =~ "Am I sure about this?"
      assert html =~ "Take it back if someone&#39;s already asked it"
      assert html =~ "Cancel (10)"
      assert Sessions.list_questions(room.id) == []
    end

    test "the composer is out of the way while it counts", %{conn: conn} do
      room = room()
      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")

      html = view |> form("#ask-form") |> render_submit(%{"body" => "Counting"})

      refute html =~ "Post question"
      refute has_element?(view, "#ask-form")
    end

    test "cancelling writes nothing at all, and hands the text back", %{conn: conn} do
      room = room()
      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      view |> form("#ask-form") |> render_submit(%{"body" => "On second thoughts"})

      html = view |> element("button", "Cancel (10)") |> render_click()

      assert html =~ "Called back. Nobody saw it."
      assert html =~ "On second thoughts"
      assert has_element?(view, "#ask-form")
      assert Sessions.list_questions(room.id) == []
    end

    test "the count falls as the window runs", %{conn: conn} do
      room = room()
      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      view |> form("#ask-form") |> render_submit(%{"body" => "Tick tock"})

      send(view.pid, :tick)
      assert render(view) =~ "Cancel (9)"

      send(view.pid, :tick)
      assert render(view) =~ "Cancel (8)"

      assert Sessions.list_questions(room.id) == []
    end

    test "the last tick writes it", %{conn: conn} do
      room = room()
      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      view |> form("#ask-form") |> render_submit(%{"body" => "Through it goes"})

      for _ <- 1..10, do: send(view.pid, :tick)

      html = render(view)
      assert html =~ "Posted to the queue."
      assert [%{body: "Through it goes"}] = Sessions.list_questions(room.id)
    end

    test "send it now skips the wait", %{conn: conn} do
      room = room()
      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      view |> form("#ask-form") |> render_submit(%{"body" => "No, I'm sure"})

      html = view |> element("button", "Send it now") |> render_click()

      assert html =~ "Posted to the queue."
      assert [%{body: "No, I'm sure"}] = Sessions.list_questions(room.id)
    end

    test "a cancelled question never counted against the allowance", %{conn: conn} do
      room = room()
      Sessions.update_settings(room, %{questions_per_student: 1})

      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      view |> form("#ask-form") |> render_submit(%{"body" => "Nearly asked"})
      view |> element("button", "Cancel (10)") |> render_click()

      html = ask(view, %{"body" => "Asked instead"})

      assert html =~ "Posted to the queue."
      assert [%{body: "Asked instead"}] = Sessions.list_questions(room.id)
    end

    test "a session that closes mid-window keeps the question out, and says so", %{conn: conn} do
      room = room()
      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      view |> form("#ask-form") |> render_submit(%{"body" => "Too late"})

      Sessions.close_room(room)

      html = render(view)
      assert html =~ "The session closed before your question went in."
      refute html =~ "Cancel ("
      assert Sessions.list_questions(room.id) == []
    end

    test "a held word still holds the question at the end of the window", %{conn: conn} do
      room = room()
      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")

      html = ask(view, %{"body" => "What the fuck was that"})

      assert html =~ "Sent to your presenter for review."
      assert [%{status: :pending}] = Sessions.list_questions(room.id)
    end
  end

  describe "what the room's limits do to the composer" do
    test "a question past the room's limit is refused, and the length is named", %{conn: conn} do
      room = room()
      Sessions.update_settings(room, %{question_max_length: 140})

      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      html = ask(view, %{"body" => String.duplicate("a", 141)})

      assert html =~ "longer than 140 characters"
      assert Sessions.list_questions(room.id) == []
    end

    test "a student at their allowance is told what to do about it", %{conn: conn} do
      room = room()
      Sessions.update_settings(room, %{questions_per_student: 1})

      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      ask(view, %{"body" => "My one question"})

      html = ask(view, %{"body" => "A second one"})

      assert html =~ "already have a question waiting"
      assert length(Sessions.list_questions(room.id)) == 1
    end

    test "the count of what's left follows each post", %{conn: conn} do
      room = room()
      Sessions.update_settings(room, %{questions_per_student: 2})

      {:ok, view, html} = live(conn, ~p"/r/#{room.join_code}")
      assert html =~ "2 questions left."

      html = ask(view, %{"body" => "One"})
      assert html =~ "One question left."

      html = ask(view, %{"body" => "Two"})
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
      ask(view, %{"body" => "Anonymous one", "name" => "Amara"})

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

    test "the composer says the presenter reads first", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/r/#{room.join_code}")

      assert html =~ "reads each question before the room sees it"
    end

    test "posting says it went for review, not to the queue", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      html = ask(view, %{"body" => "Held question"})

      assert html =~ "Sent to your presenter for review."
      refute html =~ "Posted to the queue."
    end

    test "the asker sees their own held question waiting", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      html = ask(view, %{"body" => "Held question"})

      assert html =~ "Waiting for your presenter"
      assert html =~ "Held question"
      assert html =~ "Nobody else can see this yet."
    end

    test "another student's held question is invisible", %{conn: conn, room: room} do
      Sessions.ask(room.id, %{body: "Someone else's held one", submitter_token: "other-student"})

      {:ok, _view, html} = live(conn, ~p"/r/#{room.join_code}")

      refute html =~ "Someone else's held one"
      refute html =~ "Waiting for your presenter"
    end

    test "the asker can retract it while it waits", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      ask(view, %{"body" => "Held question"})

      html = view |> element("button", "Retract") |> render_click()

      refute html =~ "Held question"
      assert Sessions.list_questions(room.id) == []
    end

    test "once approved it joins the queue for everyone", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")
      ask(view, %{"body" => "Held question"})

      [question] = Sessions.list_questions(room.id)
      Sessions.approve(question)

      html = render(view)
      refute html =~ "Waiting for your presenter"
      assert html =~ "Held question"
    end
  end
end
