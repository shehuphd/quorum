defmodule Quorum.Fixtures do
  @moduledoc "Small builders so tests read as scenarios rather than setup code."

  alias Quorum.Sessions

  def room(name \\ "Systems Design 201") do
    {:ok, room} = Sessions.open_room(name)
    # A plain room for tests that aren't about moderation. Injection screening is
    # on by default in production, so a test that wants it turns it back on; this
    # keeps the fixture meaning "nothing held" the way most tests assume.
    {:ok, room} = Sessions.update_settings(room, %{hold_injection?: false})
    room
  end

  def question(room, body, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put(:body, body)
      |> Map.put_new(:submitter_token, "seed-" <> Base.url_encode64(:crypto.strong_rand_bytes(8)))

    {:ok, question} = Sessions.ask(room.id, attrs)
    question
  end

  def votes(question, count) do
    for i <- 1..count, do: Sessions.vote(question.id, "voter-#{i}-#{question.id}")
    question
  end
end
