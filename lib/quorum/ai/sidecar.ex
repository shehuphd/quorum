defmodule Quorum.AI.Sidecar do
  @moduledoc """
  The HTTP client for the sidecar: one POST to /generate on localhost, the
  shared token in a header, a short timeout, and every failure mapped to a
  plain reason the caller can act on. Features fail closed: a sidecar that
  isn't answering means the feature doesn't run, never a crashed job
  loop.
  """
  @behaviour Quorum.AI.Client

  @impl true
  def generate(request, config) do
    base = config[:base_url] || "http://127.0.0.1:4747"

    body =
      request
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    case Req.post("#{base}/generate",
           json: body,
           headers: [{"x-quorum-token", Quorum.AI.token() || ""}],
           receive_timeout: config[:timeout] || 30_000,
           retry: false
         ) do
      {:ok, %{status: 200, body: %{"text" => _} = reply} = _response} -> {:ok, reply}
      {:ok, %{status: 200}} -> {:error, :empty_reply}
      {:ok, %{status: status, body: body}} -> {:error, {:sidecar, status, describe(body)}}
      {:error, %{reason: reason}} -> {:error, {:unreachable, reason}}
      {:error, other} -> {:error, {:unreachable, other}}
    end
  end

  defp describe(%{"message" => message}), do: message
  defp describe(%{"error" => error}), do: error
  defp describe(other), do: inspect(other)
end
