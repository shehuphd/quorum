# Quorum manifest

Last updated: 2026-09-10 13:50:00 UTC

Map of every source file: what it defines and what it touches. The Ash resources
are grouped under the `Quorum.Sessions` domain; the LiveViews are the five live
screens, and the landing page is a plain controller.

## Domain: Quorum.Accounts

| File | Role |
|---|---|
| `lib/quorum/accounts.ex` | Presenter accounts and the magic-link rules: fifteen minutes to live, single use, and a thirty-second cooldown between requests. `request_link/1` returns `{:ok, user, token}`, `{:wait, seconds}`, or an error; `claim_link/1` returns the presenter once and then `:spent` or `:expired`, so the screen can say which. |
| `lib/quorum/accounts/user.ex` | `User` resource: a presenter's email, optional name, and whether the rooms they open start by holding every question. Students never have one. `register` upserts on the email, so one address is one account. Postgres table `users`. |
| `lib/quorum/accounts/login_token.ex` | `LoginToken` resource: one single-use sign-in link, 32 random bytes with an expiry. Spent tokens are kept rather than deleted, so a second click is told apart from a token that never existed. Postgres table `login_tokens`. |
| `lib/quorum/accounts/notifier.ex` | The one email Quorum sends. In development it goes to the local mailbox at `/dev/mailbox` rather than out to the internet. |

## Domain: Quorum.Sessions

| File | Role |
|---|---|
| `lib/quorum/sessions.ex` | The `Quorum.Sessions` Ash domain. Lists the four resources, exposes `topic/1` and `subscribe/1` for a room's live feed, and holds every read and command helper the LiveViews call, so the web layer never builds a changeset or query by hand. `partition/1` splits a room's questions into the ranked queue, the ones held for review, and the answered list. `update_settings/2` is the single write behind every settings control, and each pane's defaults sit beside it for Reset this tab. `ask/2` applies the room's own limits, which are per room and so can't be resource constraints, and names each refusal (`:too_long`, `:too_many`) so the screen can say which one stopped it. `spotlight/2` refuses anything the room can't already see. `hold_reason/3` resolves the four moderation triggers to the one that fired. `close_room/1` deletes the room's questions when the room says not to keep them. `default_held_words/0` is the twenty a new room starts with. |
| `lib/quorum/sessions/room.ex` | `Room` resource: a live session with a generated `join_code` and secret `host_token`, an open/closed `status`, an optional `auto_close_at`, a nullable `spotlight_question` that drives the projection, and a nullable `owner`. Also carries the projection's four gradient colours, its angle, whether it drifts, which of the two halls it is showing now, what it puts on the wall (question size, whether it names the asker and the vote count, whether the join code stays beside a question, whether the counts show), whether students are pointed at the reading list, what a student may post (length, allowance, whether they can sign it, and whether the questions outlive the session), and what's moderated (hold everything, hold a first question, hold links, and the words that hold a question on their own). Actions: `open`, `close`, `rename`, `new_code`, `spotlight`, `clear_spotlight`, `settings`. Postgres table `rooms`. |
| `lib/quorum/sessions/reading.ex` | `Reading` resource: one item on a room's approved reading list, with a title, an optional page reference, and an optional link. Deleted with its room. This list is the only corpus the reading pointer may draw on. Postgres table `readings`. |
| `lib/quorum/sessions/question.ex` | `Question` resource: belongs to a room, holds `body`, optional `display_name`, private `submitter_token`, and a `status` (pending/visible/answered/hidden). Aggregate `vote_count`. Actions: `ask`, `approve`, `answer`, `hide`, `restore`, plus `point`, `draft`, and `confirm_injection` for the AI jobs. `ask` derives the status from a `held_reason` argument rather than accepting one, so no crafted request posts straight past a review queue, and the reason stays on the row so the review queue can say why. Postgres table `questions`. |
| `lib/quorum/sessions/vote.ex` | `Vote` resource: belongs to a question, carries `voter_token`, unique per (question, voter). Action `cast` upserts, so a repeat vote is a no-op. Deleted with the question it's about, so an upvoted question stays retractable. Postgres table `votes`. |
| `lib/quorum/sessions/codes.ex` | Generators for a room's five-character public join code (ambiguous glyphs removed) and its secret host token. |
| `lib/quorum/sessions/demo.ex` | The seeded demo session the landing page points at. Holds the question set, keeps one open demo room at a time, and exposes `current/0` (read only), `ensure_room/0` (seeds if needed), `seed/1`, and `clear/0`. |
| `lib/quorum/sessions/auto_close.ex` | The minute hand behind **Close automatically at**. An Oban cron job, run every minute, closing every open room whose time has passed on the same terms as the button, questions included. Reads only open rooms, so it never closes one twice. |
| `lib/quorum/sessions/broadcaster.ex` | Ash notifier. On any room, question, or vote change, broadcasts `{:room_changed, room_id}` on the room's PubSub topic so every watching LiveView reloads. Reads the database to resolve a vote's room, since a vote carries only a question id. |

## Domain: Quorum.AI

| File | Role |
|---|---|
| `lib/quorum/ai.ex` | The `Quorum.AI` domain and the one door to the sidecar: `enabled?/0` for every feature to gate on, `generate/3` and `generate_json/3` which make the call and record what it spent, `calls/1`, `spend/0`, and `clear_spend/0` for the counter, and `targets/0`, `providers/0`, `add_key/1`, `pin_model/2`, `remove_key/1` behind the AI keys settings tab. Quorum holds no provider keys and never speaks to a provider. |
| `lib/quorum/ai/call.ex` | `Call` resource: one model call as a record. Purpose, provider, model, tokens, elapsed time, and whether it worked, written on success and failure alike. Plain ids rather than foreign keys, so the spend record outlives the room it was spent on. Postgres table `ai_calls`. |
| `lib/quorum/ai/client.ex` | The behaviour a sidecar client answers; tests swap in a closure-backed stub. |
| `lib/quorum/ai/sidecar.ex` | The Req client for the sidecar: /generate plus the key-management calls (list targets and providers, add a key, pin a model, remove a key), all on localhost with the shared token, every failure mapped to a plain reason. |
| `lib/quorum/ai/pointer_job.ex` | Matches a fresh question to the room's reading list, at most two picks from numbered entries, stored on the question for the asker alone. The list is the only corpus offered. |
| `lib/quorum/ai/draft_job.ex` | Drafts a suggested answer when a question is spotlighted, presenter-only, three to five spoken sentences. Two or three bullet points, fifty words at most, each one a sentence the presenter could say aloud. A question keeps its draft, so a re-spotlight bills nothing. |
| `lib/quorum/ai/screen_job.ex` | The injection screen: one boolean from the model. Clean releases the question; flagged stays held, marked `:injection`; every failure leaves it held for the presenter. |
| `sidecar/quorum_sidecar.py` | The Python service that holds the keys and drives every provider through KeyCall. `/health` names targets, `/generate` makes one normalized call, and /targets manages the key file itself: a key is validated against its provider before it's stored, listed back as its first four characters and asterisks, pinned to a model, or removed. A shared token guards the port and providers are data from the key file, named nowhere in code. Models aren't chosen so much as survived: candidates are walked in KeyCall verify's order and the first that answers is remembered per request kind, and a schema a provider refuses wholesale is retried without its additionalProperties keys. |
| `sidecar/run.sh` | Starts the sidecar: installs its requirements on first run, generates the shared token when none is set, and prints it for the app. |

## Web: the five screens

| File | Role |
|---|---|
| `lib/quorum_web/live/join_live.ex` | `/join`. Five slots rather than a text field, with the caret on the slot the next character goes in; a transparent input over the row takes the typing, so a tap anywhere on it raises the keyboard. The fifth character resolves the room and the screen becomes it: the session's name, a live count of who is in and what they have asked, and the room's own gradient and hall. A closed room says so and offers what was asked; an unknown code names itself. The way in is a plain form post, so a display name can reach the session cookie rather than a URL. Accepts a `?code=` prefill. |
| `lib/quorum_web/live/attendee_live.ex` | `/r/:code`. The student's phone-first feed, inside the site shell so the mark goes home: compose a question, upvote, retract your own. A vote fills the box and moves the count, and the list ranks live; the pin beside each vote box is that browser's own bookmark, lifting a question to the top of their list alone. Keeps an unsent draft on the server so a reconnect restores it. Follows the room's own limits: the composer's length, whether a name can be attached, and how many the student has left. A question the room holds appears here for its asker alone, marked as waiting, and can be retracted from there. Posting opens a ten-second window before the write: the composer is replaced by a burn-down bar and a counting Cancel, and a cancelled question is never written at all. |
| `lib/quorum_web/live/host_live.ex` | `/host/:host_token`. The presenter's console as a full page: site shell, room bar with rename and the live counts, the joining panel (large while the room is empty, a strip once questions arrive), ranked queue, the review queue that appears above it while anything is held, and a rail carrying what's on the projection, the before-you-start checklist, and the keyboard map. Keyboard: **J**, **K**, **Enter**, **A**, **H**, Escape. |
| `lib/quorum_web/live/projection_live.ex` | `/host/:host_token/project`. The screen at the front of the hall. Joining owns the screen until a question is spotlighted, then shrinks to a 268px rail. Takes its hall, gradient, angle, drift, question size, and what it names under and around a question from the room, so the Appearance and Projection tabs change what the hall sees. Keyboard: **L**, **D**, **Q**. Renders the QR code server-side. |
| `lib/quorum_web/live/archive_live.ex` | `/archive`. The term's record: every session a presenter has run, newest first, with what it drew ranked the way the hall ranked it. A strip of figures over a search that runs across every session at once, a filter down to one, and an order toggle. Long sessions show their top five and expand. Held and hidden questions are left out, since a question the room never saw isn't part of what the room asked. |
| `lib/quorum_web/live/settings_live.ex` | `/host/:host_token/settings/:tab`. Seven categories on a rail: Room, Questions, Moderation, Readings and AI, Projection, Appearance, AI keys. The AI keys tab manages the sidecar's key file: a pasted key is tested live before it's stored, shown as its first four characters and asterisks, pinned to a model from the provider's usable catalog, or removed; under it, the spend counter and its clear button. Every control saves on change, so there is no save button; the status line has its height reserved so the first save doesn't move the buttons under the pointer. All six panes are drawn. Deleting a room needs the session closed and its name typed. |
| `lib/quorum_web/controllers/page_controller.ex`, `page_html.ex`, `page_html/*` | `/`, `/privacy`, `/accessibility`, `/contact`. The landing page plus the three standing pages the footer links to. The contact form is guarded by a honeypot and a per-session cooldown. |
| (landing template) | `/`. The landing page: hero with a code field and Start a room, the demo band, how it works, the reading-pointer illustration, the capability columns, and the closing call to action. Reads the demo room without seeding, so a visit never writes. `page_html.ex` carries `word/1`, `count/3`, and `qr/2`. |
| `lib/quorum_web/controllers/archive_controller.ex` | `GET /archive/export`. The term's questions as a CSV, every field quoted, for the presenter who plans in a spreadsheet. |
| `lib/quorum_web/controllers/room_controller.ex` | `GET /start` opens a room, owned by the presenter when one is signed in, and redirects to its console. `GET /rooms` lists a presenter's own. `POST /join` is the way in from the join page: it puts the display name in the session, where the feed reads it, and redirects to the room. |
| `lib/quorum_web/controllers/session_controller.ex`, `session_html.ex`, `session_html/*` | `/sign-in`, `/sign-in/sent`, `/sign-in/:token`, `/sign-out`. Magic-link sign-in for presenters. The check-your-email screen reads the same whether or not the address was known, so it can't be used to find out who has an account. |
| `lib/quorum_web/controllers/demo_controller.ex` | `/demo`, `/demo/host`, `/demo/project`. Three doors into the seeded demo session, one per role. Finds or seeds the room, then redirects, so the landing page's links survive a reseed. |

## Web: supporting modules

| File | Role |
|---|---|
| `lib/quorum_web/brand.ex` | The Quorum logo as an HTML component, in light and on-dark variants. HTML rather than an SVG file, because an SVG loaded through `<img>` cannot resolve the page's webfonts. |
| `lib/quorum_web/browser_token.ex` | Plug that gives each browser an opaque session token. That token is what makes a vote idempotent and lets a student retract their own question, with no sign-up. |
| `lib/quorum_web/landing_examples.ex` | The twenty sample questions the landing page's feed card cycles through, half named and half anonymous, plus the phrasing for an age between 30 seconds and 15 minutes. |
| `lib/quorum/contact.ex` | The contact form's validation and delivery. Mail goes from Quorum's own address with the sender on `reply-to`, so it doesn't fail SPF or DKIM at the receiving end. |
| `lib/quorum_web/shell.ex` | The site header and footer. Nav entries render only when the page behind them exists, so the header never offers a link that goes nowhere. Three variants: `:app` for a presenter's pages, `:guest` for sign-in, and `:student` in a room, where the only two places to go are home and another code. |
| `lib/quorum_web/current_user.ex` | Plug putting the signed-in presenter on the connection, and the session helpers behind it. Only the user id is stored, so a stale cookie for a deleted account resolves to nil. |
| `lib/quorum_web/presence.ex` | `Phoenix.Presence` over `Quorum.PubSub`. Counts the students connected to a room for the console and the projection. |
| `lib/quorum_web/router.ex` | Routes. The browser pipeline carries `BrowserToken`, then `CurrentUser`. |

## Phoenix skeleton

| File | Role |
|---|---|
| `lib/quorum/application.ex` | OTP application. Supervises the repo, PubSub (`Quorum.PubSub`), Presence, telemetry, and the endpoint. |
| `lib/quorum/repo.ex` | `Quorum.Repo`, an `AshPostgres.Repo` over PostgreSQL. |
| `lib/quorum/mailer.ex` | Swoosh mailer, behind the sign-in link and the contact form. In development it writes to the local mailbox rather than sending. |
| `lib/quorum.ex` | App boundary module (generated). |
| `lib/quorum_web.ex` | Web boundary: `controller/0`, `live_view/0`, `html/0` macros. |
| `lib/quorum_web/endpoint.ex` | HTTP endpoint and socket wiring. |
| `lib/quorum_web/telemetry.ex` | Telemetry supervisor and metric definitions. |
| `lib/quorum_web/gettext.ex` | Translation macros. |
| `lib/quorum_web/components/core_components.ex` | Shared function components (generated). |
| `lib/quorum_web/components/layouts.ex`, `layouts/root.html.heex` | Root and app layouts. The root layout loads the app stylesheet and sets the title suffix. |
| `lib/quorum_web/controllers/error_html.ex`, `error_json.ex` | Error renderers. |

## Mix tasks

| File | Role |
|---|---|
| `lib/mix/tasks/quorum.demo.ex` | `mix quorum.demo`. Opens a room, seeds nine questions with plausible vote counts and one already answered, and prints the join code with the student, host, and projection links. |

## Assets

| File | Role |
|---|---|
| `assets/css/app.css` | Entry point. Imports the stylesheets below, then adds the base body rules, the link-as-button rule, `.q-sr-only`, `.q-divider`, the reconnecting banner, and the three corrections where the design export falls short of DESIGN.md (44px link buttons, and the laptop-width vote control and question size). |
| `assets/css/tokens.css` | Design tokens: colour, type, spacing, radius, touch target sizes. |
| `assets/css/quorum.css` | The `q-*` component classes: buttons, inputs, surfaces, rows, the vote control, status lines, the projection backgrounds. |
| `assets/css/shell.css` | The page shell: site header and footer, the room bar, the console's two-column frame, the joining panel and strip, the queue rows, the sign-in split, the standing pages' prose column, and the settings rail, panes, switch, colour pickers, reading list, and AI keys rows. Carries the breakpoints that collapse all of them to one column, where the settings rail becomes a scrolling strip with a faded trailing edge. |
| `assets/css/join.css` | The join screen: the two halls as one set of `--j-*` colours, the five code slots and the caret, the skeleton status line, and the centred laptop layout. |
| `assets/css/archive.css` | The archive: the strip of figures, the search and filter bar, and the session panels with their question rows. |
| `assets/css/landing.css` | The landing page's bands and grids (`q-l-*`), plus `q-button--ink` for the nav call to action. Everything else on that page reuses the product's components. |
| `assets/css/fonts.css` | 33 `@font-face` rules pointing at the self-hosted woff2 files. |
| `priv/static/fonts/*.woff2` | 17 font files: Archivo for interface type, Literata for question bodies. Self-hosted so the app never depends on a font CDN. |
| `assets/js/app.js` | LiveView socket setup, plus the copy-to-clipboard handler and the landing page's example rotation. The rotation holds still under `prefers-reduced-motion` and pauses when the tab is hidden. |

## Migrations

| File | Role |
|---|---|
| `priv/repo/migrations/20260909132645_initialize_extensions_1.exs` | Installs the `ash-functions` Postgres extension. |
| `priv/repo/migrations/20260909134137_initial_sessions.exs` | Creates `rooms`, `questions`, `votes` with their unique indexes and foreign keys. |
| `priv/repo/migrations/20260909152328_add_spotlight.exs` | Adds `rooms.spotlight_question_id`, nilified when the question is deleted. |
| `priv/repo/migrations/20260909173909_add_demo_flag.exs` | Adds `rooms.demo?`, so the demo room is never confused with a presenter's own. |
| `priv/repo/migrations/20260909180739_add_accounts.exs` | Creates `users` and `login_tokens`, and adds `rooms.owner_id`, nilified when the presenter's account goes so the room stays reachable by its host link. |
| `priv/repo/migrations/20260909200148_add_settings.exs` | Creates `readings`, and adds the room's projection colours, gradient angle, drift flag, and reading-pointer flag. |
| `priv/repo/migrations/20260909204309_add_questions_and_moderation.exs` | Adds the room's question length, per-student allowance, signing flag, hold-for-review flag, and held-word list. |
| `priv/repo/migrations/20260909210338_add_hold_triggers.exs` | Adds the room's hold-on-links and hold-first-question flags, and the presenter's hold-by-default preference. |
| `priv/repo/migrations/20260909210546_add_retention_and_vote_cascade.exs` | Adds the room's keep-questions flag, and makes votes cascade when their question is deleted. |
| `priv/repo/migrations/20260909213240_add_default_held_words.exs` | Moves the held-word default out of the column, since a new room now seeds it from the domain. |
| `priv/repo/migrations/20260909213840_add_projection_display.exs` | Adds the room's question size and the four switches for what the projection shows. |

## Launchers

| File | Role |
|---|---|
| `launch.sh` | Checks Elixir, starts PostgreSQL if it's installed but stopped (Postgres.app, a Homebrew service, or `$PGDATA`, never with sudo), stops a stale server started from this directory, fetches deps, sets up the database, finds a free port, opens a browser, and runs the server. |
| `launch.command` | macOS double-click wrapper around `launch.sh`. |
| `launch.bat` | Windows equivalent, including the PostgreSQL start. Written but not run on Windows. |

## Tests

| File | Role |
|---|---|
| `test/quorum/accounts_test.exs` | The magic-link rules: registration, case-insensitive addresses, the cooldown, single use, expiry, and one presenter's link never signing in another. |
| `test/quorum_web/controllers/session_controller_test.exs` | The sign-in screens and the whole loop: the disabled SSO control with its microcopy, the email it sends, a refused address, no second email inside the cooldown, sign-in, sign-out, and a presenter seeing only their own rooms. |
| `test/quorum/sessions_test.exs` | Adversarial suite over the Sessions resources: validation failures, anonymity, vote dedup, status transitions, ranking, spotlight, and live-update broadcasts. |
| `test/quorum_web/live/join_live_test.exs` | The join screen: label, prefill, unknown code, and navigation however the code was typed. |
| `test/quorum_web/live/attendee_live_test.exs` | The student feed: posting, draft retention, retraction limited to the author, voting and unvoting with the word "Voted" present, the answered list, the closed room, and live arrival. Then the room's limits: a refusal past the length, a refusal past the allowance, the count of what's left, a name dropped when signing is off, and the whole held-question path from posting to approval. |
| `test/quorum_web/live/host_live_test.exs` | The console: ranking, spotlight and clear, answer and reopen, hide, search and tally, the close dialog including Escape, the keyboard shortcuts (no ring and no target until the first press), the live Clear on the spotlighted row, live arrival, and the review queue: counting, approving, refusing, a held question from another room, and a held question refused the projection. |
| `test/quorum_web/live/projection_live_test.exs` | The projection: the waiting screen, the spotlight swap, attribution and vote pluralisation, **L** / **D** / **Q**, and the tally. |
| `test/quorum_web/live/settings_live_test.exs` | The settings screens: the rail and its URLs, an unknown tab, the undrawn panes, saving without a save button, the appearance controls reaching the projection, Reset this tab, adding, searching, and removing readings, one room's readings never showing in another's, the question limits reaching the student's composer, the moderation switch and its held words, the delete guard from the disabled control through the typed name, and the AI keys tab: the down-state, the listed keys with hints and models, a key tested as it's entered, a refused key, pinning, removing, and the spend counter through its clear. |
| `test/support/fixtures.ex` | `room/1`, `question/3`, and `votes/2` builders, so tests read as scenarios. |
| `test/support/conn_case.ex`, `data_case.ex` | Test case templates with the Ecto sandbox. |
| `test/quorum_web/controllers/page_controller_test.exs` | The landing page: both entry points, every section, the three demo roles, the sample code when no demo room exists, and the live code and counts when one does. |
| `test/quorum_web/controllers/demo_controller_test.exs` | The demo doors: seeding on first use, all three reaching the same room, reuse on a second visit, reseeding after a clear, and a presenter's own room never being mistaken for the demo. |
| `test/quorum_web/controllers/error_html_test.exs`, `error_json_test.exs` | Error view tests. |
