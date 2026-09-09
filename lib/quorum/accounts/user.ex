defmodule Quorum.Accounts.User do
  @moduledoc """
  A lecturer. Students never have one: they join a room by code and stay
  anonymous, so an account exists only to own rooms and reading lists.
  """
  use Ash.Resource,
    otp_app: :quorum,
    domain: Quorum.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "users"
    repo Quorum.Repo
  end

  actions do
    defaults([:read])
    default_accept([])

    create :register do
      description("Create a lecturer from the email they asked for a link with.")
      accept([:email])
      upsert?(true)
      upsert_identity(:unique_email)
    end

    update :set_name do
      accept([:name])
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :email, :string do
      allow_nil?(false)
      public?(true)
      constraints(max_length: 254, min_length: 3, match: ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/)
    end

    attribute :name, :string do
      public?(true)
      constraints(max_length: 120)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    has_many :rooms, Quorum.Sessions.Room, destination_attribute: :owner_id
  end

  identities do
    identity(:unique_email, [:email])
  end
end
