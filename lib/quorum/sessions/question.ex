defmodule Quorum.Sessions.Question do
  @moduledoc """
  A question a student posts to a Room. Anonymous to peers unless the asker fills
  in `display_name`. The `submitter_token` is the browser's own token, used
  server-side to let the asker retract; it is never rendered to anyone.
  """
  use Ash.Resource,
    otp_app: :quorum,
    domain: Quorum.Sessions,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Quorum.Sessions.Broadcaster]

  postgres do
    table "questions"
    repo Quorum.Repo
  end

  actions do
    defaults([:read, :destroy])
    default_accept([])

    create :ask do
      description("A student posts a question to a room.")
      accept([:body, :display_name, :room_id, :submitter_token])

      argument :held?, :boolean do
        description("Whether the room's moderation settings hold this one for review.")
        default(false)
      end

      # Status is never accepted from the client, only derived here, so no
      # crafted request can post a question straight past a review queue.
      change(fn changeset, _context ->
        if Ash.Changeset.get_argument(changeset, :held?) do
          Ash.Changeset.force_change_attribute(changeset, :status, :pending)
        else
          changeset
        end
      end)
    end

    update :approve do
      description("Release a held question into the live queue.")
      accept([])
      change(set_attribute(:status, :visible))
    end

    update :answer do
      accept([])
      change(set_attribute(:status, :answered))
    end

    update :hide do
      accept([])
      change(set_attribute(:status, :hidden))
    end

    update :restore do
      description("Return a hidden or answered question to the live queue.")
      accept([])
      change(set_attribute(:status, :visible))
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :body, :string do
      allow_nil?(false)
      public?(true)
      # The ceiling. Each room's own limit lives on the room and is applied when
      # the question is asked, so this only ever catches a bad caller.
      constraints(max_length: 1000, min_length: 1)
    end

    # Optional; blank means anonymous to peers.
    attribute :display_name, :string do
      public?(true)
      constraints(max_length: 60)
    end

    # The browser's own token. Accepted from the client, never shown to peers.
    attribute :submitter_token, :string do
      allow_nil?(false)
      constraints(max_length: 64)
    end

    attribute :status, :atom do
      allow_nil?(false)
      public?(true)
      default(:visible)
      constraints(one_of: [:pending, :visible, :answered, :hidden])
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :room, Quorum.Sessions.Room do
      allow_nil?(false)
      attribute_writable?(true)
    end

    has_many :votes, Quorum.Sessions.Vote
  end

  aggregates do
    count(:vote_count, :votes)
  end
end
