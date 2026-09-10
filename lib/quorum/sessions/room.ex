defmodule Quorum.Sessions.Room do
  @moduledoc """
  One live session: a class, an all-hands, or a stream. Students join it by its
  `join_code` (also encoded in the projected QR); whoever holds the `host_token`
  gets the host view.
  """
  use Ash.Resource,
    otp_app: :quorum,
    domain: Quorum.Sessions,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Quorum.Sessions.Broadcaster]

  alias Quorum.Sessions.Codes

  postgres do
    table "rooms"
    repo Quorum.Repo

    references do
      # If a spotlighted question is deleted, the projection just goes dark.
      reference :spotlight_question, on_delete: :nilify
      # A room outlives the presenter's account; its host_token still opens it.
      reference :owner, on_delete: :nilify
    end
  end

  actions do
    defaults([:read, :destroy])
    default_accept([])

    create :open do
      description("Open a new room. The caller keeps the returned host_token.")
      accept([:name, :auto_close_at, :demo?, :owner_id, :hold_for_review?])
    end

    update :close do
      description("Close the room to new questions and votes.")
      accept([])
      change(set_attribute(:status, :closed))
    end

    update :settings do
      description(
        "Apply one settings change. Every control on the settings screens saves through here."
      )

      accept([
        :name,
        :auto_close_at,
        :projection_light_from,
        :projection_light_to,
        :projection_dark_from,
        :projection_dark_to,
        :projection_angle,
        :projection_drift?,
        :projection_dark?,
        :projection_question_scale,
        :projection_show_asker?,
        :projection_show_votes?,
        :projection_show_joining?,
        :projection_show_counts?,
        :readings_pointer?,
        :question_max_length,
        :questions_per_student,
        :allow_display_name?,
        :keep_questions?,
        :hold_for_review?,
        :hold_links?,
        :hold_first_question?,
        :held_words
      ])
    end

    update :rename do
      description("Change the room's name. The join code and host token are untouched.")
      accept([:name])
    end

    update :new_code do
      description("Issue a fresh join code, so a code shown to the wrong room stops working.")
      accept([])
      change(set_attribute(:join_code, &Quorum.Sessions.Codes.join_code/0))
    end

    update :spotlight do
      description("Put a question on the projection.")
      accept([:spotlight_question_id])
    end

    update :clear_spotlight do
      description("Take the projection back to the waiting screen.")
      accept([])
      change(set_attribute(:spotlight_question_id, nil))
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
      constraints(max_length: 200, min_length: 1)
    end

    # Shown to students; generated, never client-set.
    attribute :join_code, :string do
      allow_nil?(false)
      default(&Codes.join_code/0)
      constraints(max_length: 12)
    end

    # Secret; grants the host view. Never rendered to students.
    attribute :host_token, :string do
      allow_nil?(false)
      default(&Codes.token/0)
      constraints(max_length: 64)
    end

    attribute :status, :atom do
      allow_nil?(false)
      public?(true)
      default(:open)
      constraints(one_of: [:open, :closed])
    end

    attribute :auto_close_at, :utc_datetime do
      public?(true)
    end

    # Appearance. These are seeds, not constants: the defaults match the design
    # tokens, and Settings, Appearance edits them per room.
    attribute :projection_light_from, :string do
      allow_nil?(false)
      public?(true)
      default("#E9E9E9")
      constraints(match: ~r/^#[0-9A-Fa-f]{6}$/)
    end

    attribute :projection_light_to, :string do
      allow_nil?(false)
      public?(true)
      default("#FAFAFA")
      constraints(match: ~r/^#[0-9A-Fa-f]{6}$/)
    end

    attribute :projection_dark_from, :string do
      allow_nil?(false)
      public?(true)
      default("#1A1A1A")
      constraints(match: ~r/^#[0-9A-Fa-f]{6}$/)
    end

    attribute :projection_dark_to, :string do
      allow_nil?(false)
      public?(true)
      default("#313131")
      constraints(match: ~r/^#[0-9A-Fa-f]{6}$/)
    end

    attribute :projection_angle, :integer do
      allow_nil?(false)
      public?(true)
      default(60)
      constraints(min: 0, max: 360)
    end

    attribute :projection_drift?, :boolean do
      allow_nil?(false)
      public?(true)
      default(true)
    end

    # Which of the two halls the projection is showing. Kept on the room rather
    # than in the projection's own process, because the join page follows it: a
    # student's phone reads as a second window on the same wall.
    attribute :projection_dark?, :boolean do
      allow_nil?(false)
      public?(true)
      default(true)
    end

    # What the projection puts on the wall, and how large. A hall with a back
    # row forty metres away needs a bigger question than a seminar room does.
    attribute :projection_question_scale, :integer do
      allow_nil?(false)
      public?(true)
      default(100)
      constraints(min: 75, max: 150)
    end

    # The line under a spotlighted question: who asked it, and how many wanted
    # it. Either can go, for a room where attribution or a vote count on the
    # wall would change what people ask.
    attribute :projection_show_asker?, :boolean do
      allow_nil?(false)
      public?(true)
      default(true)
    end

    attribute :projection_show_votes?, :boolean do
      allow_nil?(false)
      public?(true)
      default(true)
    end

    # The joining rail beside a spotlighted question. Off gives the question the
    # whole wall once everyone is already in the room.
    attribute :projection_show_joining?, :boolean do
      allow_nil?(false)
      public?(true)
      default(true)
    end

    # The connected and asked counts along the bottom.
    attribute :projection_show_counts?, :boolean do
      allow_nil?(false)
      public?(true)
      default(true)
    end

    attribute :readings_pointer?, :boolean do
      allow_nil?(false)
      public?(true)
      default(false)
    end

    # What a student may post. The ceiling is the Question resource's own 1000;
    # this is the operative limit, and the composer counts down to it.
    attribute :question_max_length, :integer do
      allow_nil?(false)
      public?(true)
      default(500)
      constraints(min: 140, max: 1000)
    end

    # How many questions one browser can have waiting at once. Zero is no limit.
    attribute :questions_per_student, :integer do
      allow_nil?(false)
      public?(true)
      default(0)
      constraints(min: 0, max: 20)
    end

    # Off means every question is anonymous, whether or not a name was typed.
    attribute :allow_display_name?, :boolean do
      allow_nil?(false)
      public?(true)
      default(true)
    end

    # Questions outlive the session by default. A term of them is what tells a
    # presenter which material didn't land, so they're the record the room is
    # for. A presenter who'd rather not keep them turns this off, and closing
    # the session takes them.
    attribute :keep_questions?, :boolean do
      allow_nil?(false)
      public?(true)
      default(true)
    end

    # Moderation. Off is post-hoc: a question appears, and the presenter can hide
    # it. On holds every question until the presenter approves it.
    attribute :hold_for_review?, :boolean do
      allow_nil?(false)
      public?(true)
      default(false)
    end

    # A question carrying a link waits, whatever the toggle above says. Links
    # are how a live room gets used to advertise at a captive audience.
    attribute :hold_links?, :boolean do
      allow_nil?(false)
      public?(true)
      default(false)
    end

    # Hold a student's first question in this room, and let them through once
    # one has been approved. Students have no accounts, so "new" can only mean
    # new to this room.
    attribute :hold_first_question?, :boolean do
      allow_nil?(false)
      public?(true)
      default(false)
    end

    # Words that hold a question for review on their own, whatever the toggle
    # above says. Stored lowercase; matched whole-word.
    attribute :held_words, {:array, :string} do
      allow_nil?(false)
      public?(true)
      default(&Quorum.Sessions.default_held_words/0)
    end

    # A demo room is the one the landing page points at, so anyone can look at
    # the product without opening a session of their own.
    attribute :demo?, :boolean do
      allow_nil?(false)
      public?(true)
      default(false)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    has_many :questions, Quorum.Sessions.Question
    has_many :readings, Quorum.Sessions.Reading

    # The presenter who opened it, when they were signed in. Rooms opened from
    # /start without an account have no owner and are reached by host_token only.
    belongs_to :owner, Quorum.Accounts.User do
      allow_nil?(true)
      attribute_writable?(true)
    end

    # The question currently on the projection, if any.
    belongs_to :spotlight_question, Quorum.Sessions.Question do
      allow_nil?(true)
      attribute_writable?(true)
    end
  end

  identities do
    identity(:unique_join_code, [:join_code])
    identity(:unique_host_token, [:host_token])
  end
end
