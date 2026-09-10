defmodule QuorumWeb.JoinTest do
  use QuorumWeb.ConnCase

  import Phoenix.LiveViewTest
  import Quorum.Fixtures

  test "the way in from the join page carries a display name into the feed", %{conn: conn} do
    room = room()

    conn = post(conn, ~p"/join", %{"code" => room.join_code, "name" => "Ada"})
    assert redirected_to(conn) == "/r/#{room.join_code}"

    {:ok, _view, html} = live(conn, ~p"/r/#{room.join_code}")

    # The composer opens with the name already in it, rather than asking again.
    assert html =~ ~s(value="Ada")
    assert html =~ "Shown on the questions you post."
  end

  test "the name reaches the question, not just the field", %{conn: conn} do
    room = room()

    conn = post(conn, ~p"/join", %{"code" => room.join_code, "name" => "Ada"})
    {:ok, view, _html} = live(conn, ~p"/r/#{room.join_code}")

    view |> form("#ask-form", %{"body" => "Does the name follow me in?"}) |> render_submit()
    view |> element("button", "Send it now") |> render_click()

    assert render(view) =~ "Ada"
  end

  test "joining without a name leaves the student anonymous", %{conn: conn} do
    room = room()

    conn = post(conn, ~p"/join", %{"code" => room.join_code, "name" => ""})
    {:ok, _view, html} = live(conn, ~p"/r/#{room.join_code}")

    assert html =~ "Add your name"
  end

  test "a code lowercase or unknown still lands somewhere sensible", %{conn: conn} do
    room = room()

    assert conn
           |> post(~p"/join", %{"code" => String.downcase(room.join_code)})
           |> redirected_to() == "/r/#{room.join_code}"

    assert conn |> post(~p"/join", %{"code" => "ZZZZZ"}) |> redirected_to() == "/join?code=ZZZZZ"
  end
end
