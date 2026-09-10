defmodule QuorumWeb.SettingsLiveTest do
  use QuorumWeb.ConnCase

  import Phoenix.LiveViewTest
  import Quorum.Fixtures

  alias Quorum.Sessions

  @tabs ~w(room questions moderation resources projection appearance)

  # Saving takes two renders: the event marks the pane saving and hands the write
  # to the process itself, so a test has to come back once for the settled state.
  defp settle(view), do: render(view)

  describe "the rail" do
    test "carries every category, in the order the design fixes", %{conn: conn} do
      room = room()

      {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/settings/room")

      names = ["Room", "Questions", "Moderation", "Readings and AI", "Projection", "Appearance"]
      positions = Enum.map(names, &:binary.match(html, &1))

      assert Enum.all?(positions, &(&1 != :nomatch))
      assert positions == Enum.sort(positions)
    end

    test "every tab has its own URL and renders", %{conn: conn} do
      room = room()

      for tab <- @tabs do
        {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/settings/#{tab}")
        assert html =~ "Settings"
      end
    end

    test "the current tab is marked for assistive tech, not by colour alone", %{conn: conn} do
      room = room()

      {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/settings/appearance")

      assert html =~ ~s(aria-current="page")
    end

    test "every tab in the rail opens a pane of its own", %{conn: conn} do
      room = room()

      for {tab, heading} <- [
            {"room", "Room"},
            {"questions", "Questions"},
            {"moderation", "Moderation"},
            {"resources", "Readings and AI"},
            {"projection", "Projection"},
            {"appearance", "Appearance"}
          ] do
        {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/settings/#{tab}")

        assert html =~ "<h2>#{heading}</h2>"
        refute html =~ "hasn&#39;t been drawn yet"
      end
    end

    test "an unknown tab falls back to Room instead of erroring", %{conn: conn} do
      room = room()

      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, ~p"/host/#{room.host_token}/settings/nonsense")

      assert to == "/host/#{room.host_token}/settings/room"
    end

    test "a host token that matches nothing says so", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/host/not-a-token/settings/room")

      assert html =~ "That host link doesn&#39;t match a room"
    end
  end

  describe "hot save" do
    test "there is no save button anywhere on the settings screens", %{conn: conn} do
      room = room()

      for tab <- @tabs do
        {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/settings/#{tab}")
        refute html =~ ">Save<"
        refute html =~ "Save changes"
      end
    end

    test "a change applies immediately and the indicator settles on saved", %{conn: conn} do
      room = room()
      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/room")

      view |> form("#room-name-form") |> render_change(%{"name" => "PHIL 210"})

      assert settle(view) =~ "All changes saved"
      assert {:ok, saved} = Sessions.get_room(room.id)
      assert saved.name == "PHIL 210"
    end

    test "the indicator has its height reserved before anything is saved", %{conn: conn} do
      room = room()

      {:ok, view, html} = live(conn, ~p"/host/#{room.host_token}/settings/room")

      # The element is there and empty, so the first save doesn't shift the bar.
      assert has_element?(view, ".q-room-status")
      refute html =~ "All changes saved"
      refute html =~ "Saving"
    end
  end

  describe "appearance" do
    test "a colour change is stored and shown in the preview", %{conn: conn} do
      room = room()
      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/appearance")

      view
      |> form("#appearance-form")
      |> render_change(%{"projection_dark_to" => "#2B4A3F"})

      assert settle(view) =~ "#2B4A3F"
      assert {:ok, saved} = Sessions.get_room(room.id)
      assert saved.projection_dark_to == "#2B4A3F"
    end

    test "the projection renders the room's own gradient", %{conn: conn} do
      room = room()
      Sessions.update_settings(room, %{projection_dark_to: "#2B4A3F", projection_angle: 120})

      {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/project")

      assert html =~ "linear-gradient(120deg, #1A1A1A, #2B4A3F)"
    end

    test "the drift toggle names its state in words and stops the animation", %{conn: conn} do
      room = room()
      {:ok, view, html} = live(conn, ~p"/host/#{room.host_token}/settings/appearance")

      assert html =~ "Drift the gradient slowly, on"

      view |> element(~s([phx-value-field="projection_drift?"])) |> render_click()

      html = settle(view)
      assert html =~ "Drift the gradient slowly, off"
      assert html =~ ~s(aria-checked="false")

      {:ok, _view, projection} = live(conn, ~p"/host/#{room.host_token}/project")
      refute projection =~ "q-projection--waiting"
    end

    test "reset this tab puts every appearance value back", %{conn: conn} do
      room = room()
      Sessions.update_settings(room, %{projection_dark_to: "#2B4A3F", projection_angle: 300})

      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/appearance")
      view |> element("button", "Reset this tab") |> render_click()
      settle(view)

      assert {:ok, reset} = Sessions.get_room(room.id)
      assert reset.projection_dark_to == "#313131"
      assert reset.projection_angle == 60
    end
  end

  describe "questions" do
    test "the length limit saves and reaches the student's composer", %{conn: conn} do
      room = room()
      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/questions")

      view |> form("#question-limits-form") |> render_change(%{"question_max_length" => "140"})
      settle(view)

      assert {:ok, saved} = Sessions.get_room(room.id)
      assert saved.question_max_length == 140

      {:ok, _view, feed} = live(conn, ~p"/r/#{room.join_code}")
      assert feed =~ ~s(maxlength="140")
    end

    test "the allowance saves and the note follows it", %{conn: conn} do
      room = room()
      {:ok, view, html} = live(conn, ~p"/host/#{room.host_token}/settings/questions")

      assert html =~ "as many as they like"

      view |> form("#question-allowance-form") |> render_change(%{"questions_per_student" => "1"})

      assert settle(view) =~ "the one they have waiting"
      assert {:ok, %{questions_per_student: 1}} = Sessions.get_room(room.id)
    end

    test "turning off signing drops the name field from the feed", %{conn: conn} do
      room = room()
      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/questions")

      view |> element(~s([phx-value-field="allow_display_name?"])) |> render_click()

      assert settle(view) =~ "Let students sign a question, off"

      {:ok, _view, feed} = live(conn, ~p"/r/#{room.join_code}")
      refute feed =~ "Add your name"
      assert feed =~ "Every question here is anonymous."
    end

    test "keeping questions is the default, and the switch says why it matters", %{conn: conn} do
      room = room()

      {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/settings/questions")

      assert html =~ "Keep this room&#39;s questions, on"
      assert html =~ "which weeks drew nothing"
      assert html =~ "There&#39;s no undo."
    end

    test "turning keeping off means closing the session takes the questions", %{conn: conn} do
      room = room()
      Sessions.ask(room.id, %{body: "Gone at the bell", submitter_token: "a"})

      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/questions")
      view |> element(~s([phx-value-field="keep_questions?"])) |> render_click()

      assert settle(view) =~ "Keep this room&#39;s questions, off"

      {:ok, room} = Sessions.get_room(room.id)
      Sessions.close_room(room)

      assert Sessions.list_questions(room.id) == []
    end

    test "reset this tab puts the limits back", %{conn: conn} do
      room = room()

      Sessions.update_settings(room, %{
        question_max_length: 140,
        questions_per_student: 3,
        allow_display_name?: false,
        keep_questions?: false
      })

      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/questions")
      view |> element("button", "Reset this tab") |> render_click()
      settle(view)

      assert {:ok, reset} = Sessions.get_room(room.id)
      assert reset.question_max_length == 500
      assert reset.questions_per_student == 0
      assert reset.allow_display_name?
      assert reset.keep_questions?
    end
  end

  describe "moderation" do
    test "the hold switch names its state and takes effect on the next question", %{conn: conn} do
      room = room()
      {:ok, view, html} = live(conn, ~p"/host/#{room.host_token}/settings/moderation")

      assert html =~ "Hold every question for review, off"

      view |> element(~s([phx-value-field="hold_for_review?"])) |> render_click()

      assert settle(view) =~ "Hold every question for review, on"

      assert {:ok, %{status: :pending}} =
               Sessions.ask(room.id, %{body: "held one", submitter_token: "a"})
    end

    test "a room arrives with a starting list rather than an empty box", %{conn: conn} do
      room = room()

      {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/settings/moderation")

      assert html =~ "starting point, not a policy"
      assert html =~ "Remove every word"
      refute html =~ "No words held."
    end

    test "removing every word empties the list and says what to do instead", %{conn: conn} do
      room = room()

      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/moderation")
      view |> element("button", "Remove every word") |> render_click()
      html = settle(view)

      assert html =~ "No words held."
      assert {:ok, %{held_words: []}} = Sessions.get_room(room.id)
    end

    test "a word is added, listed, and holds a question", %{conn: conn} do
      room = room()
      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/moderation")

      html = view |> form("#add-word-form") |> render_submit(%{"word" => "Grade"})

      # Stored lowercase, so the list shows what actually matches.
      assert html =~ "grade"

      assert {:ok, %{status: :pending}} =
               Sessions.ask(room.id, %{body: "What about my grade?", submitter_token: "a"})
    end

    test "the same word twice is refused, and says so", %{conn: conn} do
      room = room()
      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/moderation")

      view |> form("#add-word-form") |> render_submit(%{"word" => "grade"})
      html = view |> form("#add-word-form") |> render_submit(%{"word" => "GRADE"})

      assert html =~ "That word is already on the list."
      assert {:ok, saved} = Sessions.get_room(room.id)
      assert Enum.count(saved.held_words, &(&1 == "grade")) == 1
    end

    test "a blank word is refused", %{conn: conn} do
      room = room()
      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/moderation")

      html = view |> form("#add-word-form") |> render_submit(%{"word" => "   "})

      assert html =~ "Type a word to hold."
      assert {:ok, saved} = Sessions.get_room(room.id)
      assert saved.held_words == Sessions.default_held_words()
    end

    test "a word is removed", %{conn: conn} do
      room = room()
      {:ok, room} = Sessions.update_settings(room, %{held_words: []})
      {:ok, _room} = Sessions.add_held_word(room, "grade")

      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/moderation")
      html = view |> element(~s(button[phx-value-word="grade"])) |> render_click()

      refute html =~ ">grade<"
      assert {:ok, %{held_words: []}} = Sessions.get_room(room.id)
    end

    test "the pane counts what's waiting and links to the console", %{conn: conn} do
      room = room()
      Sessions.update_settings(room, %{hold_for_review?: true})
      Sessions.ask(room.id, %{body: "waiting", submitter_token: "a"})

      {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/settings/moderation")

      assert html =~ "1 question is"
      assert html =~ ~s(href="/host/#{room.host_token}")
    end

    test "nothing waiting means no count at all", %{conn: conn} do
      room = room()

      {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/settings/moderation")

      refute html =~ "waiting for review"
    end

    test "each of the three switches names its state and takes effect", %{conn: conn} do
      room = room()
      {:ok, view, html} = live(conn, ~p"/host/#{room.host_token}/settings/moderation")

      assert html =~ "Hold a student&#39;s first question, off"
      assert html =~ "Hold anything with a link, off"

      view |> element(~s([phx-value-field="hold_first_question?"])) |> render_click()
      settle(view)
      view |> element(~s([phx-value-field="hold_links?"])) |> render_click()

      html = settle(view)
      assert html =~ "Hold a student&#39;s first question, on"
      assert html =~ "Hold anything with a link, on"

      assert {:ok, saved} = Sessions.get_room(room.id)
      assert saved.hold_first_question?
      assert saved.hold_links?
    end

    test "the account default is offered only to a signed-in presenter", %{conn: conn} do
      room = room()

      {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/settings/moderation")

      refute html =~ "Start the rooms I open"
    end

    test "a signed-in presenter can make holding the default for their next room", %{conn: conn} do
      {:ok, user, _token} = Quorum.Accounts.request_link("presenter@example.ac.uk")
      {:ok, room} = Sessions.open_room("Signed in", owner_id: user.id)
      conn = Plug.Test.init_test_session(conn, %{}) |> QuorumWeb.CurrentUser.sign_in(user)

      {:ok, view, html} = live(conn, ~p"/host/#{room.host_token}/settings/moderation")
      assert html =~ "Start the rooms I open"

      view |> element(~s(input[phx-click="toggle_account_default"])) |> render_click()

      assert {:ok, %{hold_for_review_default?: true}} = Quorum.Accounts.get_user(user.id)

      # It seeds the next room, and leaves this one where it was.
      assert {:ok, %{hold_for_review?: false}} = Sessions.get_room(room.id)
      {:ok, next} = Sessions.open_room("Opened after", owner_id: user.id)
      assert next.hold_for_review?
    end

    test "reset this tab clears the switches and puts the starting list back", %{conn: conn} do
      room = room()
      {:ok, room} = Sessions.update_settings(room, %{held_words: ["something-else"]})
      Sessions.update_settings(room, %{hold_for_review?: true})

      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/moderation")
      view |> element("button", "Reset this tab") |> render_click()
      settle(view)

      assert {:ok, reset} = Sessions.get_room(room.id)
      refute reset.hold_for_review?
      assert reset.held_words == Sessions.default_held_words()
    end
  end

  describe "projection" do
    setup %{conn: conn} do
      room = room()
      question = question(room, "What is a supervision tree?") |> votes(3)
      Sessions.spotlight(room, question.id)
      %{room: room, conn: conn}
    end

    test "the size saves and the projected question follows it", %{conn: conn, room: room} do
      {:ok, view, html} = live(conn, ~p"/host/#{room.host_token}/settings/projection")
      assert html =~ "readable from the back of a full hall"

      view
      |> form("#projection-scale-form")
      |> render_change(%{"projection_question_scale" => "150"})

      assert settle(view) =~ "As large as it goes"

      {:ok, _view, wall} = live(conn, ~p"/host/#{room.host_token}/project")
      assert wall =~ "font-size:93px"
    end

    test "the standard size adds no override at all", %{conn: conn, room: room} do
      {:ok, _view, wall} = live(conn, ~p"/host/#{room.host_token}/project")

      refute wall =~ "font-size:62px"
      assert wall =~ "q-question--projected"
    end

    test "turning off who asked drops it from the wall", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/projection")

      view |> element(~s([phx-value-field="projection_show_asker?"])) |> render_click()
      assert settle(view) =~ "Show who asked, off"

      {:ok, _view, wall} = live(conn, ~p"/host/#{room.host_token}/project")
      refute wall =~ "Asked anonymously"
      assert wall =~ "3 votes"
    end

    test "turning off the vote count drops it from the wall", %{conn: conn, room: room} do
      Sessions.update_settings(room, %{projection_show_votes?: false})

      {:ok, _view, wall} = live(conn, ~p"/host/#{room.host_token}/project")

      refute wall =~ "3 votes"
      assert wall =~ "Asked anonymously"
    end

    test "with both off there is no line under the question at all", %{conn: conn, room: room} do
      Sessions.update_settings(room, %{
        projection_show_asker?: false,
        projection_show_votes?: false
      })

      {:ok, _view, wall} = live(conn, ~p"/host/#{room.host_token}/project")

      refute wall =~ "Asked anonymously"
      refute wall =~ "3 votes"
      assert wall =~ "What is a supervision tree?"
    end

    test "the join rail can be taken off while answering", %{conn: conn, room: room} do
      {:ok, _view, with_rail} = live(conn, ~p"/host/#{room.host_token}/project")
      assert with_rail =~ "Scan to ask a question"

      Sessions.update_settings(room, %{projection_show_joining?: false})

      {:ok, _view, without} = live(conn, ~p"/host/#{room.host_token}/project")
      refute without =~ "Scan to ask a question"
      assert without =~ "What is a supervision tree?"
    end

    test "the join code still owns the waiting screen whatever that switch says", %{
      conn: conn,
      room: room
    } do
      Sessions.update_settings(room, %{projection_show_joining?: false})
      {:ok, room} = Sessions.get_room(room.id)
      Sessions.clear_spotlight(room)

      {:ok, _view, wall} = live(conn, ~p"/host/#{room.host_token}/project")

      assert wall =~ "Scan to ask a question"
      assert wall =~ room.join_code
    end

    test "the counts can be taken off the bottom", %{conn: conn, room: room} do
      Sessions.update_settings(room, %{projection_show_counts?: false})

      {:ok, _view, wall} = live(conn, ~p"/host/#{room.host_token}/project")

      refute wall =~ "connected"
      # The keyboard hint stays, since it's the only place the map is shown.
      assert wall =~ "for a lit hall"
    end

    test "reset this tab puts all five back", %{conn: conn, room: room} do
      Sessions.update_settings(room, %{
        projection_question_scale: 150,
        projection_show_asker?: false,
        projection_show_votes?: false,
        projection_show_joining?: false,
        projection_show_counts?: false
      })

      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/projection")
      view |> element("button", "Reset this tab") |> render_click()
      settle(view)

      assert {:ok, reset} = Sessions.get_room(room.id)
      assert reset.projection_question_scale == 100
      assert reset.projection_show_asker?
      assert reset.projection_show_votes?
      assert reset.projection_show_joining?
      assert reset.projection_show_counts?
    end
  end

  describe "readings" do
    test "the empty list says what the first reading does", %{conn: conn} do
      room = room()

      {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/settings/resources")

      assert html =~ "No readings yet."
      assert html =~ "the only material a suggestion can"
    end

    test "a reading is added and listed", %{conn: conn} do
      room = room()
      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/resources")

      html =
        view
        |> form("#add-reading-form")
        |> render_submit(%{
          "title" => "Nagel, What Is It Like to Be a Bat?",
          "detail" => "pp. 435 to 441",
          "url" => ""
        })

      assert html =~ "Nagel, What Is It Like to Be a Bat?"
      assert html =~ "pp. 435 to 441"
      assert [%{title: "Nagel, What Is It Like to Be a Bat?"}] = Sessions.list_readings(room.id)
    end

    test "a reading with no title is refused", %{conn: conn} do
      room = room()
      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/resources")

      html =
        view
        |> form("#add-reading-form")
        |> render_submit(%{"title" => "   ", "detail" => "", "url" => ""})

      assert html =~ "A reading needs a title."
      assert Sessions.list_readings(room.id) == []
    end

    test "search filters the list and reports the tally", %{conn: conn} do
      room = room()
      Sessions.add_reading(room.id, %{title: "Nagel, What Is It Like to Be a Bat?"})
      Sessions.add_reading(room.id, %{title: "Lecture 6 slides", detail: "the epistemic gap"})
      Sessions.add_reading(room.id, %{title: "Chalmers, Facing Up"})

      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/resources")

      html = view |> element("#reading-search") |> render_keyup(%{"value" => "nagel"})
      assert html =~ "Showing 1 of 3 readings"
      assert html =~ "Nagel, What Is It Like to Be a Bat?"
      refute html =~ "Chalmers, Facing Up"

      # It searches the detail as well as the title.
      html = view |> element("#reading-search") |> render_keyup(%{"value" => "epistemic"})
      assert html =~ "Showing 1 of 3 readings"
      assert html =~ "Lecture 6 slides"

      html = view |> element("#reading-search") |> render_keyup(%{"value" => "zzzz"})
      assert html =~ "No readings match that search."
    end

    test "Escape in the search box clears it rather than doing nothing", %{conn: conn} do
      room = room()
      Sessions.add_reading(room.id, %{title: "Nagel, What Is It Like to Be a Bat?"})
      Sessions.add_reading(room.id, %{title: "Chalmers, Facing Up"})

      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/resources")
      view |> element("#reading-search") |> render_keyup(%{"value" => "nagel"})

      html =
        view |> element("#reading-search") |> render_keyup(%{"key" => "Escape", "value" => ""})

      assert html =~ "Chalmers, Facing Up"
      refute html =~ "Showing 1 of 2"
    end

    test "a reading can be removed", %{conn: conn} do
      room = room()
      Sessions.add_reading(room.id, %{title: "Remove me"})

      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/resources")
      html = view |> element("button", "Remove") |> render_click()

      refute html =~ "Remove me"
      assert Sessions.list_readings(room.id) == []
    end

    test "one room's readings never appear in another's", %{conn: conn} do
      mine = room()
      theirs = room("Someone else's session")
      Sessions.add_reading(theirs.id, %{title: "Their reading"})

      {:ok, _view, html} = live(conn, ~p"/host/#{mine.host_token}/settings/resources")

      refute html =~ "Their reading"
    end

    test "the pointer toggle names its state in words", %{conn: conn} do
      room = room()
      {:ok, view, html} = live(conn, ~p"/host/#{room.host_token}/settings/resources")

      assert html =~ "Point students to approved readings, off"

      view |> element(~s([phx-value-field="readings_pointer?"])) |> render_click()

      html = settle(view)
      assert html =~ "Point students to approved readings, on"
      assert html =~ ~s(aria-checked="true")
      assert {:ok, saved} = Sessions.get_room(room.id)
      assert saved.readings_pointer?
    end
  end

  describe "deleting a room" do
    test "the control is disabled while the session is open, and says why", %{conn: conn} do
      room = room()

      {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/settings/room")

      assert html =~ ~s(disabled="disabled")
      assert html =~ "Close the session first. Deleting is permanent."
    end

    test "once closed, the dialog needs the room's name typed before it will delete", %{
      conn: conn
    } do
      room = room("Distributed Systems 301")
      Sessions.close_room(room)

      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/room")
      html = view |> element("button", "Delete room") |> render_click()

      assert html =~ "Delete Distributed Systems 301?"
      assert html =~ "can&#39;t be undone"
      assert html =~ "Type the room&#39;s name to turn this on."

      # A near miss leaves the button disabled.
      html =
        view |> element("#delete-confirm") |> render_keyup(%{"value" => "Distributed Systems"})

      assert html =~ "Type the room&#39;s name to turn this on."

      html =
        view
        |> element("#delete-confirm")
        |> render_keyup(%{"value" => "Distributed Systems 301"})

      refute html =~ "Type the room&#39;s name to turn this on."
    end

    test "the typed name deletes the room", %{conn: conn} do
      room = room("Distributed Systems 301")
      Sessions.close_room(room)

      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/room")
      view |> element("button", "Delete room") |> render_click()
      view |> element("#delete-confirm") |> render_keyup(%{"value" => "Distributed Systems 301"})

      assert {:error, {:live_redirect, %{to: "/"}}} =
               view |> element("button.q-button--destructive-solid") |> render_click()

      assert Sessions.get_room_by_host_token(room.host_token) == {:ok, nil}
    end

    test "Escape cancels the dialog and the room survives", %{conn: conn} do
      room = room()
      Sessions.close_room(room)

      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/room")
      view |> element("button", "Delete room") |> render_click()

      html = render_keyup(view, "key", %{"key" => "Escape"})

      refute html =~ "Keep the room"
      assert {:ok, %{}} = Sessions.get_room_by_host_token(room.host_token)
    end
  end

  describe "closing automatically" do
    test "the time is read and written in the presenter's own clock", %{conn: conn} do
      room = room()

      # Two hours east of UTC, as a browser in Johannesburg reports it.
      conn = put_connect_params(conn, %{"tz_offset" => 120})
      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/room")

      view
      |> form("#auto-close-form", %{"auto_close_at" => "2026-09-10T18:00"})
      |> render_change()

      settle(view)
      {:ok, room} = Sessions.get_room(room.id)

      # 18:00 there is 16:00 UTC, which is what the sweep will compare against.
      assert DateTime.to_iso8601(room.auto_close_at) == "2026-09-10T16:00:00Z"

      # And it reads back as the time that was typed, not the one stored.
      assert render(view) =~ ~s(value="2026-09-10T18:00")
    end

    test "emptying the field puts the room back to closing by hand", %{conn: conn} do
      room = room()
      {:ok, _} = Sessions.update_settings(room, %{auto_close_at: DateTime.utc_now()})

      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/room")
      view |> form("#auto-close-form", %{"auto_close_at" => ""}) |> render_change()
      settle(view)

      {:ok, room} = Sessions.get_room(room.id)
      assert room.auto_close_at == nil
    end
  end

  describe "the AI keys tab" do
    setup do
      on_exit(fn ->
        Application.delete_env(:quorum, :ai_stub_api)
        Application.delete_env(:quorum, :ai_stub)
      end)
    end

    defp ai_api(map), do: Application.put_env(:quorum, :ai_stub_api, map)

    defp one_target do
      %{
        "name" => "anthropic",
        "provider" => "anthropic",
        "key_hint" => "sk-a************",
        "model" => nil,
        "models" => ["model-new", "model-old"]
      }
    end

    test "with the service down, the tab says so and how to start it", %{conn: conn} do
      room = room()
      {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/settings/ai")

      assert html =~ "The AI service isn&#39;t running"
      assert html =~ "./sidecar/run.sh"
    end

    test "each key shows its provider, its first four characters, and its models", %{conn: conn} do
      ai_api(%{targets: fn -> {:ok, [one_target()]} end, providers: fn -> {:ok, ["gemini"]} end})
      room = room()

      {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/settings/ai")

      assert html =~ "sk-a************"
      assert html =~ "Automatic: newest that answers"
      assert html =~ "model-new"
      refute html =~ "sk-ant-"
    end

    test "a key is tested the moment it stops being typed, and a tick confirms it", %{conn: conn} do
      test_pid = self()

      ai_api(%{
        targets: fn -> {:ok, []} end,
        providers: fn -> {:ok, ["deepseek"]} end,
        put_target: fn params ->
          send(test_pid, {:stored, params})
          {:ok, %{"ok" => true, "models" => ["a", "b", "c"]}}
        end
      })

      room = room()
      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/ai")

      html =
        view
        |> form("[id^=ai-key-form]", %{"provider" => "deepseek", "key" => "sk-something"})
        |> render_change()

      assert html =~ "Checking the key"
      assert render(view) =~ "Key accepted: 3 usable models."
      assert_received {:stored, %{provider: "deepseek", key: "sk-something"}}
    end

    test "a refused key says what the provider said", %{conn: conn} do
      ai_api(%{
        targets: fn -> {:ok, []} end,
        providers: fn -> {:ok, ["deepseek"]} end,
        put_target: fn _params -> {:error, {:sidecar, 422, "Your api key is invalid"}} end
      })

      room = room()
      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/ai")

      view
      |> form("[id^=ai-key-form]", %{"provider" => "deepseek", "key" => "sk-bad"})
      |> render_change()

      assert render(view) =~ "Your api key is invalid"
    end

    test "a key with no provider picked is told, not tested", %{conn: conn} do
      ai_api(%{targets: fn -> {:ok, []} end, providers: fn -> {:ok, ["deepseek"]} end})
      room = room()
      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/ai")

      html =
        view
        |> form("[id^=ai-key-form]", %{"provider" => "", "key" => "sk-something"})
        |> render_change()

      assert html =~ "Pick the provider the key is for first."
    end

    test "pinning a model and removing a key go through the service", %{conn: conn} do
      test_pid = self()

      ai_api(%{
        targets: fn -> {:ok, [one_target()]} end,
        providers: fn -> {:ok, []} end,
        put_model: fn name, model ->
          send(test_pid, {:pinned, name, model})
          {:ok, %{"ok" => true}}
        end,
        delete_target: fn name ->
          send(test_pid, {:removed, name})
          :ok
        end
      })

      room = room()
      {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/settings/ai")

      view
      |> element(~s(form[phx-change="ai_pin"]))
      |> render_change(%{"target" => "anthropic", "model" => "model-old"})

      assert_received {:pinned, "anthropic", "model-old"}

      view |> element("button", "Remove") |> render_click()
      assert_received {:removed, "anthropic"}
    end

    test "the spend counter adds up and clears", %{conn: conn} do
      ai_api(%{targets: fn -> {:ok, []} end, providers: fn -> {:ok, []} end})

      Application.put_env(:quorum, :ai_stub, fn _request ->
        {:ok, %{"text" => "x", "input_tokens" => 100, "output_tokens" => 7}}
      end)

      {:ok, _} = Quorum.AI.generate(:draft, "a")
      {:ok, _} = Quorum.AI.generate(:pointer, "b")

      room = room()
      {:ok, view, html} = live(conn, ~p"/host/#{room.host_token}/settings/ai")

      assert html =~ "2</strong> calls"
      assert html =~ "200</strong> tokens in"
      assert html =~ "14</strong> tokens out"
      assert html =~ "1 reading pointers, 1 drafts"

      html = view |> element("button", "Clear the counter") |> render_click()
      assert html =~ "0</strong> calls"
      assert html =~ "Nothing spent yet."
    end

    test "priced calls show dollars, and a mixed set says what they cover", %{conn: conn} do
      ai_api(%{targets: fn -> {:ok, []} end, providers: fn -> {:ok, []} end})

      Application.put_env(:quorum, :ai_stub, fn _request ->
        {:ok, %{"text" => "x", "input_tokens" => 10, "output_tokens" => 5, "cost" => "0.001200"}}
      end)

      {:ok, _} = Quorum.AI.generate(:draft, "a")

      Application.put_env(:quorum, :ai_stub, fn _request ->
        {:ok, %{"text" => "x", "input_tokens" => 10, "output_tokens" => 5}}
      end)

      {:ok, _} = Quorum.AI.generate(:screen, "b")

      room = room()
      {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/settings/ai")

      assert html =~ "$0.0012</strong> spent"
      assert html =~ "Dollars cover 1 of 2 calls; the rest count tokens only."
    end
  end
end
