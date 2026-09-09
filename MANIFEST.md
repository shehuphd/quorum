# Quorum manifest

Last updated: 2026-09-09 21:45:00 UTC

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
| `lib/quorum/sessions.ex` | The `Quorum.Sessions` Ash domain. Lists the four resources, exposes `topic/1` and `subscribe/1` for a room's live feed, and holds every read and command helper the LiveViews call, so the web layer never builds a changeset or query by hand. `partition/1` splits a room's questions into the ranked queue, the ones held for review, and the answered list. `update_settings/2` is the single write behind every settings control, and each pane's defaults sit beside it for Reset this tab. `ask/2` applies the room's own limits, which are per room and so can't be resource constraints, and names each refusal (`:too_long`, `:too_many`) so the screen can say which one stopped it. `spotlight/2` refuses anything the room can't already see. `hold_reason/3` resolves the four moderation triggers to the one that fired. `close_room/1` deletes the room's questions when the room says not to keep them. |
| `lib/quorum/sessions/room.ex` | `Room` resource: a live session with a generated `join_code` and secret `host_token`, an open/closed `status`, an optional `auto_close_at`, a nullable `spotlight_question` that drives the projection, and a nullable `owner`. Also carries the projection's four gradient colours, its angle, whether it drifts, whether students are pointed at the reading list, what a student may post (length, allowance, whether they can sign it, and whether the questions outlive the session), and what's moderated (hold everything, hold a first question, hold links, and the words that hold a question on their own). Actions: `open`, `close`, `rename`, `new_code`, `spotlight`, `clear_spotlight`, `settings`. Postgres table `rooms`. |
| `lib/quorum/sessions/reading.ex` | `Reading` resource: one item on a room's approved reading list, with a title, an optional page reference, and an optional link. Deleted with its room. This list is the only corpus the reading pointer may draw on. Postgres table `readings`. |
| `lib/quorum/sessions/question.ex` | `Question` resource: belongs to a room, holds `body`, optional `display_name`, private `submitter_token`, and a `status` (pending/visible/answered/hidden). Aggregate `vote_count`. Actions: `ask`, `approve`, `answer`, `hide`, `restore`. `ask` derives the status from a `held?` argument rather than accepting one, so no crafted request posts straight past a review queue. Postgres table `questions`. |
| `lib/quorum/sessions/vote.ex` | `Vote` resource: belongs to a question, carries `voter_token`, unique per (question, voter). Action `cast` upserts, so a repeat vote is a no-op. Deleted with the question it's about, so an upvoted question stays retractable. Postgres table `votes`. |
| `lib/quorum/sessions/codes.ex` | Generators for a room's five-character public join code (ambiguous glyphs removed) and its secret host token. |
| `lib/quorum/sessions/demo.ex` | The seeded demo session the landing page points at. Holds the question set, keeps one open demo room at a time, and exposes `current/0` (read only), `ensure_room/0` (seeds if needed), `seed/1`, and `clear/0`. |
| `lib/quorum/sessions/broadcaster.ex` | Ash notifier. On any room, question, or vote change, broadcasts `{:room_changed, room_id}` on the room's PubSub topic so every watching LiveView reloads. Reads the database to resolve a vote's room, since a vote carries only a question id. |

## Web: the five screens

| File | Role |
|---|---|
| `lib/quorum_web/live/join_live.ex` | `/join`. Types a five-character code and navigates to that room, or names the code it rejected. Accepts a `?code=` prefill. |
| `lib/quorum_web/live/attendee_live.ex` | `/r/:code`. The student's phone-first feed: compose a question, upvote, retract your own. Holds a voted row in place while the reader reads it and offers a resort with a count of what rose above. Keeps an unsent draft on the server so a reconnect restores it. Follows the room's own limits: the composer's length, whether a name can be attached, and how many the student has left. A question the room holds appears here for its asker alone, marked as waiting, and can be retracted from there. |
| `lib/quorum_web/live/host_live.ex` | `/host/:host_token`. The presenter's console as a full page: site shell, room bar with rename and the live counts, the joining panel (large while the room is empty, a strip once questions arrive), ranked queue, the review queue that appears above it while anything is held, and a rail carrying what's on the projection, the before-you-start checklist, and the keyboard map. Keyboard: **J**, **K**, **Enter**, **A**, **H**, Escape. |
| `lib/quorum_web/live/projection_live.ex` | `/host/:host_token/project`. The screen at the front of the hall. Joining owns the screen until a question is spotlighted, then shrinks to a 268px rail. Takes its gradient, angle, and drift from the room, so the Appearance tab changes what the hall sees. Keyboard: **L**, **D**, **Q**. Renders the QR code server-side. |
| `lib/quorum_web/live/settings_live.ex` | `/host/:host_token/settings/:tab`. Six categories on a rail: Room, Questions, Moderation, Readings and AI, Projection, Appearance. Every control saves on change, so there is no save button; the status line has its height reserved so the first save doesn't move the buttons under the pointer. Five panes are drawn; Projection says what will go in it rather than showing an empty box. Deleting a room needs the session closed and its name typed. |
| `lib/quorum_web/controllers/page_controller.ex`, `page_html.ex`, `page_html/*` | `/`, `/privacy`, `/accessibility`, `/contact`. The landing page plus the three standing pages the footer links to. The contact form is guarded by a honeypot and a per-session cooldown. |
| (landing template) | `/`. The landing page: hero with a code field and Start a room, the demo band, how it works, the reading-pointer illustration, the capability columns, and the closing call to action. Reads the demo room without seeding, so a visit never writes. `page_html.ex` carries `word/1`, `count/3`, and `qr/2`. |
| `lib/quorum_web/controllers/room_controller.ex` | `GET /start` opens a room, owned by the presenter when one is signed in, and redirects to its console. `GET /rooms` lists a presenter's own. |
| `lib/quorum_web/controllers/session_controller.ex`, `session_html.ex`, `session_html/*` | `/sign-in`, `/sign-in/sent`, `/sign-in/:token`, `/sign-out`. Magic-link sign-in for presenters. The check-your-email screen reads the same whether or not the address was known, so it can't be used to find out who has an account. |
| `lib/quorum_web/controllers/demo_controller.ex` | `/demo`, `/demo/host`, `/demo/project`. Three doors into the seeded demo session, one per role. Finds or seeds the room, then redirects, so the landing page's links survive a reseed. |

## Web: supporting modules

| File | Role |
|---|---|
| `lib/quorum_web/brand.ex` | The Quorum logo as an HTML component, in light and on-dark variants. HTML rather than an SVG file, because an SVG loaded through `<img>` cannot resolve the page's webfonts. |
| `lib/quorum_web/browser_token.ex` | Plug that gives each browser an opaque session token. That token is what makes a vote idempotent and lets a student retract their own question, with no sign-up. |
| `lib/quorum_web/landing_examples.ex` | The twenty sample questions the landing page's feed card cycles through, half named and half anonymous, plus the phrasing for an age between 30 seconds and 15 minutes. |
| `lib/quorum/contact.ex` | The contact form's validation and delivery. Mail goes from Quorum's own address with the sender on `reply-to`, so it doesn't fail SPF or DKIM at the receiving end. |
| `lib/quorum_web/shell.ex` | The site header and footer. Nav entries render only when the page behind them exists, so the header never offers a link that goes nowhere. |
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
| `assets/css/shell.css` | The page shell: site header and footer, the room bar, the console's two-column frame, the joining panel and strip, the queue rows, the sign-in split, the standing pages' prose column, and the settings rail, panes, switch, colour pickers, and reading list. Carries the breakpoints that collapse all of them to one column, where the settings rail becomes a scrolling strip with a faded trailing edge. |
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

## Launchers

| File | Role |
|---|---|
| `launch.sh` | Checks Elixir and PostgreSQL, stops a stale server started from this directory, fetches deps, sets up the database, finds a free port, opens a browser, and runs the server. |
| `launch.command` | macOS double-click wrapper around `launch.sh`. |
| `launch.bat` | Windows equivalent. |

## Tests

| File | Role |
|---|---|
| `test/quorum/accounts_test.exs` | The magic-link rules: registration, case-insensitive addresses, the cooldown, single use, expiry, and one presenter's link never signing in another. |
| `test/quorum_web/controllers/session_controller_test.exs` | The sign-in screens and the whole loop: the disabled SSO control with its microcopy, the email it sends, a refused address, no second email inside the cooldown, sign-in, sign-out, and a presenter seeing only their own rooms. |
| `test/quorum/sessions_test.exs` | Adversarial suite over the Sessions resources: validation failures, anonymity, vote dedup, status transitions, ranking, spotlight, and live-update broadcasts. |
| `test/quorum_web/live/join_live_test.exs` | The join screen: label, prefill, unknown code, and navigation however the code was typed. |
| `test/quorum_web/live/attendee_live_test.exs` | The student feed: posting, draft retention, retraction limited to the author, voting and unvoting with the word "Voted" present, the answered list, the closed room, and live arrival. Then the room's limits: a refusal past the length, a refusal past the allowance, the count of what's left, a name dropped when signing is off, and the whole held-question path from posting to approval. |
| `test/quorum_web/live/host_live_test.exs` | The console: ranking, spotlight and clear, answer and reopen, hide, search and tally, the close dialog including Escape, the keyboard shortcuts, live arrival, and the review queue: counting, approving, refusing, a held question from another room, and a held question refused the projection. |
| `test/quorum_web/live/projection_live_test.exs` | The projection: the waiting screen, the spotlight swap, attribution and vote pluralisation, **L** / **D** / **Q**, and the tally. |
| `test/quorum_web/live/settings_live_test.exs` | The settings screens: the rail and its URLs, an unknown tab, the undrawn panes, saving without a save button, the appearance controls reaching the projection, Reset this tab, adding, searching, and removing readings, one room's readings never showing in another's, the question limits reaching the student's composer, the moderation switch and its held words, and the delete guard from the disabled control through the typed name. |
| `test/support/fixtures.ex` | `room/1`, `question/3`, and `votes/2` builders, so tests read as scenarios. |
| `test/support/conn_case.ex`, `data_case.ex` | Test case templates with the Ecto sandbox. |
| `test/quorum_web/controllers/page_controller_test.exs` | The landing page: both entry points, every section, the three demo roles, the sample code when no demo room exists, and the live code and counts when one does. |
| `test/quorum_web/controllers/demo_controller_test.exs` | The demo doors: seeding on first use, all three reaching the same room, reuse on a second visit, reseeding after a clear, and a presenter's own room never being mistaken for the demo. |
| `test/quorum_web/controllers/error_html_test.exs`, `error_json_test.exs` | Error view tests. |
