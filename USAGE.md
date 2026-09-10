# Quorum usage

Last updated: 2026-09-10 16:10:13 UTC

Quorum runs one live session at a time as a room. A presenter opens the room, projects it, and answers the questions students rank from their seats.

## Prerequisites

- Elixir (`elixir --version`)
- PostgreSQL, installed (`pg_isready`). The launcher starts it if it isn't running.

## Setup and run

```bash
./launch.sh
```

The launcher checks both prerequisites, fetches dependencies, creates and migrates the database, frees a port, and opens a browser. If PostgreSQL is installed but stopped, it starts it: Postgres.app's own server, a Homebrew service, or a cluster named by `PGDATA`, in that order. It never uses sudo, so where a privileged service manager is the only route it prints the command instead of running it. macOS users can double-click `launch.command` instead; Windows users can double-click `launch.bat`.

To run the steps by hand:

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

## A demo session

The landing page carries a demo band that opens one seeded session in any of three roles. The same three doors work directly:

| Route | Opens |
|---|---|
| `/demo` | The student feed |
| `/demo/host` | The presenter's console |
| `/demo/project` | The projection |

The first visit seeds the room, the rest reuse it. Open two of them side by side and watch a vote in one move the queue in the other.

From the command line:

```bash
mix quorum.demo
```

That prints the demo session's join code and its three links, seeding the room if none is open. `--fresh` closes the old room and seeds a new one; `--name "Your session"` does the same under a different title.

## The screens

| Screen | Route | Who opens it |
|---|---|---|
| Landing | `/` | Anyone |
| Sign in | `/sign-in` | Presenters, optional |
| Your rooms | `/rooms` | Signed-in presenters |
| Archive | `/archive` | Signed-in presenters |
| Demo session | `/demo`, `/demo/host`, `/demo/project` | Anyone, in any of the three roles |
| Join | `/join` | Students without the QR code |
| Student feed | `/r/:code` | Students, usually by scanning |
| Host console | `/host/:host_token` | The presenter |
| Projection | `/host/:host_token/project` | The presenter, on the projector |
| Settings | `/host/:host_token/settings` | The presenter |

`GET /start` opens a new room and redirects to its console. The host token in that URL is the only credential, so treat the console link as private and project only the `/project` page.

### Signing in

Sign-in is for presenters, and it's optional: `/start` opens a room without one, and the host link works either way. Signing in adds `/rooms`, a list of the rooms you opened.

Sign-in is a stub for this demo build, not a live credential. The page at `/sign-in` has one access code field, and the code is shown as the field's own placeholder, so the hint and the key are one value: type what's in the box and you're in as the shared demo presenter. No email is sent. The code defaults to `showtime` and is set per event with the `QUORUM_DEMO_CODE` environment variable. The magic-link machinery stays in the code, dormant, for a later build that authenticates presenters.

Single sign-on appears on the page but is disabled, with microcopy saying what turns it on: an institution's provider being connected.

### Joining

`/join` asks for the five characters on the wall, one per slot, with the caret on the slot the next character goes in. Scanning the QR code skips the screen; typing `/join?code=K7QM4` fills it in.

The fifth character resolves the room, and the screen changes to it: the session's name at the top, a live line counting who is already in and how many questions they have asked, the room's own gradient behind it all, and only then a way in. A code that matches nothing says so and names what it rejected. A session that has closed says that too, and offers what was asked rather than a way in.

**Add a display name** signs what the student posts. The name reaches the feed's composer already filled in, so it's asked for once rather than per question, and it never appears in a URL. Without one, every question is anonymous. The badge in the corner reads back whichever it is.

**See demo** opens the seeded session for anyone with no code to type.

### The archive

`/archive` is what a term of sessions adds up to. Every session you have run is listed newest first, with the questions it drew ranked the way the hall ranked them, so the page reads as the record of what didn't get through: which weeks drew nothing, which drew the same question five times, what belongs in the next tutorial.

Above them, four figures: sessions run, questions asked, how many you answered in the room, and the most any one session drew, with the session named.

The search runs over every question in every session at once, because the point is the thread that runs through a term rather than one week's list. Beside it, a filter down to one session and an order: most voted, or newest. A session with more than five questions shows its top five and expands.

Questions held for review and never approved, and questions you hid, are left out. A question the room never saw isn't part of what the room asked.

**Download CSV** hands over the same thing as a file: one row per question, with its session, date, votes, status, and who asked.

### Host console

The room bar carries the room's name with a Rename control, the live counts, Open projection, and Close session. While nobody has posted, the joining panel takes the space with the QR code, the join code, Copy student link, and New code. New code issues a fresh one and the old code stops working, for a code shown to the wrong room. Once a question arrives the panel shrinks to a strip and the queue takes over.

The queue is ranked by votes, oldest first within a tie. Each row carries three controls: **Spotlight** puts the question on the projection, **Mark answered** moves it to the answered list and closes voting on it, and **Hide** takes it off both lists. Answered questions can be reopened.

With the AI service running, spotlighting a question also starts a suggested answer drafting. It appears in the rail beside the queue, marked as the AI's, and nobody but you ever sees it: the model advises, you answer. A question keeps its draft, so a second spotlight costs nothing.

The search field filters the queue as you type and reports how many of the room's questions match. Escape clears it. The queue shortcuts below don't fire while you're typing in it.

Keyboard shortcuts, with no modifier:

| Key | Action |
|---|---|
| **J**, **K** | Move down and up the queue |
| **Enter** | Spotlight the selected question |
| **A** | Mark the selected question answered |
| **H** | Hide the selected question |
| **Escape** | Cancel the close-session dialog |

Closing the session stops posting and voting. Students keep reading what's there. The dialog asks first, and Escape or **Keep it open** backs out.

A room can also close itself. **Close automatically at** on the Room settings tab takes a time on your own clock, and the room closes on the same terms as the button: posting and voting stop, and a room set not to keep its questions loses them then. It's checked every minute, so the close comes within a minute of the time you set.

### Projection

With nothing spotlighted, the QR code and the five-character join code own the screen. Spotlighting a question shrinks the joining panel to a rail on the left and shows the question at headline scale, with who asked it and its vote count.

| Key | Action |
|---|---|
| **L**, **D** | Toggle between a lit hall and a dark one. Either key flips it, so reaching for the wrong one still works. Dark is the default |
| **Q** | Hide the spotlight and give the screen back to joining |

The footer counts the students connected and the questions asked.

The hall belongs to the room rather than to the screen showing it, so it survives a reload, a second projector follows the first, and the join page in every student's hand takes the same one.

### Settings

Settings open from the console at `/host/:host_token/settings`, with seven categories on a rail. Each has its own URL, so a tab can be linked or reloaded.

Every control applies as you change it. There is no save button, and the line beside the buttons says "Saving", then "All changes saved". Its height is reserved, so the first save doesn't move the buttons under your pointer.

| Tab | What it does |
|---|---|
| Room | The room's name, when it closes itself, the join code, and deleting the room |
| Questions | What a student may post |
| Moderation | Whether questions wait for you before the room sees them |
| Readings | The approved reading list, and whether students are pointed at it |
| Projection | What the screen at the front puts on the wall |
| Appearance | The projection's colours |
| API keys | Provider keys, the model each uses, and what the AI has spent |

**Questions** sets the longest a question may be (140, 280, 500, or 1000 characters), how many a student can have waiting at once, and whether students may sign what they post. The composer follows all three. Answered and hidden questions stop counting against their asker, so a student who's been answered can post again. Turning signing off posts every question anonymously, including any name an old page still sends.

The same tab decides what happens to the questions when the session ends. **Keep this room's questions** is on, because a term of them is the record of what didn't get through: which weeks drew nothing, which drew the same question forty times, what belongs in the next tutorial. Turning it off deletes every question in the room, and its votes, the moment you close the session, with no undo.

**Projection** sets what the screen at the front shows. Question size runs from Small, for a seminar room or a question you'd rather not have wrapping, through Standard, which is readable from the back of a full hall, to Largest. Under the question you can show or hide who asked and how many voted; with both off there's no line at all. Around it, the join code can stay in a rail beside a spotlighted question for anyone arriving late, and the connected and asked counts can come off the bottom. Colours are on the Appearance tab. Every change reaches the projection live, so you can leave it running while you set it.

**Moderation** decides what reaches the room. Five things can hold a question, and any one of them is enough:

| Trigger | Holds when |
|---|---|
| Hold every question for review | Always, until you approve each one |
| Hold a student's first question | The asker has had nothing approved in this room yet |
| Hold anything with a link | The question carries a web address or a bare domain |
| Held words | The question uses a word you've put on the room's list |
| Reads as aimed at the AI | A model reads the text as instructions to an AI system, rather than a question for you |

A room starts with a list of twenty held words, profanity and insults, so it isn't ungated on day one. The words are one comma-separated field: add one by typing a comma and the word, remove one by deleting it, empty the field to hold nothing. Clicking away saves, and the field reads back lowercased, deduplicated, and alphabetical, however you typed it.

Every one of them holds rather than refuses, so the worst a mistake costs an asker is a wait. That's what lets the list stay blunt: a question citing Dr. Dick Rittmann's paper gets held, you glance at it, you approve it. Held words match whole words, so "ass" doesn't catch "class". The link check ignores file names, so a question about Node.js goes straight through.

Holding a student's first question reads trust per room, because students have no accounts here: the only history a room can see is what that browser has had approved in it. Approve one of someone's questions and the rest go through.

If you're signed in, **Start the rooms I open with the first of these on** makes holding your default. It seeds a new room only, so changing it never rewrites a session already running.

The fifth trigger needs the AI service running, and it works the other way around from the rest: every question is held for a moment while a model reads it, a clean read releases it on its own within a few seconds, and only the ones read as aimed at the AI stay for you. Questions about AI go straight through; it's instructions to the machine the screen is for. It's on by default, since a room can be opened to anyone with the link, and you can turn it off per room. While the service is down the switch holds nothing.

Underneath the switch, and whatever it's set to, the blatant attempts are caught for free: an "ignore previous instructions" opener, a demand to print the system prompt, a chat-role marker pasted into the body. These are held for you without a model reading them, and the text is cleaned of the invisible characters used to hide such wording before anything, a person or a pattern, reads it. This runs whenever the AI service is up, so an open room still has a floor under it even with the screen turned off.

A held question is invisible to the room and to the projection. Its own asker sees it waiting, and can retract it, so nobody posts the same question twice thinking the first one failed. While anything is held, the console carries a review queue above the ranked queue, with **Approve** to send a question to the room and **Refuse** to hide it, and each row says why it's waiting. A refused question is hidden rather than deleted, so you can restore it.

**Appearance** sets the two gradients the projection uses, one for a lit hall and one for a dark one, the angle between them, and whether the gradient drifts. A preview stands beside the controls, and one link puts the whole tab back to its defaults. Drift stops on its own for anyone who has asked for reduced motion.

**Readings** holds the room's approved reading list: a title, optionally where in it, and optionally a link. When the reading pointer is on and the AI service is running, a student who posts a question is shown up to two items from this list under their own question, and nothing else: the list is the only corpus the model may pick from, and picking nothing is allowed. The list belongs to the room and goes when the room does.

**Deleting a room** needs the session closed first, and then the room's name typed to confirm. It takes the room, its questions, and its votes. The server checks both conditions rather than trusting the disabled button.

### Student feed

Students post a question, optionally with a name, and upvote anything already asked. A vote fills the vote box and moves the count, and that's all it does: the list ranks live, so a row can move as the room votes.

To keep track of one question through that, press the pin to the left of its vote box. Pinned questions rise to the top of that student's own list, ranked among themselves by votes, and the only mark on them is the pin itself, filled in: nothing else about the row changes, and nobody else's ranking does either. The pin appears on hover where there's a pointer, and stands there on a phone.

**Post question** stays grey until there's something in the box.

The feed carries the site header and footer, so the Quorum mark goes home and **Change room** leads to another session's code.

Pressing **Post question** doesn't write it yet. The composer is replaced by the question, a bar that burns down over ten seconds, and a **Cancel** button counting the seconds off. That window is for the student who spots the same question already in the list, catches a typo, or thinks better of it. Cancelling writes nothing at all: the text goes back in the composer, and nobody saw it. **Send it now** skips the wait.

Students can retract their own questions.

When the room holds questions for review, a student's own held question appears under "Waiting for your presenter" with a note that nobody else can see it yet. They can retract it from there.

## The AI service

Everything above that mentions the AI runs through one small service beside the app, and none of it happens without it: no keys in Quorum, no calls from Quorum, and every feature off until the service is up.

```bash
# 1. Put a provider key in project/keys.toml (the file is gitignored)
# 2. Start the sidecar; it prints the token Quorum needs
./sidecar/run.sh
# 3. Start Quorum with that token in the same variable
QUORUM_SIDECAR_TOKEN=<printed value> ./launch.sh
```

The key file is KeyCall's own TOML shape, so `keycall verify --source ./project/keys.toml` checks the same file the sidecar reads. Providers are data: add a `[[targets]]` entry and it's available, and no provider is named anywhere in Quorum.

You don't have to edit the file by hand. The **API keys** settings tab manages it once the service is up: pick a provider, paste a key, and the key is tested against the provider the moment you stop typing. A key that answers is stored and confirmed ("Key accepted: 12 usable models."); one the provider refuses is never stored, and the tab shows the provider's own message. A stored key renders as its first four characters and asterisks, and can't be read back out, only replaced or removed.

Each key normally runs on the newest model that answers, chosen from the provider's live catalog. The picker beside a key pins one instead, offering only models the key can use for text: nothing deprecated, no image or embedding models.

Every model call is recorded: what it was for, which provider and model answered, the tokens it spent, what those tokens cost in dollars, and how long it took, kept per presenter. The same tab shows the running total, calls, tokens in, tokens out, dollars, split by purpose, with a button that clears the counter. Prices come from the [rates](https://pypi.org/project/rates/) ledger, matched on the exact model id the provider answered with; a model the ledger doesn't know yet counts tokens only, and the tab says how many calls the dollar figure covers.

## The domain

The `Quorum.Sessions` domain exposes four resources through Ash actions:

- `Room`: `open` a room (returns a join code and a host token), then `close` it. `spotlight` and `clear_spotlight` drive the projection. `settings` applies one settings change. `demo?` marks the room the landing page points at.
- `Question`: `ask` in a room, then `approve`, `answer`, `hide`, or `restore`. A question the room's moderation holds is written with status `:pending` and reaches nobody but its asker until it's approved.
- `Vote`: `cast` an upvote (idempotent per browser); destroy a vote to unvote.
- `Reading`: `add` an item to a room's approved list, then `edit` or destroy it.

Subscribe a process to a room's live feed with `Quorum.Sessions.subscribe(room_id)`; every change to that room delivers `{:room_changed, room_id}` so a view can reload its ranked questions.
