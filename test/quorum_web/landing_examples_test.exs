defmodule QuorumWeb.LandingExamplesTest do
  use ExUnit.Case, async: true

  alias QuorumWeb.LandingExamples

  test "there are twenty examples, split between named and anonymous askers" do
    all = LandingExamples.all()

    assert length(all) == 20
    named = Enum.count(all, & &1.name)
    assert named > 0
    assert named < 20
  end

  test "every example carries a body and a plausible vote count" do
    for example <- LandingExamples.all() do
      assert is_binary(example.body) and String.length(example.body) > 20
      assert example.votes > 0
    end
  end

  test "an age reads the way the feed phrases it, across the whole range" do
    assert LandingExamples.ago(30) == "30 seconds ago"
    assert LandingExamples.ago(59) == "59 seconds ago"
    assert LandingExamples.ago(60) == "1 minute ago"
    assert LandingExamples.ago(119) == "1 minute ago"
    assert LandingExamples.ago(120) == "2 minutes ago"
    assert LandingExamples.ago(900) == "15 minutes ago"
  end

  test "a random age stays inside 30 seconds to 15 minutes" do
    for _ <- 1..200 do
      assert LandingExamples.random_age() =~ ~r/^(\d+ seconds|1 minute|\d+ minutes) ago$/
    end
  end

  test "an asker with no name reads as Anonymous" do
    assert LandingExamples.asker(nil) == "Anonymous"
    assert LandingExamples.asker("Amara O.") == "Amara O."
  end
end
