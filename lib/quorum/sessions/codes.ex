defmodule Quorum.Sessions.Codes do
  @moduledoc """
  Generators for a room's public join code and for the opaque tokens that grant
  host access. Student ownership and vote tokens are supplied by the browser, not
  generated here.
  """

  # Uppercase letters and digits with the ambiguous glyphs (I, O, 0, 1) removed,
  # so a code read off a projector or spoken aloud is hard to mistype.
  @join_alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @join_length 5

  @doc """
  A short, human-typable room code, e.g. "K7QM4". Uniqueness is enforced by the
  Room's identity, not by this generator.
  """
  def join_code do
    for _ <- 1..@join_length, into: "", do: <<Enum.random(@join_alphabet)>>
  end

  @doc "An opaque, unguessable token for host access."
  def token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
