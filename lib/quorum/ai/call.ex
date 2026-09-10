defmodule Quorum.AI.Call do
  @moduledoc """
  One model call, as a record: what asked for it, which provider and model
  answered, the tokens it spent, and how long it took. Written for every call,
  successful or not, so nothing the app spends is ever untracked.

  `cost` stays empty until a rates table prices it; the tokens are the durable
  fact, and prices change under them.
  """
  use Ash.Resource,
    otp_app: :quorum,
    domain: Quorum.AI,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "ai_calls"
    repo Quorum.Repo
  end

  actions do
    defaults([:read, :destroy])
    default_accept([])

    create :record do
      accept([
        :purpose,
        :room_id,
        :owner_id,
        :provider,
        :model,
        :input_tokens,
        :output_tokens,
        :elapsed_ms,
        :ok?,
        :error
      ])
    end
  end

  attributes do
    uuid_primary_key(:id)

    # What the call was for: the reading pointer, the presenter's draft, or
    # the injection screen.
    attribute :purpose, :atom do
      allow_nil?(false)
      public?(true)
      constraints(one_of: [:pointer, :draft, :screen])
    end

    # Kept as plain ids rather than foreign keys, so the record of what was
    # spent survives the room it was spent on.
    attribute :room_id, :uuid do
      public?(true)
    end

    attribute :owner_id, :uuid do
      public?(true)
    end

    attribute :provider, :string do
      public?(true)
    end

    attribute :model, :string do
      public?(true)
    end

    attribute :input_tokens, :integer do
      public?(true)
    end

    attribute :output_tokens, :integer do
      public?(true)
    end

    attribute :elapsed_ms, :integer do
      public?(true)
    end

    attribute :cost, :decimal do
      public?(true)
    end

    attribute :ok?, :boolean do
      allow_nil?(false)
      public?(true)
      default(true)
    end

    attribute :error, :string do
      public?(true)
    end

    create_timestamp(:inserted_at)
  end
end
