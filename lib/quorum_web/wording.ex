defmodule QuorumWeb.Wording do
  @moduledoc """
  Small view helpers shared across the screens: the phrasing several of them
  render the same way, and the two projection builders (the QR code and the
  hall gradient) the console and the front screen both draw. One definition
  each, imported where a screen needs it.
  """
  use QuorumWeb, :verified_routes

  @doc "Pluralize the word vote by count."
  def votes(1), do: "vote"
  def votes(_), do: "votes"

  @doc "The wall-clock time, for a timestamp shown in the room."
  def clock(dt), do: Calendar.strftime(dt, "%H:%M")

  @doc "A count with its noun, pluralized: one question, two questions."
  def counted(1, word), do: "1 #{word}"
  def counted(n, word), do: "#{n} #{word}s"

  @doc "A display name, or \"Anonymous\" when there isn't one."
  def name_or_anon(name) when is_binary(name) and name != "", do: name
  def name_or_anon(_), do: "Anonymous"

  @doc """
  Who asked, as a line: "Asked by <name>", or `anonymous` when the question
  carries no name (the front screen says "Asked anonymously", the console
  "Anonymous").
  """
  def asked_by(question, anonymous \\ "Anonymous")

  def asked_by(%{display_name: name}, _anonymous) when is_binary(name) and name != "",
    do: "Asked by #{name}"

  def asked_by(_question, anonymous), do: anonymous

  @doc """
  The hall's gradient, from a room's Appearance settings. `nil` for no room
  yet; otherwise the lit or dark pair by `dark?`.
  """
  def hall(nil, _dark?), do: nil

  def hall(room, dark?) do
    {from, to} =
      if dark?,
        do: {room.projection_dark_from, room.projection_dark_to},
        else: {room.projection_light_from, room.projection_light_to}

    # The longhand, not the `background` shorthand: the shorthand resets
    # background-size, and the drift animates a position across 150% of it.
    "background-image:linear-gradient(#{room.projection_angle}deg, #{from}, #{to});"
  end

  @doc "A room's join QR as an inline SVG at the given width."
  def qr_svg(code, width) do
    ~p"/r/#{code}" |> url() |> EQRCode.encode() |> EQRCode.svg(width: width)
  end
end
