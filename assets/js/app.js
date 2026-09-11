// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/quorum"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  // The browser's minutes east of UTC. Settings reads it so "Close automatically
  // at" means the presenter's own clock rather than the server's.
  params: {_csrf_token: csrfToken, tz_offset: -new Date().getTimezoneOffset()},
  hooks: {...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

// Copy a string to the clipboard from a phx-click JS.dispatch, and let the
// LiveView say so. Falls back to a hidden textarea where the async clipboard
// API is unavailable (an insecure origin, or an older browser).
window.addEventListener("quorum:copy", (event) => {
  const text = event.detail && event.detail.text
  if (!text) return

  const done = () => {
    const target = event.target.closest("[phx-click]") || event.target
    const view = target.closest("[data-phx-main], [data-phx-session]")
    if (window.liveSocket && view) {
      window.liveSocket.execJS(target, JSON.stringify([["push", {event: "copied"}]]))
    }
  }

  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(text).then(done).catch(() => {})
    return
  }

  const field = document.createElement("textarea")
  field.value = text
  field.setAttribute("readonly", "")
  field.style.position = "fixed"
  field.style.opacity = "0"
  document.body.appendChild(field)
  field.select()
  try { document.execCommand("copy"); done() } finally { field.remove() }
})

// Cycle the landing page's example feed card through its samples, with a fresh
// asker and age each time. Auto-updating content is motion, so a viewer who
// asked for reduced motion keeps the one the server rendered.
;(() => {
  const card = document.getElementById("q-example")
  if (!card) return
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

  let examples
  try { examples = JSON.parse(card.dataset.examples || "[]") } catch { return }
  if (!Array.isArray(examples) || examples.length < 2) return

  const votes = card.querySelector('[data-example="votes"]')
  const body = card.querySelector('[data-example="body"]')
  const meta = card.querySelector('[data-example="meta"]')
  if (!votes || !body || !meta) return

  const ago = () => {
    const s = 30 + Math.floor(Math.random() * 871) // 30s to 15min
    if (s < 60) return `${s} seconds ago`
    if (s < 120) return "1 minute ago"
    return `${Math.floor(s / 60)} minutes ago`
  }

  let i = Math.floor(Math.random() * examples.length)
  const step = () => {
    i = (i + 1) % examples.length
    const next = examples[i]
    card.style.opacity = "0"
    setTimeout(() => {
      votes.textContent = next.votes
      body.textContent = next.body
      meta.textContent = `${next.name || "Anonymous"}, ${ago()}`
      card.style.opacity = "1"
    }, 220)
  }

  card.style.transition = "opacity 220ms ease"
  let timer = setInterval(step, parseInt(card.dataset.rotateMs || "5000", 10))

  // Stop while the tab is hidden, so a backgrounded page isn't doing work.
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      clearInterval(timer)
    } else {
      clearInterval(timer)
      timer = setInterval(step, parseInt(card.dataset.rotateMs || "5000", 10))
    }
  })
})()

// Rotate the hero mock's join code through fresh random five-character strings,
// so the preview reads as live. Decorative: the QR beside it still points at the
// demo room. Held still under reduced motion, and paused while the tab is hidden.
;(() => {
  const el = document.getElementById("q-hero-code")
  if (!el) return
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

  // The room-code alphabet, ambiguous glyphs (I, O, 0, 1) removed.
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  const code = () =>
    Array.from({length: 5}, () => alphabet[Math.floor(Math.random() * alphabet.length)]).join("")

  const ms = parseInt(el.dataset.rotateMs || "5000", 10)
  el.style.transition = "opacity 220ms ease"
  const step = () => {
    el.style.opacity = "0"
    setTimeout(() => {
      el.textContent = code()
      el.style.opacity = "1"
    }, 220)
  }

  let timer = setInterval(step, ms)
  document.addEventListener("visibilitychange", () => {
    clearInterval(timer)
    if (!document.hidden) timer = setInterval(step, ms)
  })
})()

// Cycle the reading-pointer illustration through its scenarios: a question and
// the two list items a room would point a student at. Same motion rules.
;(() => {
  const card = document.getElementById("q-pointer")
  if (!card) return
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

  let scenarios
  try { scenarios = JSON.parse(card.dataset.scenarios || "[]") } catch { return }
  if (!Array.isArray(scenarios) || scenarios.length < 2) return

  const question = card.querySelector('[data-pointer="question"]')
  const readings = card.querySelector('[data-pointer="readings"]')
  if (!question || !readings) return

  const render = (s) => {
    question.textContent = s.question
    readings.replaceChildren()
    s.readings.forEach((r, idx) => {
      const link = document.createElement("span")
      link.className = "q-l-pointer-link"
      link.textContent = r.title
      readings.append(link, document.createTextNode(`, ${r.detail}`))
      if (idx < s.readings.length - 1) readings.append(document.createElement("br"))
    })
  }

  const ms = parseInt(card.dataset.rotateMs || "6000", 10)
  question.style.transition = readings.style.transition = "opacity 220ms ease"
  let i = Math.floor(Math.random() * scenarios.length)
  const step = () => {
    i = (i + 1) % scenarios.length
    question.style.opacity = readings.style.opacity = "0"
    setTimeout(() => {
      render(scenarios[i])
      question.style.opacity = readings.style.opacity = "1"
    }, 220)
  }

  let timer = setInterval(step, ms)
  document.addEventListener("visibilitychange", () => {
    clearInterval(timer)
    if (!document.hidden) timer = setInterval(step, ms)
  })
})()
