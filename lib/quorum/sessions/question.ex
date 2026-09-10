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

    references do
      # A question belongs to its room and outlives nothing. Without this, a
      # room with anything in it can't be deleted at all.
      reference :room, on_delete: :delete
    end
  end

  actions do
    defaults([:read, :destroy])
    default_accept([])

    create :ask do
      description("A student posts a question to a room.")
      accept([:body, :display_name, :room_id, :submitter_token])

      argument :held_reason, :atom do
        description("Which moderation trigger holds this one for review, or nil for none.")
        constraints(one_of: [:room, :first, :word, :link, :screening])
      end

      # Status is never accepted from the client, only derived here, so no
      # crafted request can post a question straight past a review queue. The
      # reason is kept on the row, so the review queue can say why.
      change(fn changeset, _context ->
        case Ash.Changeset.get_argument(changeset, :held_reason) do
          nil ->
            changeset

          reason ->
            changeset
            |> Ash.Changeset.force_change_attribute(:status, :pending)
            |> Ash.Changeset.force_change_attribute(:held_reason, reason)
        end
      end)
    end

    update :approve do
      description("Release a held question into the live queue.")
      accept([])
      change(set_attribute(:status, :visible))
    end

    update :confirm_injection do
      description("The screen read this as an instruction to the AI. It stays held, marked.")
      accept([])
      change(set_attribute(:held_reason, :injection))
    end

    update :point do
      description("Attach the reading-list items the pointer matched to this question.")
      accept([:pointer_reading_ids])
    end

    update :draft do
      description("Store the suggested answer only the presenter sees.")
      accept([:answer_draft])
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

    # Why a pending question is waiting: which trigger held it, `:screening`
    # while the injection check runs, `:injection` once it has confirmed.
    # History rather than state after approval, so it survives the release.
    attribute :held_reason, :atom do
      public?(true)
      constraints(one_of: [:room, :first, :word, :link, :screening, :injection])
    end

    # The reading-list items the pointer matched, shown to the asker alone.
    attribute :pointer_reading_ids, {:array, :uuid} do
      allow_nil?(false)
      public?(true)
      default([])
    end

    # A suggested answer, drafted when the presenter spotlights the question,
    # and shown to nobody but them.
    attribute :answer_draft, :string do
      public?(true)
      constraints(max_length: 4000)
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
