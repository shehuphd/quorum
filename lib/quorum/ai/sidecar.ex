defmodule Quorum.AI.Sidecar do
  @moduledoc """
  The HTTP client for the sidecar: localhost, the shared token in a header,
  short timeouts, and every failure mapped to a plain reason the caller can
  act on. Features fail closed: a sidecar that isn't answering means the
  feature doesn't run, never a crashed job loop. A key passes through here
  once, on its way in, and is never stored, logged, or echoed by Quorum.
  """
  @behaviour Quorum.AI.Client

  @impl true
  def generate(request, config) do
    body =
      request
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    case post("/generate", body, config, config[:timeout] || 30_000) do
      {:ok, %{"text" => _} = reply} -> {:ok, reply}
      {:ok, _} -> {:error, :empty_reply}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def targets(config) do
    with {:ok, %{"targets" => targets}} <- get("/targets", config), do: {:ok, targets}
  end

  @impl true
  def providers(config) do
    with {:ok, %{"providers" => providers}} <- get("/providers", config), do: {:ok, providers}
  end

  @impl true
  def put_target(params, config), do: post("/targets", params, config, 20_000)

  @impl true
  def put_model(name, model, config),
    do: post("/targets/#{name}/model", %{model: model || ""}, config, 20_000)

  @impl true
  def delete_target(name, config) do
    case request(:delete, "/targets/#{name}", nil, config, 10_000) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp get(path, config), do: request(:get, path, nil, config, 10_000)
  defp post(path, body, config, timeout), do: request(:post, path, body, config, timeout)

  defp request(method, path, body, config, timeout) do
    base = config[:base_url] || "http://127.0.0.1:4747"

    options = [
      method: method,
      url: base <> path,
      headers: [{"x-quorum-token", Quorum.AI.token() || ""}],
      receive_timeout: timeout,
      retry: false
    ]

    options = if body, do: Keyword.put(options, :json, body), else: options

    case Req.request(options) do
      {:ok, %{status: status, body: reply}} when status in 200..299 -> {:ok, reply}
      {:ok, %{status: status, body: reply}} -> {:error, {:sidecar, status, describe(reply)}}
      {:error, %{reason: reason}} -> {:error, {:unreachable, reason}}
      {:error, other} -> {:error, {:unreachable, other}}
    end
  end

  defp describe(%{"message" => message}), do: message
  defp describe(%{"error" => error}), do: error
  defp describe(other), do: inspect(other)
end
