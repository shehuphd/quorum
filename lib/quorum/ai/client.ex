defmodule Quorum.AI.Client do
  @moduledoc "What a sidecar client answers. Tests swap in a stub through config."
  @callback generate(request :: map(), config :: keyword()) ::
              {:ok, map()} | {:error, term()}
end
