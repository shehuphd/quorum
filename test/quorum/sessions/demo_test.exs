defmodule Quorum.Sessions.DemoTest do
  @moduledoc """
  The demo room carries a fixed, printable code, and that code always resolves:
  the landing page can show it and a visitor who types it lands in the demo.
  """
  use Quorum.DataCase, async: false

  alias Quorum.Sessions.Demo

  test "a seeded demo room carries the fixed code" do
    {:ok, room} = Demo.seed()
    assert room.join_code == Demo.code()
  end

  test "the fixed code resolves, seeding the demo room when none is open" do
    assert Demo.current() == nil

    {:ok, room} = Demo.room_for_code(Demo.code())

    assert room.join_code == Demo.code()
    assert Demo.current().id == room.id
  end

  test "the fixed code is matched whatever the casing" do
    {:ok, room} = Demo.room_for_code(String.downcase(Demo.code()))
    assert room.join_code == Demo.code()
  end

  test "a code that isn't the demo's and names no room is not found" do
    assert Demo.room_for_code("ZZZZZ") == {:error, :not_found}
    assert Demo.current() == nil
  end

  test "reseeding after a clear takes the fixed code again rather than colliding" do
    {:ok, first} = Demo.seed()
    Demo.clear()

    {:ok, second} = Demo.room_for_code(Demo.code())

    assert second.id != first.id
    assert second.join_code == Demo.code()
  end
end
