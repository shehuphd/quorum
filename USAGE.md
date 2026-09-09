# Quorum usage

Last updated: 2026-09-09 20:30:00 UTC

Quorum runs one lecture at a time as a room. A lecturer opens the room, projects it, and answers the questions students rank from their seats.

## Prerequisites

- Elixir (`elixir --version`)
- PostgreSQL, running and reachable (`pg_isready`)

## Setup and run

```bash
./launch.sh
```

The launcher checks both prerequisites, fetches dependencies, creates and migrates the database, frees a port, and opens a browser. macOS users can double-click `launch.command` instead; Windows users can double-click `launch.bat`.

To run the steps by hand:

```bash
mix setup       # fetch deps, create and migrate the database, build assets
mix test        # run the test suite
mix phx.server  # start the app on http://localhost:4000
```

## A demo lecture

The landing page carries a demo band that opens one seeded lecture in any of three roles. The same three doors work directly:

| Route | Opens |
|---|---|
| `/demo` | The student feed |
| `/demo/host` | The lecturer's console |
| `/demo/project` | The projection |

The first visit seeds the room, the rest reuse it. Open two of them side by side and watch a vote in one move the queue in the other.

From the command line:

```bash
mix quorum.demo
```

That prints the demo lecture's join code and its three links, seeding the room if none is open. `--fresh` closes the old room and seeds a new one; `--name "Your lecture"` does the same under a different title.

## The screens

| Screen | Route | Who opens it |
|---|---|---|
| Landing | `/` | Anyone |
| Sign in | `/sign-in` | Lecturers, optional |
| Your rooms | `/rooms` | Signed-in lecturers |
| Demo lecture | `/demo`, `/demo/host`, `/demo/project` | Anyone, in any of the three roles |
| Join | `/join` | Students without the QR code |
| Student feed | `/r/:code` | Students, usually by scanning |
| Host console | `/host/:host_token` | The lecturer |
| Projection | `/host/:host_token/project` | The lecturer, on the projector |
| Settings | `/host/:host_token/settings` | The lecturer |

`GET /start` opens a new room and redirects to its console. The host token in that URL is the only credential, so treat the console link as private and project only the `/project` page.

### Signing in

Sign-in is for lecturers, and it's optional: `/start` opens a room without one, and the host link works either way. Signing in adds `/rooms`, a list of the rooms you opened.

Enter a work email at `/sign-in` and Quorum sends a single-use link that expires in 15 minutes. Asking again within 30 seconds sends nothing, and the screen says how long is left. In development the email goes to the local mailbox at `/dev/mailbox` instead of out to the internet.

Single sign-on appears on the page but is disabled, with microcopy saying what turns it on: an institution's provider being connected.

### Host console

The room bar carries the room's name with a Rename control, the live counts, Open projection, and Close session. While nobody has posted, the joining panel takes the space with the QR code, the join code, Copy student link, and New code. New code issues a fresh one and the old code stops working, for a code shown to the wrong room. Once a question arrives the panel shrinks to a strip and the queue takes over.

The queue is ranked by votes, oldest first within a tie. Each row carries three controls: **Spotlight** puts the question on the projection, **Mark answered** moves it to the answered list and closes voting on it, and **Hide** takes it off both lists. Answered questions can be reopened.

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

### Projection

With nothing spotlighted, the QR code and the five-character join code own the screen. Spotlighting a question shrinks the joining panel to a rail on the left and shows the question at headline scale, with who asked it and its vote count.

| Key | Action |
|---|---|
| **L**, **D** | Toggle between a lit hall and a dark one. Either key flips it, so reaching for the wrong one still works. Dark is the default |
| **Q** | Hide the spotlight and give the screen back to joining |

The footer counts the students connected and the questions asked.

### Settings

Settings open from the console at `/host/:host_token/settings`, with six categories on a rail. Each has its own URL, so a tab can be linked or reloaded.

Every control applies as you change it. There is no save button, and the line beside the buttons says "Saving", then "All changes saved". Its height is reserved, so the first save doesn't move the buttons under your pointer.

| Tab | What it does |
|---|---|
| Room | The room's name, when it closes itself, the join code, and deleting the room |
| Questions | Not drawn yet |
| Moderation | Not drawn yet |
| Readings and AI | The approved reading list, and whether students are pointed at it |
| Projection | Not drawn yet |
| Appearance | The projection's colours |

The three undrawn tabs say what will go in them and that nothing is missing from your room meanwhile, rather than showing an empty pane.

**Appearance** sets the two gradients the projection uses, one for a lit hall and one for a dark one, the angle between them, and whether the gradient drifts. A preview stands beside the controls, and one link puts the whole tab back to its defaults. Drift stops on its own for anyone who has asked for reduced motion.

**Readings and AI** holds the room's approved reading list: a title, optionally where in it, and optionally a link. When the reading pointer is on, a student who posts a question is shown items from this list and nothing else. Matching arrives with the model work; the list is stored and ready for it. The list belongs to the room and goes when the room does.

**Deleting a room** needs the session closed first, and then the room's name typed to confirm. It takes the room, its questions, and its votes. The server checks both conditions rather than trusting the disabled button.

### Student feed

Students post a question, optionally with a name, and upvote anything already asked. A vote holds that row in place while they read, with a **Let it move** control and a count of how many questions have risen above it, so the list never reorders under a thumb.

Students can retract their own questions. A question they upvoted reads "Voted" in words, not colour alone.

## The domain

The `Quorum.Sessions` domain exposes four resources through Ash actions:

- `Room`: `open` a room (returns a join code and a host token), then `close` it. `spotlight` and `clear_spotlight` drive the projection. `settings` applies one settings change. `demo?` marks the room the landing page points at.
- `Question`: `ask` in a room, then `answer`, `hide`, or `restore`.
- `Vote`: `cast` an upvote (idempotent per browser); destroy a vote to unvote.
- `Reading`: `add` an item to a room's approved list, then `edit` or destroy it.

Subscribe a process to a room's live feed with `Quorum.Sessions.subscribe(room_id)`; every change to that room delivers `{:room_changed, room_id}` so a view can reload its ranked questions.
