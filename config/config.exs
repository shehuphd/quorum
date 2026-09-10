# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :spark, formatter: ["Ash.Resource": [section_order: [:postgres]]]

config :quorum,
  ecto_repos: [Quorum.Repo],
  ash_domains: [Quorum.Sessions, Quorum.Accounts, Quorum.AI],
  generators: [timestamp_type: :utc_datetime]

# Ash counts string length by unicode codepoints, matching how SQL data layers
# measure it, so validation is consistent in Elixir and in the database.
config :ash,
  default_string_length_count: :codepoints,
  known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec]

# Configure the endpoint
config :quorum, QuorumWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: QuorumWeb.ErrorHTML, json: QuorumWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Quorum.PubSub,
  live_view: [signing_salt: "4udevRw6"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
# Where the contact form's mail goes.
config :quorum, contact_email: "mo@mohammedshehu.com"

config :quorum, Quorum.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  quorum: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  quorum: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# The AI sidecar: where it answers, and how long a call may take. The shared
# token comes from QUORUM_SIDECAR_TOKEN at call time, never from config.
config :quorum, Quorum.AI, base_url: "http://127.0.0.1:4747"

# Background work. One queue and one job: the minute hand that closes a room
# whose own clock has run out.
config :quorum, Oban,
  repo: Quorum.Repo,
  queues: [default: 5],
  plugins: [
    {Oban.Plugins.Cron, crontab: [{"* * * * *", Quorum.Sessions.AutoClose}]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
