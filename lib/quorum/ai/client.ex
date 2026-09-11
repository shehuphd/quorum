defmodule Quorum.AI.Client do
  @moduledoc "What a sidecar client answers. Tests swap in a stub through config."

  @callback generate(request :: map(), config :: keyword()) :: {:ok, map()} | {:error, term()}
  @callback targets(config :: keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback providers(config :: keyword()) :: {:ok, [String.t()]} | {:error, term()}
  @callback put_target(params :: map(), config :: keyword()) :: {:ok, map()} | {:error, term()}
  @callback put_model(name :: String.t(), model :: String.t() | nil, config :: keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback put_default(name :: String.t(), config :: keyword()) :: :ok | {:error, term()}
  @callback delete_target(name :: String.t(), config :: keyword()) :: :ok | {:error, term()}
end
