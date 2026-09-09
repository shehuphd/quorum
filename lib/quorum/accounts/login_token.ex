defmodule Quorum.Accounts.LoginToken do
  @moduledoc """
  One single-use sign-in link. The token is the whole credential, so it is long,
  random, expires after fifteen minutes, and is spent the first time it's
  claimed. A spent or expired token is kept rather than deleted, so a second
  click can be told apart from a token that never existed.
  """
  use Ash.Resource,
    otp_app: :quorum,
    domain: Quorum.Accounts,
    data_layer: AshPostgres.DataLayer

  alias Quorum.Sessions.Codes

  @ttl_minutes 15

  postgres do
    table "login_tokens"
    repo Quorum.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults([:read, :destroy])
    default_accept([])

    create :issue do
      accept([:user_id])
      change(set_attribute(:expires_at, &__MODULE__.expires_at/0))
    end

    update :spend do
      description("Mark the link used, so a second click can't sign anyone in.")
      accept([])
      change(set_attribute(:used_at, &DateTime.utc_now/0))
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :token, :string do
      allow_nil?(false)
      default(&Codes.token/0)
      constraints(max_length: 64)
    end

    attribute :expires_at, :utc_datetime do
      allow_nil?(false)
    end

    attribute :used_at, :utc_datetime do
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :user, Quorum.Accounts.User do
      allow_nil?(false)
      attribute_writable?(true)
    end
  end

  identities do
    identity(:unique_token, [:token])
  end

  def ttl_minutes, do: @ttl_minutes

  @doc "When a link issued right now stops working."
  def expires_at,
    do:
      DateTime.utc_now() |> DateTime.add(@ttl_minutes * 60, :second) |> DateTime.truncate(:second)
end
