defmodule QuorumWeb.DemoControllerTest do
  use QuorumWeb.ConnCase

  alias Quorum.Sessions
  alias Quorum.Sessions.Demo

  test "the student door seeds a session on first use and opens its feed", %{conn: conn} do
    assert Demo.current() == nil

    conn = get(conn, ~p"/demo")
    room = Demo.current()

    assert room
    assert redirected_to(conn) == "/r/#{room.join_code}"
  end

  test "a seeded session has the questions and the one answer the band promises", %{conn: conn} do
    get(conn, ~p"/demo")

    %{visible: visible, answered: answered} =
      Demo.current().id |> Sessions.list_questions() |> Sessions.partition()

    assert length(visible) + length(answered) == Demo.question_count()
    assert length(answered) == 1
    assert Enum.any?(visible, &(&1.vote_count == 31))
  end

  test "the three doors reach the same room", %{conn: conn} do
    student = get(conn, ~p"/demo")
    host = get(conn, ~p"/demo/host")
    projection = get(conn, ~p"/demo/project")

    room = Demo.current()

    assert redirected_to(student) == "/r/#{room.join_code}"
    assert redirected_to(host) == "/host/#{room.host_token}"
    assert redirected_to(projection) == "/host/#{room.host_token}/project"
  end

  test "a second visit reuses the open room instead of seeding another", %{conn: conn} do
    get(conn, ~p"/demo")
    first = Demo.current()

    get(conn, ~p"/demo")

    assert Demo.current().id == first.id
    assert length(Sessions.list_questions(first.id)) == Demo.question_count()
  end

  test "clearing the demo makes the next visit seed a fresh room", %{conn: conn} do
    get(conn, ~p"/demo")
    first = Demo.current()

    Demo.clear()
    assert Demo.current() == nil

    get(conn, ~p"/demo")
    assert Demo.current().id != first.id
  end

  test "a demo room is flagged, so a presenter's own room is never mistaken for it", %{conn: conn} do
    {:ok, mine} = Sessions.open_room("My session")
    get(conn, ~p"/demo")

    refute mine.demo?
    assert Demo.current().demo?
    assert Demo.current().id != mine.id
  end
end
