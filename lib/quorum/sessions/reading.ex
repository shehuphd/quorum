defmodule Quorum.Sessions.Reading do
  @moduledoc """
  One item on a room's approved reading list.

  This list is the only corpus the reading pointer may draw on, so it's the
  presenter's own material rather than anything the model finds.
  """
  use Ash.Resource,
    otp_app: :quorum,
    domain: Quorum.Sessions,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Quorum.Sessions.Broadcaster]

  postgres do
    table "readings"
    repo Quorum.Repo

    references do
      reference :room, on_delete: :delete
    end
  end

  actions do
    defaults([:read, :destroy])
    default_accept([])

    create :add do
      description("Put a reading on a room's approved list.")
      accept([:room_id, :title, :detail, :url])
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
      constraints(max_length: 200, min_length: 1)
    end

    # Where in the reading, for example "pp. 435 to 441".
    attribute :detail, :string do
      public?(true)
      constraints(max_length: 120)
    end

    attribute :url, :string do
      public?(true)
      constraints(max_length: 500)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :room, Quorum.Sessions.Room do
      allow_nil?(false)
      attribute_writable?(true)
    end
  end
end
