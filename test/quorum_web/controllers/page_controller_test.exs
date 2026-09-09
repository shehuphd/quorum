defmodule QuorumWeb.PageControllerTest do
  use QuorumWeb.ConnCase

  alias Quorum.Sessions.Demo

  test "the hero carries both entry points, a labelled code field and Start a room", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Take live questions during lectures."
    assert html =~ ~s(for="code")
    assert html =~ ~s(id="code")
    assert html =~ "Join a lecture"
    assert html =~ "Start a room"
    assert html =~ "No account. You remain anonymous unless you choose otherwise."
  end

  test "the page carries every section from the design", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "How it works"
    assert html =~ "Project the code"
    assert html =~ "Students ask and vote"
    assert html =~ "Answer the top ones"
    assert html =~ "Add reading suggestions for offline learning"
    assert html =~ "While you wait, from your course reading list"
    assert html =~ "In the hall"
    assert html =~ "Setup"
    assert html =~ "See a demo lecture"
  end

  test "the demo band offers all three roles", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Join as a student"
    assert html =~ "Join as a lecturer"
    assert html =~ "Open the projection"
    assert html =~ ~s(href="/demo")
    assert html =~ ~s(href="/demo/host")
    assert html =~ ~s(href="/demo/project")
  end

  test "with no demo room the page shows the sample code and seeds nothing", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Demo room, code K7QM4"
    assert Demo.current() == nil
  end

  test "with a demo room the band reports that room's code and counts", %{conn: conn} do
    {:ok, room} = Demo.ensure_room()

    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Demo room, code #{room.join_code}"
    assert html =~ "Nine questions posted, one answered."
    refute html =~ "K7QM4"
  end
end
