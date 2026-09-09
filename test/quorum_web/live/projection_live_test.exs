defmodule QuorumWeb.ProjectionLiveTest do
  use QuorumWeb.ConnCase

  import Phoenix.LiveViewTest
  import Quorum.Fixtures

  alias Quorum.Sessions

  test "a host token that matches nothing says so instead of crashing", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/host/not-a-token/project")

    assert html =~ "That host link doesn&#39;t match a room."
  end

  test "with nothing spotlighted the join code owns the screen", %{conn: conn} do
    room = room()

    {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/project")

    assert html =~ "Scan to ask a question"
    assert html =~ room.join_code
    assert html =~ "q-projection--waiting"
    assert html =~ "<svg"
    assert html =~ "No questions yet"
  end

  test "spotlighting swaps the screen for the question and its attribution", %{conn: conn} do
    room = room()

    question =
      question(room, "How does a supervisor decide to restart?", %{display_name: "Amara"})

    votes(question, 3)

    {:ok, view, _html} = live(conn, ~p"/host/#{room.host_token}/project")
    Sessions.spotlight(room, question.id)

    html = render(view)

    assert html =~ "Answering now"
    assert html =~ "How does a supervisor decide to restart?"
    assert html =~ "Asked by Amara, 3 votes"
    refute html =~ "q-projection--waiting"
    assert html =~ room.join_code
  end

  test "an anonymous question reads as anonymous, and one vote is singular", %{conn: conn} do
    room = room()
    question = question(room, "Asked from the back row")
    votes(question, 1)
    Sessions.spotlight(room, question.id)

    {:ok, _view, html} = live(conn, ~p"/host/#{room.host_token}/project")

    assert html =~ "Asked anonymously, 1 vote"
  end

  test "either L or D flips the hall light, and the hint names the other state", %{conn: conn} do
    room = room()

    {:ok, view, html} = live(conn, ~p"/host/#{room.host_token}/project")
    assert html =~ "q-projection--dark"
    assert squish(html) =~ "Press <strong>L</strong> or <strong>D</strong> for a lit hall."

    html = render_keyup(view, "key", %{"key" => "l"})
    refute html =~ "q-projection--dark"
    assert squish(html) =~ "Press <strong>L</strong> or <strong>D</strong> for a dark hall."

    # L again toggles back, rather than being a one-way switch to lit.
    html = render_keyup(view, "key", %{"key" => "l"})
    assert html =~ "q-projection--dark"

    html = render_keyup(view, "key", %{"key" => "d"})
    refute html =~ "q-projection--dark"

    html = render_keyup(view, "key", %{"key" => "D"})
    assert html =~ "q-projection--dark"
  end

  test "the QR card is framed in a lit hall, where white on white has no edge", %{conn: conn} do
    room = room()

    {:ok, view, html} = live(conn, ~p"/host/#{room.host_token}/project")
    refute html =~ "border:1px solid var(--q-ink)"

    assert render_keyup(view, "key", %{"key" => "l"}) =~ "border:1px solid var(--q-ink)"
  end

  test "Q hides the spotlight and is only offered while one is showing", %{conn: conn} do
    room = room()
    question = question(room, "On the screen for now")
    Sessions.spotlight(room, question.id)

    {:ok, view, html} = live(conn, ~p"/host/#{room.host_token}/project")
    assert html =~ "Press <strong>Q</strong> to hide the spotlight."

    render_keyup(view, "key", %{"key" => "q"})
    html = render(view)

    refute html =~ "On the screen for now"
    refute html =~ "Press <strong>Q</strong> to hide the spotlight."
    assert {:ok, %{spotlight_question_id: nil}} = Sessions.get_room(room.id)
  end

  test "the question tally counts up as students ask", %{conn: conn} do
    room = room()
    {:ok, view, html} = live(conn, ~p"/host/#{room.host_token}/project")
    assert html =~ "No questions yet"

    question(room, "First of the lecture")

    assert squish(render(view)) =~ "<strong>1</strong> question asked"

    question(room, "Second of the lecture")

    assert squish(render(view)) =~ "<strong>2</strong> questions asked"
  end

  # Collapse the whitespace HEEx adds around interpolations so copy reads as one line.
  defp squish(html) do
    String.replace(html, ~r/\s+/, " ")
  end
end
