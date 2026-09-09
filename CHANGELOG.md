# Changelog

All notable changes to Quorum are recorded here, dated per release.

## Unreleased

- Phoenix and Ash application scaffold.
- `Quorum.Sessions` domain with `Room`, `Question`, and `Vote` resources, and their initial migration.
- Live updates: an Ash notifier broadcasts room changes over Phoenix.PubSub.
- Adversarial test suite covering resource validation, vote dedup, status transitions, ranking, and broadcasts.
- Spotlight on `Room`, so the lecturer's pick drives the projection screen.
- The four core screens as LiveViews: join, student feed, host console, and projection.
- `GET /start` opens a room and redirects to its console; `QuorumWeb.BrowserToken` gives each browser an opaque identity for voting and retraction without sign-up.
- Phoenix Presence counts the students connected to a room.
- Server-rendered QR codes on the projection, via eqrcode.
- Keyboard control: **J**, **K**, **Enter**, **A**, **H**, and Escape on the console; **L**, **D**, and **Q** on the projection.
- Design system as CSS: tokens, `q-*` components, and Archivo and Literata self-hosted as woff2.
- Text-link buttons meet the 44px minimum target, and the vote control and feed question take their laptop-width sizes.
- Launchers for macOS, Linux, and Windows (`launch.sh`, `launch.command`, `launch.bat`).
- Landing page at `/`: hero with a student code field and a Start a room call to action, a demo band, how it works, the reading-pointer illustration, and the capability columns.
- A seeded demo lecture behind `/demo`, `/demo/host`, and `/demo/project`, so anyone can see all three roles without opening a room. `rooms.demo?` keeps it apart from a lecturer's own rooms.
- `mix quorum.demo` opens or reseeds that lecture and prints its links.
- The projection's QR card is framed with a hairline in a lit hall, where white on near-white has no edge of its own.
- **L** and **D** each toggle the hall light, rather than each setting one state.
- Lecturer accounts and magic-link sign-in at `/sign-in`, with single-use links, a fifteen-minute expiry, and a thirty-second cooldown between requests. Single sign-on is drawn but disabled until an institution's provider is connected.
- `/rooms` lists a lecturer's own rooms. A room opened while signed in belongs to them; `/host/:host_token` keeps working as before, with or without an account.
- The host console is a full page: site shell, room bar with rename and a fresh join code, the joining panel that shrinks to a strip once questions arrive, and a rail carrying the projection state, the pre-lecture checklist, and the keyboard map.
- Privacy, Accessibility, and Contact pages behind the footer, so no footer link goes nowhere. Contact mail routes to the configured address, with the sender on reply-to.
- The landing page's example card cycles through twenty questions, alternating named and anonymous askers and varying the age between 30 seconds and 15 minutes. It holds still for anyone who has asked for reduced motion.
- More room between the landing page's sections, and the footer's edges line up with the rest of the page.
- Every page is checked at 375px, 768px, 1280px, and 1600px, and none of them scrolls sideways.
- LiveView test suite over all four screens, covering ranking, voting, spotlight, search, the close dialog, keyboard shortcuts, and live arrival of questions.
