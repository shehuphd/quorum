defmodule Quorum.AIStub do
  @moduledoc """
  The sidecar, as closures. A test sets `:ai_stub` to a function taking the
  generate request, and `:ai_stub_api` to a map of the management calls it
  wants answered; everything unset answers as a sidecar that's down. Flip
  `:ai_enabled` to bring the gated features to life without a Python process
  anywhere near the suite.
  """
  @behaviour Quorum.AI.Client

  @impl true
  def generate(request, _config) do
    case Application.get_env(:quorum, :ai_stub) do
      nil -> {:error, :no_stub}
      fun -> fun.(request)
    end
  end

  @impl true
  def targets(_config), do: api(:targets, [])

  @impl true
  def providers(_config), do: api(:providers, [])

  @impl true
  def put_target(params, _config), do: api(:put_target, [params])

  @impl true
  def put_model(name, model, _config), do: api(:put_model, [name, model])

  @impl true
  def delete_target(name, _config), do: api(:delete_target, [name])

  defp api(name, args) do
    case Application.get_env(:quorum, :ai_stub_api, %{})[name] do
      nil -> {:error, {:unreachable, :no_stub}}
      fun -> apply(fun, args)
    end
  end
end
