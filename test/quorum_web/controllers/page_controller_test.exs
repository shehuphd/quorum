defmodule QuorumWeb.PageControllerTest do
  use QuorumWeb.ConnCase

  alias Quorum.Sessions.Demo

  test "the hero carries both entry points, a labelled code field and Start a room", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Take live questions from the room."
    assert html =~ ~s(for="code")
    assert html =~ ~s(id="code")
    assert html =~ "Join a session"
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
    assert html =~ "See a demo session"
  end

  test "the demo band offers all three roles", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Join as a student"
    assert html =~ "Join as a presenter"
    assert html =~ "Open the projection"
    assert html =~ ~s(href="/demo")
    assert html =~ ~s(href="/demo/host")
    assert html =~ ~s(href="/demo/project")
  end

  test "with no demo room the page shows the standard demo code and seeds nothing", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Demo room, code #{Demo.code()}"
    assert Demo.current() == nil
  end

  test "with a demo room the band reports that room's code and counts", %{conn: conn} do
    {:ok, room} = Demo.ensure_room()

    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Demo room, code #{room.join_code}"
    assert html =~ "Nine questions posted, one answered."
    refute html =~ "K7QM4"
  end

  test "the feed card renders one example and ships the rest for rotation", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(id="q-example")
    assert html =~ "data-examples="
    assert html =~ ~s(data-example="votes")
    assert html =~ ~s(data-example="body")
    assert html =~ ~s(data-example="meta")

    # The rendered one comes from the same list the client cycles through.
    bodies = Enum.map(QuorumWeb.LandingExamples.all(), & &1.body)

    assert Enum.any?(
             bodies,
             &(html =~ Phoenix.HTML.html_escape(&1) |> Phoenix.HTML.safe_to_string())
           )
  end

  test "the footer keeps the same side margins as the rest of the page", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    # Sharing q-l-shell is what keeps the footer's edges lined up with the bands.
    assert html =~ ~s(class="q-l-shell q-l-footer")
  end
end
