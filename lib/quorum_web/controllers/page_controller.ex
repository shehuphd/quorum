defmodule QuorumWeb.PageController do
  @moduledoc """
  The landing page and the three standing pages behind the footer.

  The landing page reads the demo room without seeding one, so a visit never
  writes; the demo links seed on click instead.
  """
  use QuorumWeb, :controller

  alias Quorum.Contact
  alias Quorum.Contact.Limit
  alias Quorum.Sessions
  alias Quorum.Sessions.Demo
  alias QuorumWeb.LandingExamples

  # Counts for the hero mock before anyone has seeded the demo room. The code is
  # always the demo's fixed one, filled in by demo/0.
  @sample %{posted: 12, answered: 1, connected: 38, live?: false}
  @cooldown_seconds 60
  @cooldown_key "contact_sent_at"

  def home(conn, _params) do
    # The landing tab carries the brand and what the app is, rather than a page
    # name and a suffix, so an empty suffix leaves the title exactly as set.
    render(conn, :home,
      page_title: "Quorum | Live Questions Platform",
      title_suffix: "",
      demo: demo(),
      example: LandingExamples.sample(),
      example_age: LandingExamples.random_age()
    )
  end

  def privacy(conn, _params), do: render(conn, :privacy, page_title: "Privacy")

  def accessibility(conn, _params), do: render(conn, :accessibility, page_title: "Accessibility")

  def contact(conn, _params) do
    render(conn, :contact,
      page_title: "Contact",
      params: %{},
      errors: [],
      sent: false
    )
  end

  def contact_submit(conn, params) do
    cond do
      # A bot filling every field trips the honeypot. Report success so it
      # learns nothing, and send nothing.
      params |> Map.get("website", "") |> String.trim() != "" ->
        render_sent(conn)

      seconds_remaining(conn) > 0 ->
        too_soon(conn, params)

      true ->
        case Limit.check(sender_key(conn)) do
          :ok -> submit(conn, params)
          {:wait, _seconds} -> too_soon(conn, params)
          :busy -> too_busy(conn, params)
        end
    end
  end

  defp too_soon(conn, params) do
    render(conn, :contact,
      page_title: "Contact",
      params: params,
      errors: [message: "You just sent one. Give it a few minutes before sending another."],
      sent: false
    )
  end

  defp too_busy(conn, params) do
    render(conn, :contact,
      page_title: "Contact",
      params: params,
      errors: [
        message:
          "The form has taken all it can for now. Try again in an hour, or email us directly."
      ],
      sent: false
    )
  end

  # Who the wait applies to. Behind the ingress every request arrives from the
  # proxy, so the address to count is the one the proxy recorded: the last entry
  # of the forwarded list, which is what it observed rather than anything the
  # sender put there themselves.
  defp sender_key(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [] ->
        conn.remote_ip |> :inet.ntoa() |> to_string()

      values ->
        values
        |> Enum.join(",")
        |> String.split(",")
        |> List.last()
        |> String.trim()
    end
  end

  defp submit(conn, params) do
    case Contact.validate(params) do
      {:ok, message} ->
        case Contact.deliver(message) do
          {:ok, _} ->
            Limit.record(sender_key(conn))

            conn
            |> put_session(@cooldown_key, System.system_time(:second))
            |> render_sent()

          _ ->
            render(conn, :contact,
              page_title: "Contact",
              params: params,
              errors: [message: "That didn't send. Try again, or email us directly."],
              sent: false
            )
        end

      {:error, errors} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:contact, page_title: "Contact", params: params, errors: errors, sent: false)
    end
  end

  defp render_sent(conn),
    do: render(conn, :contact, page_title: "Contact", params: %{}, errors: [], sent: true)

  defp seconds_remaining(conn) do
    case get_session(conn, @cooldown_key) do
      nil ->
        0

      at ->
        elapsed = System.system_time(:second) - at
        if elapsed >= @cooldown_seconds, do: 0, else: @cooldown_seconds - elapsed
    end
  end

  defp demo do
    case Demo.current() do
      nil ->
        Map.put(@sample, :code, Demo.code())

      room ->
        %{visible: visible, answered: answered} =
          room.id |> Sessions.list_questions() |> Sessions.partition()

        %{
          code: room.join_code,
          posted: length(visible) + length(answered),
          answered: length(answered),
          connected: room.id |> Sessions.topic() |> QuorumWeb.Presence.list() |> map_size(),
          live?: true
        }
    end
  end
end
