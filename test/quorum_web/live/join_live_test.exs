defmodule QuorumWeb.JoinLiveTest do
  use QuorumWeb.ConnCase

  import Phoenix.LiveViewTest
  import Quorum.Fixtures

  alias Quorum.Sessions

  # Every keystroke reaches the server through the code field's own change
  # binding, so the tests drive it the way a phone does.
  defp type(view, code), do: view |> element("#code") |> render_change(%{"code" => code})

  test "the screen asks for the code, with a label for the field", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/join")

    assert html =~ "Type the code"
    assert html =~ ~s(for="code")
    assert html =~ ~s(id="code")
  end

  test "a code in the query string prefills the field, upcased", %{conn: conn} do
    room = room()
    {:ok, _view, html} = live(conn, ~p"/join?code=#{String.downcase(room.join_code)}")

    assert html =~ ~s(value="#{room.join_code}")
  end

  test "the caret marks the slot the next character goes in", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/join")

    # Nothing typed: the caret is on the first slot.
    assert has_element?(view, "#slot-0.q-slot--caret")

    type(view, "K7")

    assert has_element?(view, "#slot-2.q-slot--caret")
    refute has_element?(view, "#slot-0.q-slot--caret")
  end

  test "the way in stays shut until five characters name a room", %{conn: conn} do
    room = room("Physics 201")
    {:ok, view, html} = live(conn, ~p"/join")

    assert html =~ "disabled"
    refute html =~ "Physics 201"

    html = type(view, String.slice(room.join_code, 0, 4))
    assert html =~ "disabled"

    html = type(view, room.join_code)
    assert html =~ "Join Physics 201"
    refute html =~ "disabled"
  end

  test "a resolved room counts what's already happening in it", %{conn: conn} do
    room = room()
    question(room, "Why does the phase velocity exceed c?")
    question(room, "Is the group velocity the one that carries energy?")

    {:ok, view, _html} = live(conn, ~p"/join")

    assert type(view, room.join_code) =~ "In session"
    assert render(view) =~ "2 questions"
  end

  test "a question posted while the code stands there updates the count", %{conn: conn} do
    room = room()
    {:ok, view, _html} = live(conn, ~p"/join")

    assert type(view, room.join_code) =~ "0 questions"

    question(room, "Does this reach the join page?")

    assert render(view) =~ "1 question"
  end

  test "an unknown code names the code it rejected", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/join")

    html = type(view, "zzzzz")

    assert html =~ "No session uses the code ZZZZZ."
    assert html =~ "disabled"
  end

  test "a closed room says so, and offers what was asked rather than a way in", %{conn: conn} do
    room = room()
    question(room, "Was this answered?")
    Sessions.close_room(room)

    {:ok, view, _html} = live(conn, ~p"/join")
    html = type(view, room.join_code)

    assert html =~ "Session closed"
    assert html =~ "Read what was asked"
    refute html =~ "Join Systems Design 201"
  end

  test "the page takes the room's own hall, so the phone matches the wall", %{conn: conn} do
    room = room()
    {:ok, view, html} = live(conn, ~p"/join")

    # Nothing resolved yet, so the screen starts on the dark hall.
    assert html =~ "q-join--dark"

    Sessions.update_settings(room, %{projection_dark?: false})
    html = type(view, room.join_code)

    refute html =~ "q-join--dark"
    assert html =~ "background-image:linear-gradient(60deg, #E9E9E9, #FAFAFA)"
  end

  test "a display name is offered only where the room allows one", %{conn: conn} do
    room = room()
    {:ok, view, _html} = live(conn, ~p"/join")

    assert type(view, room.join_code) =~ "Add a display name"

    Sessions.update_settings(room, %{allow_display_name?: false})
    {:ok, view, _html} = live(conn, ~p"/join")

    refute type(view, room.join_code) =~ "Add a display name"
  end

  test "the name field opens on the link and the badge reads it back", %{conn: conn} do
    room = room()
    {:ok, view, _html} = live(conn, ~p"/join")
    type(view, room.join_code)

    html = view |> element("button", "Add a display name") |> render_click()
    assert html =~ ~s(id="name")

    html = view |> element("#name") |> render_change(%{"name" => "Ada"})
    assert html =~ ~s(<span class="q-join-badge">Ada</span>)

    # Going back to anonymous drops the name rather than keeping it out of sight.
    html = view |> element("button", "Stay anonymous") |> render_click()
    refute html =~ "Ada"
  end
end
