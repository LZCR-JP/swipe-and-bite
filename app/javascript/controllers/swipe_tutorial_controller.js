import { Controller } from "@hotwired/stimulus"

// First-visit tutorial for the swipe screen. Participants are token-based
// guests, so "seen" is remembered per browser in localStorage.
const STORAGE_KEY = "swipe-and-bite:swipe-tutorial-seen"
const CLOSE_DURATION = 180

export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    if (!this.seen) this.open()
  }

  disconnect() {
    window.clearTimeout(this.closeTimer)
    // Don't let Turbo snapshot the page with the dialog open.
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  open() {
    const dialog = this.dialogTarget
    if (dialog.open) return

    window.clearTimeout(this.closeTimer)
    dialog.classList.remove("is-closing")
    dialog.showModal()
  }

  close() {
    const dialog = this.dialogTarget
    if (!dialog.open || dialog.classList.contains("is-closing")) return

    this.markSeen()
    dialog.classList.add("is-closing")

    const duration = this.reducedMotion ? 0 : CLOSE_DURATION
    this.closeTimer = window.setTimeout(() => {
      dialog.classList.remove("is-closing")
      dialog.close()
    }, duration)
  }

  // Clicks on the <dialog> element itself land on the backdrop area;
  // clicks inside the sheet have a descendant as their target.
  backdropClose(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  markSeen() {
    try {
      window.localStorage.setItem(STORAGE_KEY, "1")
    } catch (_error) {
      // Storage can be unavailable (private mode, blocked site data).
    }
  }

  get seen() {
    try {
      return window.localStorage.getItem(STORAGE_KEY) === "1"
    } catch (_error) {
      return false
    }
  }

  get reducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }
}
