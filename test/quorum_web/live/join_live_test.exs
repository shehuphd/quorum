defmodule QuorumWeb.JoinLiveTest do
  use QuorumWeb.ConnCase

  import Phoenix.LiveViewTest
  import Quorum.Fixtures

  test "shows the code field with a visible label", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/join")

    assert html =~ "Join the lecture"
    assert html =~ ~s(for="code")
    assert html =~ ~s(id="code")
  end

  test "a code in the query string prefills the field, upcased", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/join?code=k7qm4")

    assert html =~ ~s(value="K7QM4")
  end

  test "an unknown code names the code it rejected", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/join")

    html = view |> form("form", %{"code" => "ZZZZZ"}) |> render_submit()

    assert html =~ "No lecture uses the code ZZZZZ."
  end

  test "a known code navigates to that room, however it was typed", %{conn: conn} do
    room = room()
    {:ok, view, _html} = live(conn, ~p"/join")

    assert {:error, {:live_redirect, %{to: to}}} =
             view |> form("form", %{"code" => String.downcase(room.join_code)}) |> render_submit()

    assert to == "/r/#{room.join_code}"
  end
end
