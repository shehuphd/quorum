# Architecture

This document describes how Quorum is built: its structure, the domain resources, the data store, and the path a change takes through the system.

## STRuFOL

[S]hape, [T]echnical stack, [Ru]n details, [F]ailure modes, [O]bservability, [L]imitations.

### Shape

Quorum is a live audience engagement tool. Its first use case is university teaching. Students join a session by scanning a projected QR code, then submit and upvote questions from their seats; the presenter answers the top-ranked ones and closes the session. The interactive UI renders server-side over websockets via Phoenix LiveView.

Five screens make up the product. The projection, the console, and the settings belong to the presenter, behind a secret host token. The join screen and the student feed are public to anyone holding the five-character code.

Settings are per-room rather than per-account, so they follow the host token like the rest of the presenter's tools, and a room carries its own look, its own reading list, and its own rules about what students may post and what reaches the room.

Moderation is post-hoc by default: a question appears and the presenter can hide it. A room can switch to pre-publish, where a question is written with a `pending` status and reaches nobody but its own asker until the presenter approves it. Because a held question exists as a row rather than being refused, the asker can see it waiting and retract it, and an approval is one status change rather than a re-post.

A new room starts with twenty held words so it isn't ungated on day one; the list is a starting point a presenter edits, not a policy. Four triggers feed that one decision, resolved by `Sessions.hold_reason/3`: the room holds everything, the asker has had nothing approved in this room, the body uses a held word, or the body carries a link. Students have no accounts, so the second reads trust per room from what that browser has had approved in it. Every trigger holds and none refuses, which keeps the cost of a false positive to a wait and means the triggers can be blunt without being punitive.

Questions outlive the session. A term of them is the record of which material didn't land, which is what a room is kept for rather than a default nobody chose, so retention is on unless a room turns it off. A room that does has its questions and votes deleted when the session closes.

Presenter accounts are optional and stand beside the host token rather than replacing it: a room opened while signed in belongs to that presenter and appears in their list, and every host link keeps working with or without an account. Students never have an account at all. Signing in is a demo stub for now, one access code shown as the field's own placeholder, with the magic-link machinery kept underneath it for a build that authenticates presenters.

A landing page at `/` fronts all of it, and a seeded demo session behind `/demo`, `/demo/host`, and `/demo/project` opens the same room in each of the three roles, so the product can be looked at without a room of your own to run.

### Technical stack

- Elixir on the BEAM (Erlang VM)
- Phoenix web framework, with LiveView for all five screens and a plain controller for the landing page
- Ash for the domain layer, resources grouped under `Quorum.Sessions` and `Quorum.Accounts`
- Ecto with PostgreSQL for persistence, through `Quorum.Repo` (an `AshPostgres.Repo`)
- Phoenix.PubSub (`Quorum.PubSub`) for live updates, driven by an Ash notifier
- Phoenix.Presence for the connected-student count
- eqrcode for server-rendered QR codes, so the projection needs no client JavaScript to draw one
- A bespoke CSS design system (tokens plus `q-*` components) with Archivo and Literata self-hosted as woff2
- Oban for scheduled and background jobs: one queue, a cron entry that closes rooms whose own clock has run out, and the three AI jobs (pointer, draft, screen)
- AI provider calls through a localhost Python sidecar built on KeyCall (`sidecar/`): Quorum holds no provider keys, speaks HTTP to one normalized `/generate` plus a small key-management API the settings screen drives, and records every call's spend in `ai_calls`, priced in dollars through the rates ledger where it knows the model
- Contact mail through Swoosh, its adapter chosen at boot from what the environment carries: Brevo, Mailgun, or the log when neither has credentials
- Deployed as one container on Azure Container Apps (UK South), image in GHCR, scaled to zero between demos. The Phoenix release runs in the foreground and the Python sidecar in the background of the same container, sharing localhost the way they do on a development machine
- PostgreSQL is Neon's serverless tier in London, over TLS verified against the system CA store, reached on its direct connection string rather than the pooled one

### Run details

#### Plain-English version

A student posts a question to a room. Ash runs the room's `ask` action, which validates the body and writes a row through AshPostgres. Once the write commits, the room's notifier publishes one "this room changed" message on the room's PubSub topic. Every LiveView watching that room, on any device and in any process, receives it and re-reads the room's visible questions ordered by vote count. The presenter's console, the projection, and every student's phone all redraw within the same round-trip, with no page refresh.

An upvote follows the same path: the `cast` action upserts a vote, so a repeat vote by the same browser changes nothing, and the same broadcast reloads every viewer. A vote is tied to an opaque token in the browser's session cookie, which is also what lets a student retract their own question. No sign-up, and no way for one student to see who asked what.

The presenter's actions take the same path. Spotlighting a question writes the pick onto the room, and the projection reloads and swaps its layout because it heard the same broadcast, not because the console told it to.

Settings ride the same path, which is what lets them do without a save button. Changing a colour writes it to the room, and the projection in the hall picks up the new gradient from the broadcast. The settings screen itself takes two renders: the change marks the pane saving and hands the write to the process, and the write's own render reports it saved. That ordering is what keeps the status honest, since it can only say "saved" after the write returned.

#### Technical version

- `Quorum.Sessions.Question` `:ask`, built with `Ash.Changeset.for_create/3` and run by `Ash.create/1`
- validation and the insert run through `AshPostgres.DataLayer` against `Quorum.Repo`
- after commit, `Quorum.Sessions.Broadcaster.notify/1` calls `Phoenix.PubSub.broadcast/3` on `Quorum.Sessions.topic(room_id)` with `{:room_changed, room_id}`
- every LiveView subscribes in `mount/3` via `Quorum.Sessions.subscribe/1` and reloads in a single `handle_info/2` clause, since the message names the room rather than a delta
- an upvote takes `Quorum.Sessions.Vote` `:cast`, an upsert on the `unique_vote` identity; the notifier loads the vote's question to resolve its room, then broadcasts
- `QuorumWeb.BrowserToken` puts an opaque token in the session on the first request; `AttendeeLive` reads it in `mount/3` and passes it as the `voter_token` and `submitter_token`
- `QuorumWeb.Presence.track/3` in `AttendeeLive`'s mount, `Presence.list/1` in the console and projection, both keyed on the same room topic
- the LiveViews call only `Quorum.Sessions` functions; no changeset or `Ash.Query` is built in the web layer

### Failure modes

| Cause | Handling |
|---|---|
| Empty or over-length question body | The composer refuses to submit an empty body, and Ash validation rejects an over-length one; either way the draft stays in the box and a status line says the question wasn't posted |
| Question with no room or no submitter token | `allow_nil? false` rejects it before insert |
| Same browser votes twice | The `unique_vote` identity plus an upsert make the second vote a no-op, not an error and not a duplicate row |
| Duplicate join code or host token | Unique identities reject the collision; a room open fails rather than shadowing an existing room |
| Unknown join code | The join screen names the code it rejected; a bad code in a `/r/:code` URL redirects back to join with that code prefilled |
| Unknown host token | The console and the projection each render a plain "that host link doesn't match a room" instead of crashing the LiveView |
| A spotlighted question is deleted | The foreign key nilifies `rooms.spotlight_question_id`, so the projection falls back to the joining screen rather than pointing at a missing row |
| The list reorders under a reader's thumb | A voted row is held in its position and the feed offers a resort with a count of what rose above it, rather than moving content the reader is looking at |
| PubSub message missed, or a viewer joins late | The broadcast names the room, not a delta, so a reload reconstructs the correct state; a missed message costs at most one stale render until the next change |
| Websocket drops | LiveView reconnects and remounts; the student's unsent draft is held in the LiveView's own assigns and comes back with it |
| The demo room is closed or missing | `Demo.ensure_room/0` seeds a new one on the next visit, so `/demo` never reaches a dead link. The landing page reads without seeding, so a page view never writes |
| A sign-in link is clicked twice | The first click spends it; the second says the link has been used, told apart from one that never existed because spent tokens are kept rather than deleted |
| A sign-in link is clicked after 15 minutes | It's refused as expired, with a control to ask for another |
| Someone asks for link after link | A 30-second cooldown returns the same "check your email" screen and sends nothing, so the address can't be mailed repeatedly |
| An address is probed to see who has an account | The screen after a request reads the same whether or not the address was known |
| A presenter's account is deleted | `rooms.owner_id` is nilified rather than cascading, so their rooms stay reachable by host link instead of disappearing |
| A student posts, then sees the same question already asked | Posting opens a ten-second window before anything is written. Cancelling inside it writes nothing at all, so there's no row to retract and no other student saw one |
| A student's browser drops mid-window | The question was never written, and isn't. The window lives in the LiveView's own process, so leaving takes the pending question with it |
| A session closes mid-window | The reload that closes the room drops the pending question and says so, rather than counting down against a room that can't take it |
| A question arrives at a closed session | `Sessions.ask/2` refuses it. The composer is already hidden, so this catches a stale page or a question written at the end of its window |
| A question is longer than the room allows, or the student is at their allowance | `Sessions.ask/2` refuses before the write and names which limit stopped it, so the composer says the length or the allowance rather than "couldn't be posted". These are per-room, so they can't be resource constraints |
| A crafted request tries to post past a review queue | `status` is never accepted from the client. The `ask` action derives it from a `held?` argument the domain computes from the room's own settings |
| A crafted request tries to project a held question | `Sessions.spotlight/2` refuses anything the room can't already see, so holding a question back means the hall and not only the queue |
| A student's held question looks like it failed to post | The asker sees their own held question waiting, with a note that nobody else can see it yet, and can retract it from there. Other students see nothing |
| A held word is used innocently | A held word holds the question rather than refusing it, and matches whole words, so "class" doesn't trip "ass". The cost of a false positive is a wait |
| A question names a file, not a website | The link check reads a scheme, a `www` host, or a bare domain, and ignores a set of extensions that read as domains. A session on Node.js doesn't hold every question that names it |
| A presenter's default changes mid-term | The account preference seeds a room at the moment it's opened. A room already running keeps its own setting, so no session changes under the person giving it |
| A student retracts a question others upvoted | The votes foreign key cascades, so the votes go with the question. Before it did, one upvote made a question undeletable |
| A room is set to discard its questions | They go when the session closes, with their votes, and the room itself survives so its link still opens. There's no undo, and the setting says so |
| A room is deleted while it's still running | Deleting needs the session closed and the room's name typed, and the action checks both server-side rather than trusting the disabled button |
| A room is deleted with readings on it | `readings.room_id` cascades, so the list goes with the room rather than outliving it |
| A settings write fails | The status line stays on "Saving" rather than claiming a save that didn't happen, because it only reports saved once the write returns |
| A key event in a text field triggers a shortcut | An element carrying its own `phx-keyup` takes the event and the window binding doesn't fire, so typing "j" in a search box filters instead of moving the queue. Fields without one stop the event themselves |
| Database unreachable | Ash returns a transport error from the action; nothing is silently swallowed |
| The demo is open and the provider keys behind it are live | Every model call goes through `AI.generate/3`, which refuses once a rolling day has used either ceiling: dollars, or a count of calls. Two of them because the ledger can't price a model it doesn't know, so an unpriced call would cost nothing against a dollar limit and could be used to walk past it. The features degrade to nothing, the way they do when the sidecar is down |
| A mail provider is unreachable, refuses the key, or has no process behind it | `Contact.deliver/1` catches exits as well as exceptions, so a send that fails returns an error instead of taking the request down. The page says the message didn't send and keeps what was typed, and the log carries the provider's own words |
| A provider accepts the API call and rejects the send later | Nothing synchronous can catch this: the call returns a message id and the rejection follows, so the page says sent. The provider's own event log is where it shows, which is the first place to look when a message never arrives |
| The contact form is used repeatedly, or from many sessions | A honeypot answers a bot with success and sends nothing. Beyond that the wait is held server-side in `Quorum.Contact.Limit`, keyed on the address the ingress recorded, so clearing cookies doesn't reset it: one message per address every five minutes, and twenty an hour across everyone, which also keeps a flood inside a provider's free allowance |
| Migrations run against a pooled Postgres connection | They'd hang or fail on the advisory lock a transaction-mode pooler can't hold, so the deployment uses Neon's direct connection string |
| The deployed host doesn't match `PHX_HOST` | The endpoint's origin check refuses the websocket, which reads as a page that loads and never goes live, so the host is computed from the Container Apps environment when the app is created |

### Observability

- Ecto logs every query with timings in dev, so the SQL a run issued is visible without adding print statements
- The ExUnit suite drives every resource action against a live database, and the LiveView suite drives all five screens through `Phoenix.LiveViewTest`, asserting the rendered outcome rather than internal state
- Sign-in emails land in the local mailbox at `/dev/mailbox` in development, so the link is readable without a mail provider
- Every page is measured at 375px, 768px, 1280px, and 1600px, asserting `scrollWidth <= clientWidth` and that no control's target falls under 44px, rather than eyeballed. `Phoenix.LiveViewTest` dispatches events straight to the server, so anything that can go wrong between a browser's key press and the socket has to be measured in a browser
- `Phoenix.LiveDashboard` is mounted for process, memory, and query inspection
- In the deployed container both processes log to the same stream, so the Phoenix release and the Python sidecar interleave under `az containerapp logs show` and a boot problem in either is visible in one place
- Contact mail that a provider refuses is logged with the provider's reason. What a provider accepts and then rejects is only in the provider's own event log, so that log is part of checking mail works rather than an afterthought
- Telemetry handlers that record each handler's decision arrive when there are decisions to record; today every screen's state is one reload of the same query, which the query log already shows

### Limitations

- Presenter sign-in is a demo stub: one shared access code opens a shared demo presenter. Single sign-on is designed but not built, and the magic-link machinery underneath doesn't send to arbitrary addresses.
- Students have no accounts at all: identity, votes, retraction rights, and per-room trust all hang off an opaque token in the browser's session cookie, so a cleared cookie or a different device is a new student.
- The AI features depend on the localhost Python sidecar holding the provider keys; when it's down or unkeyed they stand down to nothing rather than degrading.
- The deployment is one container scaled to zero between demos, so it isn't provisioned for continuous production load, and the first visit after idle waits for the container to start.
- Mail delivery is only observable up to the provider's acceptance: a send the provider accepts and rejects later shows nowhere but the provider's own event log.
