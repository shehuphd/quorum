defmodule Quorum.Sessions.Vote do
  @moduledoc """
  One upvote by one browser on one question. The `voter_token` is the browser's
  own token; the unique identity plus an upsert make a repeat vote a no-op rather
  than an error. Unvoting is a destroy.
  """
  use Ash.Resource,
    otp_app: :quorum,
    domain: Quorum.Sessions,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Quorum.Sessions.Broadcaster]

  postgres do
    table "votes"
    repo Quorum.Repo
  end

  actions do
    defaults([:read, :destroy])
    default_accept([])

    create :cast do
      description("A student upvotes a question once.")
      accept([:question_id, :voter_token])
      upsert?(true)
      upsert_identity(:unique_vote)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :voter_token, :string do
      allow_nil?(false)
      constraints(max_length: 64)
    end

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :question, Quorum.Sessions.Question do
      allow_nil?(false)
      attribute_writable?(true)
    end
  end

  identities do
    identity(:unique_vote, [:question_id, :voter_token])
  end
end
