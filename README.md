# Quorum

See demo at [mohammedshehu.com/quorum](https://mohammedshehu.com/quorum).

Quorum is a live audience engagement tool, built first for university teaching. The presenter projects a QR code; students scan it to join the session in one tap, then post and upvote questions from their seats. The top questions rank live over a websocket with no page refresh, so quieter students take part instead of being cold-called. The presenter answers questions and closes the session. Questions are anonymous to peers by default. The same primitives serve any live audience, so company all-hands and streamed talks remain options later.

Built with Elixir and Phoenix LiveView, so the interactive UI renders server-side with almost no JavaScript.

## Development status

The landing page, presenter sign-in, and the five screens are built and driven by the live data layer: the join screen, the student feed, the presenter's console, the projection, and the settings. All seven settings categories are drawn. A presenter's own archive at `/archive` reads a term of sessions back, in the browser or as a CSV. The AI features run through a small keyed sidecar and stand down without it: the reading pointer under a student's question, a presenter-only suggested answer on spotlight, and a fifth moderation trigger that holds questions aimed at the AI. Single sign-on is designed but not built.

## Local development

Prerequisites: Elixir and PostgreSQL. Check them with `elixir --version` and `pg_isready`; if either is missing, install Elixir from [elixir-lang.org/install](https://elixir-lang.org/install.html) and PostgreSQL from [postgresql.org/download](https://www.postgresql.org/download/).

The quickest start is the launcher, which starts PostgreSQL if it's installed but not running, fetches dependencies, sets up the database, picks a free port, and opens a browser:

```bash
./launch.sh
```

macOS users can double-click `launch.command`; Windows users can double-click `launch.bat`.

To drive it by hand instead:

```bash
mix setup       # fetch deps, create and migrate the database, build assets
mix test        # run the test suite
mix phx.server  # start the app on http://localhost:4000
```

## Set up with your coding agent

Hand a fresh clone to your coding agent with this block and it takes the app to a
running state with the AI features on. The one step it hands back to you is the API
keys, which are secrets you paste.

1. Make sure PostgreSQL is running (or run `./launch.sh` once, which starts it), then
   run `mix setup` (fetch deps, create and migrate the database, build assets).
2. Create `project/keys.toml` (gitignored) and ask me for one or more provider API
   keys to put in it, in KeyCall's `[[targets]]` shape. These are secrets I paste in;
   don't generate them.
3. Start the sidecar with `./sidecar/run.sh`. It installs its Python deps on first run
   and prints a `QUORUM_SIDECAR_TOKEN`. Keep that value.
4. Start the app with that token: `QUORUM_SIDECAR_TOKEN=<token> mix phx.server`, then
   open http://localhost:4000.

Skip steps 2 and 3 and the app still runs; the AI features stay off until the sidecar
is up.

## Using it

The quickest look is the demo session. From the landing page, the demo band opens the same seeded room in any of three roles, or go straight to `/demo`, `/demo/host`, or `/demo/project`.

For a room of your own, `/start` opens one and redirects to the presenter's console at a secret host URL, which links to the projection screen for the projector and to the room's settings. Students go to `/join` and type the five-character code, or scan the QR code on the projection.

Presenters can sign in at `/sign-in` to keep a list of their rooms. Sign-in is a demo stub: one access code, shown as the field's own placeholder, opens a shared demo presenter, so no email or mail provider is needed. A room still opens without an account, and its host link keeps working either way.

[USAGE.md](USAGE.md) covers each screen and its keyboard shortcuts.

## Documentation

- [USAGE.md](USAGE.md): the full manual, growing with each feature
- [ARCHITECTURE.md](ARCHITECTURE.md): how the app is put together
- [MANIFEST.md](MANIFEST.md): what every source file does
- [CHANGELOG.md](CHANGELOG.md): dated changes per release

## Tech stack

- Elixir on the BEAM
- Phoenix and LiveView for the web surface
- Ash for the domain layer, on Ecto and PostgreSQL
- Phoenix Presence and PubSub for live counts and broadcasts
- eqrcode for the projected join code
- A Python sidecar on KeyCall for every provider call, holding the keys so the app never does
- Archivo and Literata, self-hosted as woff2

By [Mo Shehu](https://mohammedshehu.com)
