defmodule QuorumWeb.ArchiveController do
  @moduledoc """
  The term's questions as a file. A presenter planning the next term works in a
  spreadsheet as often as on a screen, so the archive hands over what it holds.
  """
  use QuorumWeb, :controller

  alias Quorum.Sessions

  @columns ~w(Session Date Question Votes Status Asker)

  def export(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        redirect(conn, to: ~p"/sign-in")

      user ->
        csv = user.id |> Sessions.archive() |> rows() |> to_csv()

        conn
        |> put_resp_content_type("text/csv")
        |> send_download({:binary, csv}, filename: "quorum-questions.csv")
    end
  end

  defp rows(sessions) do
    Enum.flat_map(sessions, fn room ->
      Enum.map(room.questions, fn question ->
        [
          room.name,
          Calendar.strftime(question.inserted_at, "%Y-%m-%d"),
          question.body,
          question.vote_count,
          question.status,
          question.display_name || "Anonymous"
        ]
      end)
    end)
  end

  defp to_csv(rows), do: Enum.map_join([@columns | rows], "\r\n", &line/1) <> "\r\n"

  defp line(row), do: Enum.map_join(row, ",", &field/1)

  # Every field is quoted, so a comma, a quote, or a line break inside a question
  # can't break the column it's in.
  defp field(value) do
    escaped = value |> to_string() |> String.replace("\"", "\"\"")
    "\"" <> escaped <> "\""
  end
end
