defmodule Quorum.AI do
  @moduledoc """
  The one door to the AI sidecar.

  Quorum holds no provider keys and speaks to no provider. A Python sidecar
  next door holds the keys and drives every provider through KeyCall; this
  module makes one normalized call to it, records what the call spent, and
  says plainly when the sidecar isn't there. Every feature behind a model
  checks `enabled?/0` and stays out of the way when it's off.
  """
  use Ash.Domain, otp_app: :quorum

  resources do
    resource(Quorum.AI.Call)
  end

  @doc """
  Whether the sidecar can be reached at all: a base URL is configured and the
  shared token is set. Features gate on this rather than erroring one by one.
  """
  def enabled? do
    case Application.get_env(:quorum, :ai_enabled) do
      nil -> config()[:base_url] != nil and token() != nil
      value -> value
    end
  end

  @doc """
  One model call through the sidecar, recorded whatever happens.

  `purpose` is `:pointer`, `:draft`, or `:screen`. Options: `:system`,
  `:schema`, `:max_output_tokens`, `:target`, and `:room` (the room the spend
  belongs to, for the record). Returns `{:ok, text}` or `{:error, reason}`.
  """
  def generate(purpose, prompt, opts \\ []) do
    request = %{
      prompt: prompt,
      system: opts[:system],
      schema: opts[:schema],
      target: opts[:target],
      max_output_tokens: opts[:max_output_tokens] || 400
    }

    case client().generate(request, config()) do
      {:ok, reply} ->
        record(purpose, opts[:room], reply, true, nil)
        {:ok, reply["text"]}

      {:error, reason} ->
        record(purpose, opts[:room], %{}, false, inspect(reason))
        {:error, reason}
    end
  end

  @doc "generate/3, with the reply parsed as JSON. For calls made with a schema."
  def generate_json(purpose, prompt, opts \\ []) do
    with {:ok, text} <- generate(purpose, prompt, opts),
         {:ok, parsed} <- Jason.decode(to_string(text)) do
      {:ok, parsed}
    else
      {:error, %Jason.DecodeError{}} -> {:error, :bad_json}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Every recorded call for a presenter, newest first."
  def calls(owner_id) do
    require Ash.Query

    Quorum.AI.Call
    |> Ash.Query.filter(owner_id == ^owner_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!()
  end

  defp record(purpose, room, reply, ok?, error) do
    attrs = %{
      purpose: purpose,
      room_id: room && room.id,
      owner_id: room && room.owner_id,
      provider: reply["provider"],
      model: reply["model"],
      input_tokens: reply["input_tokens"],
      output_tokens: reply["output_tokens"],
      elapsed_ms: round_ms(reply["elapsed_ms"]),
      ok?: ok?,
      error: error
    }

    Quorum.AI.Call
    |> Ash.Changeset.for_create(:record, attrs)
    |> Ash.create!()
  end

  defp round_ms(nil), do: nil
  defp round_ms(ms) when is_float(ms), do: round(ms)
  defp round_ms(ms), do: ms

  defp client, do: Application.get_env(:quorum, :ai_client, Quorum.AI.Sidecar)
  defp config, do: Application.get_env(:quorum, Quorum.AI, [])

  @doc false
  def token, do: System.get_env("QUORUM_SIDECAR_TOKEN")
end
