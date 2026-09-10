# Quorum usage

Last updated: 2026-09-10 10:10:00 UTC

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
| Demo session | `/demo`, `/demo/host`, `/demo/project` | Anyone, in any of the three roles |
| Join | `/join` | Students without the QR code |
| Student feed | `/r/:code` | Students, usually by scanning |
| Host console | `/host/:host_token` | The presenter |
| Projection | `/host/:host_token/project` | The presenter, on the projector |
| Settings | `/host/:host_token/settings` | The presenter |

`GET /start` opens a new room and redirects to its console. The host token in that URL is the only credential, so treat the console link as private and project only the `/project` page.

### Signing in

Sign-in is for presenters, and it's optional: `/start` opens a room without one, and the host link works either way. Signing in adds `/rooms`, a list of the rooms you opened.

Enter a work email at `/sign-in` and Quorum sends a single-use link that expires in 15 minutes. Asking again within 30 seconds sends nothing, and the screen says how long is left. In development the email goes to the local mailbox at `/dev/mailbox` instead of out to the internet.

Single sign-on appears on the page but is disabled, with microcopy saying what turns it on: an institution's provider being connected.

### Joining

`/join` asks for the five characters on the wall, one per slot, with the caret on the slot the next character goes in. Scanning the QR code skips the screen; typing `/join?code=K7QM4` fills it in.

The fifth character resolves the room, and the screen changes to it: the session's name at the top, a live line counting who is already in and how many questions they have asked, the room's own gradient behind it all, and only then a way in. A code that matches nothing says so and names what it rejected. A session that has closed says that too, and offers what was asked rather than a way in.

**Add a display name** signs what the student posts. The name reaches the feed's composer already filled in, so it's asked for once rather than per question, and it never appears in a URL. Without one, every question is anonymous. The badge in the corner reads back whichever it is.

**See demo** opens the seeded session for anyone with no code to type.

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

The hall belongs to the room rather than to the screen showing it, so it survives a reload, a second projector follows the first, and the join page in every student's hand takes the same one.

### Settings

Settings open from the console at `/host/:host_token/settings`, with six categories on a rail. Each has its own URL, so a tab can be linked or reloaded.

Every control applies as you change it. There is no save button, and the line beside the buttons says "Saving", then "All changes saved". Its height is reserved, so the first save doesn't move the buttons under your pointer.

| Tab | What it does |
|---|---|
| Room | The room's name, when it closes itself, the join code, and deleting the room |
| Questions | What a student may post |
| Moderation | Whether questions wait for you before the room sees them |
| Readings and AI | The approved reading list, and whether students are pointed at it |
| Projection | What the screen at the front puts on the wall |
| Appearance | The projection's colours |

**Questions** sets the longest a question may be (140, 280, 500, or 1000 characters), how many a student can have waiting at once, and whether students may sign what they post. The composer follows all three. Answered and hidden questions stop counting against their asker, so a student who's been answered can post again. Turning signing off posts every question anonymously, including any name an old page still sends.

The same tab decides what happens to the questions when the session ends. **Keep this room's questions** is on, because a term of them is the record of what didn't get through: which weeks drew nothing, which drew the same question forty times, what belongs in the next tutorial. Turning it off deletes every question in the room, and its votes, the moment you close the session, with no undo.

**Projection** sets what the screen at the front shows. Question size runs from Small, for a seminar room or a question you'd rather not have wrapping, through Standard, which is readable from the back of a full hall, to Largest. Under the question you can show or hide who asked and how many voted; with both off there's no line at all. Around it, the join code can stay in a rail beside a spotlighted question for anyone arriving late, and the connected and asked counts can come off the bottom. Colours are on the Appearance tab. Every change reaches the projection live, so you can leave it running while you set it.

**Moderation** decides what reaches the room. Four things can hold a question, and any one of them is enough:

| Trigger | Holds when |
|---|---|
| Hold every question for review | Always, until you approve each one |
| Hold a student's first question | The asker has had nothing approved in this room yet |
| Hold anything with a link | The question carries a web address or a bare domain |
| Held words | The question uses a word you've put on the room's list |

A room starts with a list of twenty held words, profanity and insults, so it isn't ungated on day one. It's a starting point, not a policy: remove them one at a time, or all at once.

Every one of them holds rather than refuses, so the worst a mistake costs an asker is a wait. That's what lets the list stay blunt: a question citing Dr. Dick Rittmann's paper gets held, you glance at it, you approve it. Held words match whole words, so "ass" doesn't catch "class". The link check ignores file names, so a question about Node.js goes straight through.

Holding a student's first question reads trust per room, because students have no accounts here: the only history a room can see is what that browser has had approved in it. Approve one of someone's questions and the rest go through.

If you're signed in, **Start the rooms I open with the first of these on** makes holding your default. It seeds a new room only, so changing it never rewrites a session already running.

A held question is invisible to the room and to the projection. Its own asker sees it waiting, and can retract it, so nobody posts the same question twice thinking the first one failed. While anything is held, the console carries a review queue above the ranked queue, with **Approve** to send a question to the room and **Refuse** to hide it. A refused question is hidden rather than deleted, so you can restore it.

**Appearance** sets the two gradients the projection uses, one for a lit hall and one for a dark one, the angle between them, and whether the gradient drifts. A preview stands beside the controls, and one link puts the whole tab back to its defaults. Drift stops on its own for anyone who has asked for reduced motion.

**Readings and AI** holds the room's approved reading list: a title, optionally where in it, and optionally a link. When the reading pointer is on, a student who posts a question is shown items from this list and nothing else. Matching arrives with the model work; the list is stored and ready for it. The list belongs to the room and goes when the room does.

**Deleting a room** needs the session closed first, and then the room's name typed to confirm. It takes the room, its questions, and its votes. The server checks both conditions rather than trusting the disabled button.

### Student feed

Students post a question, optionally with a name, and upvote anything already asked. A vote fills the vote box and moves the count, and that's all it does: the list ranks live, so a row can move as the room votes.

To keep track of one question through that, press the pin to the left of its vote box. Pinned questions rise to the top of that student's own list, ranked among themselves by votes, and the only mark on them is the pin itself, filled in: nothing else about the row changes, and nobody else's ranking does either. The pin appears on hover where there's a pointer, and stands there on a phone.

**Post question** stays grey until there's something in the box.

The feed carries the site header and footer, so the Quorum mark goes home and **Enter a code** goes to another session.

Pressing **Post question** doesn't write it yet. The composer is replaced by the question, a bar that burns down over ten seconds, and a **Cancel** button counting the seconds off. That window is for the student who spots the same question already in the list, catches a typo, or thinks better of it. Cancelling writes nothing at all: the text goes back in the composer, and nobody saw it. **Send it now** skips the wait.

Students can retract their own questions.

When the room holds questions for review, a student's own held question appears under "Waiting for your presenter" with a note that nobody else can see it yet. They can retract it from there.

## The domain

The `Quorum.Sessions` domain exposes four resources through Ash actions:

- `Room`: `open` a room (returns a join code and a host token), then `close` it. `spotlight` and `clear_spotlight` drive the projection. `settings` applies one settings change. `demo?` marks the room the landing page points at.
- `Question`: `ask` in a room, then `approve`, `answer`, `hide`, or `restore`. A question the room's moderation holds is written with status `:pending` and reaches nobody but its asker until it's approved.
- `Vote`: `cast` an upvote (idempotent per browser); destroy a vote to unvote.
- `Reading`: `add` an item to a room's approved list, then `edit` or destroy it.

Subscribe a process to a room's live feed with `Quorum.Sessions.subscribe(room_id)`; every change to that room delivers `{:room_changed, room_id}` so a view can reload its ranked questions.
