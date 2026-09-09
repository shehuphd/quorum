defmodule QuorumWeb.PageHTML do
  @moduledoc """
  The landing page and its helpers.
  """
  use QuorumWeb, :html

  embed_templates "page_html/*"

  @words ~w(no one two three four five six seven eight nine ten eleven twelve)

  @doc """
  Small counts read as words in a sentence, larger ones as digits.
  """
  def word(n) when n >= 0 and n < 13, do: Enum.at(@words, n)
  def word(n), do: Integer.to_string(n)

  @doc "The same count with its noun, pluralised."
  def count(n, singular, plural), do: "#{word(n)} #{if n == 1, do: singular, else: plural}"

  @doc "The message for one field, or nil."
  def error(errors, field), do: Keyword.get(errors, field)

  @doc "The id a field points `aria-describedby` at while it carries an error."
  def error_id(errors, field), do: if(error(errors, field), do: "#{field}-error")

  @doc "A QR code for a room's join URL, as inline SVG."
  def qr(code, width) do
    ~p"/r/#{code}" |> url() |> EQRCode.encode() |> EQRCode.svg(width: width)
  end
end
