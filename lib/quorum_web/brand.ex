defmodule QuorumWeb.Brand do
  @moduledoc """
  The Quorum lockup, drawn in markup rather than loaded as an image: the vote
  caret beside the wordmark. Built this way so the wordmark uses the page's own
  Archivo (an SVG loaded through `<img>` can't reach a webfont) and so it carries
  no background of its own on the projection's gradient.
  """
  use Phoenix.Component

  attr :on_dark, :boolean, default: false
  attr :size, :integer, default: 26, doc: "wordmark size in px; the caret scales with it"

  def logo(assigns) do
    ~H"""
    <span style={"display:inline-flex;align-items:center;gap:#{round(@size * 0.35)}px;"}>
      <svg
        width={round(@size * 0.72)}
        height={round(@size * 0.62)}
        viewBox="0 0 24 20"
        aria-hidden="true"
        focusable="false"
      >
        <polygon points="12,2 22,18 2,18" fill={if @on_dark, do: "#4FBF9B", else: "#0B6B54"} />
      </svg>
      <span style={"font:700 #{@size}px var(--q-font-sans);letter-spacing:-0.02em;color:#{if @on_dark, do: "var(--q-on-dark)", else: "var(--q-ink)"};"}>
        Quorum
      </span>
    </span>
    """
  end
end
