defmodule Quorum.AIStub do
  @moduledoc """
  The sidecar, as a closure. A test sets `:ai_stub` to a function taking the
  request and answering what the sidecar would, and `:ai_enabled` to bring the
  features that gate on it to life without a Python process anywhere near the
  suite.
  """
  @behaviour Quorum.AI.Client

  @impl true
  def generate(request, _config) do
    case Application.get_env(:quorum, :ai_stub) do
      nil -> {:error, :no_stub}
      fun -> fun.(request)
    end
  end
end
