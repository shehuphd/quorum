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

  require Ash.Query
  require Logger

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

  # A day of model use. The keys behind the sidecar are live and the demo
  # is open to anyone with the link, so this is the ceiling that stops a room
  # full of questions, or someone poking at it, from drawing an account down.
  #
  # Two ceilings, because either alone has a hole: the ledger can't price a model
  # it doesn't know yet, and an unpriced call would otherwise cost nothing
  # against a dollar limit, so a count guards it too. Both roll over 24 hours
  # rather than resetting on a calendar day, so they recover without anything
  # having to run.
  @default_daily_budget "2.00"
  @default_daily_calls 1000

  @doc "The most the AI may spend in a rolling day, in dollars."
  def daily_budget do
    :quorum
    |> Application.get_env(:ai_daily_budget, @default_daily_budget)
    |> to_string()
    |> Decimal.new()
  end

  @doc "The most calls the AI may make in a rolling day, priced or not."
  def daily_call_limit do
    :quorum
    |> Application.get_env(:ai_daily_calls, @default_daily_calls)
    |> to_string()
    |> String.to_integer()
  end

  @doc "What the AI has spent in the last 24 hours. Unpriced calls count as nothing."
  def spent_today(now \\ DateTime.utc_now()), do: now |> day() |> elem(0)

  @doc "How many calls the AI has made in the last 24 hours, priced or not."
  def calls_today(now \\ DateTime.utc_now()), do: now |> day() |> elem(1)

  @doc "Whether either ceiling still has room for another call today."
  def within_budget?(now \\ DateTime.utc_now()) do
    {spent, count} = day(now)
    Decimal.lt?(spent, daily_budget()) and count < daily_call_limit()
  end

  defp day(now) do
    since = DateTime.add(now, -24, :hour)

    calls =
      Quorum.AI.Call
      |> Ash.Query.filter(inserted_at >= ^since)
      |> Ash.read!()

    spent =
      calls
      |> Enum.map(& &1.cost)
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    {spent, length(calls)}
  end

  @doc """
  One model call through the sidecar, recorded whatever happens.

  `purpose` is `:pointer`, `:draft`, or `:screen`. Options: `:system`,
  `:schema`, `:max_output_tokens`, `:target`, and `:room` (the room the spend
  belongs to, for the record). Returns `{:ok, text}` or `{:error, reason}`.
  """
  def generate(purpose, prompt, opts \\ []) do
    if within_budget?() do
      call(purpose, prompt, opts)
    else
      Logger.warning(
        "AI call refused: the last 24 hours already used " <>
          "$#{spent_today()} of $#{daily_budget()} or " <>
          "#{calls_today()} of #{daily_call_limit()} calls"
      )

      {:error, :over_budget}
    end
  end

  defp call(purpose, prompt, opts) do
    request = %{
      prompt: prompt,
      system: opts[:system],
      schema: opts[:schema],
      target: opts[:target],
      max_output_tokens: opts[:max_output_tokens] || 8192
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

  ## Keys and models, through the sidecar

  @doc "The configured targets: provider, name, a key hint, and usable models. Never a key."
  def targets, do: client().targets(config())

  @doc "The providers a key can be for, from KeyCall's own catalog."
  def providers, do: client().providers(config())

  @doc """
  Add or replace a key. The sidecar proves it live against the provider before
  storing it, so nothing invalid is ever saved; the key passes through this
  process once and is never stored, logged, or echoed here.
  """
  def add_key(params), do: client().put_target(params, config())

  @doc "Pin a target to one model, or nil to go back to automatic."
  def pin_model(name, model), do: client().put_model(name, model, config())

  @doc """
  Make a target the default: tried first for every call, with the other keys
  as its fallbacks when it can't answer.
  """
  def set_default(name), do: client().put_default(name, config())

  @doc "Remove a key. The next feature call finds it gone."
  def remove_key(name), do: client().delete_target(name, config())

  @doc """
  The passcode that guards removing a protected house key, from the environment.
  `nil` when unset, which reads as locked: a protected key can't be removed
  until the deployment sets one.
  """
  def key_guard, do: System.get_env("QUORUM_KEY_GUARD")

  ## The spend

  @doc """
  What the AI has spent so far: calls, tokens, and dollars, in total and per
  purpose. Dollars cover only the calls the rates ledger could price, so
  `priced` says how many of the calls the figure spans.
  """
  def spend do
    calls = Ash.read!(Quorum.AI.Call)
    priced = Enum.reject(calls, &is_nil(&1.cost))

    %{
      calls: length(calls),
      input: calls |> Enum.map(&(&1.input_tokens || 0)) |> Enum.sum(),
      output: calls |> Enum.map(&(&1.output_tokens || 0)) |> Enum.sum(),
      cost: priced |> Enum.map(& &1.cost) |> Enum.reduce(Decimal.new(0), &Decimal.add/2),
      priced: length(priced),
      by_purpose: Enum.frequencies_by(calls, & &1.purpose)
    }
  end

  @doc "Zero the counter. The rows go; the tokens were already spent."
  def clear_spend do
    Quorum.AI.Call |> Ash.read!() |> Enum.each(&Ash.destroy!/1)
    :ok
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
      cost: reply["cost"],
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
