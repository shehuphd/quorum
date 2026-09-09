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

    test "a tab that isn't drawn says so rather than looking broken", %{conn: conn} do
      room = room()

      {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/settings/moderation")

      assert html =~ "Not drawn yet"
      assert html =~ "Holding questions for review"
      assert html =~ "Nothing is missing"
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
      theirs = room("Someone else's lecture")
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
end
