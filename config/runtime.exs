import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/quorum start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :quorum, QuorumWeb.Endpoint, server: true
  # The app is serving, so keep the database warm underneath it. Idle outside the
  # warm window is the container scaled to zero, not a server sitting idle.
  config :quorum, :heartbeat, enabled: true, interval_ms: 240_000
end

config :quorum, QuorumWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :quorum, QuorumWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/quorum_web/router\.ex$"E,
        ~r"lib/quorum_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # Neon and most managed Postgres require TLS. Verify against the system CA
  # store (the runtime image carries ca-certificates) and send SNI so the
  # endpoint presents the right certificate for its host.
  db_host = database_url |> URI.parse() |> Map.fetch!(:host)

  config :quorum, Quorum.Repo,
    ssl: [
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(db_host)
    ],
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :quorum, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :quorum, QuorumWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :quorum, QuorumWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :quorum, QuorumWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## The mailer
  #
  # The base config names Swoosh's local adapter, which keeps mail in a process
  # this environment doesn't start, so leaving it in place makes every send exit.
  # Whichever provider has credentials here wins, and with none of them set the
  # contact form's mail goes to the log, where `az containerapp logs show` reads
  # it back.
  #
  # Brevo takes an API key and sends from any address you've confirmed by email.
  # Mailgun takes a key and a sending domain, its no-DNS sandbox included, and
  # sends only from that domain. Any other Swoosh provider works the same way:
  # name its adapter and pass its own keys.
  brevo_key = System.get_env("BREVO_API_KEY")
  mailgun_key = System.get_env("MAILGUN_API_KEY")
  mailgun_domain = System.get_env("MAILGUN_DOMAIN")

  cond do
    brevo_key ->
      # Brevo sends only from an address the account has confirmed, so a key
      # without one to send from is a send that fails at the provider. Say so at
      # boot rather than leaving it to the first person who uses the form.
      unless System.get_env("CONTACT_FROM") do
        IO.warn(
          "BREVO_API_KEY is set but CONTACT_FROM isn't, so the form will mail " <>
            "from its built-in address, which Brevo refuses unless the account " <>
            "has confirmed it. Set CONTACT_FROM to a sender you confirmed."
        )
      end

      config :quorum, Quorum.Mailer, adapter: Swoosh.Adapters.Brevo, api_key: brevo_key

    mailgun_key && mailgun_domain ->
      config :quorum, Quorum.Mailer,
        adapter: Swoosh.Adapters.Mailgun,
        api_key: mailgun_key,
        domain: mailgun_domain

      # Mailgun sends only from a domain the account holds, so the from address
      # follows the sending domain unless CONTACT_FROM says otherwise.
      config :quorum,
             :contact_from,
             System.get_env("CONTACT_FROM") || "no-reply@#{mailgun_domain}"

    true ->
      # The whole message, not only who it was for, so a form submission is
      # still readable back out of the log.
      config :quorum, Quorum.Mailer,
        adapter: Swoosh.Adapters.Logger,
        log_full_email: true
  end

  # The address the form mails from. A provider will only send from one it has
  # confirmed, so this is set per deployment rather than written down.
  if from = System.get_env("CONTACT_FROM") do
    config :quorum, :contact_from, from
  end

  # The AI's daily ceilings. The provider keys behind the sidecar are live, so
  # these are what stop an open demo drawing an account down: a dollar limit,
  # and a count of calls beside it for models the ledger can't price yet.
  if budget = System.get_env("QUORUM_AI_DAILY_BUDGET") do
    config :quorum, :ai_daily_budget, budget
  end

  if calls = System.get_env("QUORUM_AI_DAILY_CALLS") do
    config :quorum, :ai_daily_calls, calls
  end

  # Where the contact form's mail goes.
  if address = System.get_env("CONTACT_EMAIL") do
    config :quorum, :contact_email, address
  end
end
