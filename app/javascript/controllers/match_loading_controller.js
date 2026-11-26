import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  start(event) {
    if (event.defaultPrevented) return
    if (this.overlay) { event.preventDefault(); return }
    this.element.setAttribute("aria-busy", "true")
    const overlay = document.createElement("div")
    overlay.className = "match-loading"
    overlay.setAttribute("role", "status")
    overlay.setAttribute("aria-live", "polite")
    overlay.innerHTML = '<div class="match-loading__panel"><span class="match-loading__spinner" aria-hidden="true"></span><h2>Finding your matches.</h2><p>Looking for spots that fit your group…</p></div>'
    document.body.append(overlay)
    this.overlay = overlay
  }

  reset() {
    this.overlay?.remove()
    this.overlay = null
    this.element.removeAttribute("aria-busy")
  }

  disconnect() { this.reset() }
}
