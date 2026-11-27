import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["image", "fallback", "message", "credit"]

  connect() {
    if (!this.hasImageTarget || !this.imageTarget.complete) return
    this.imageTarget.naturalWidth > 0 ? this.loaded() : this.failed()
  }

  loaded() {
    this.imageTarget.classList.add("is-loaded")
    this.fallbackTarget.hidden = true
  }

  failed() {
    this.imageTarget.hidden = true
    this.fallbackTarget.hidden = false
    this.messageTarget.textContent = "Photo unavailable"
    if (this.hasCreditTarget) this.creditTarget.hidden = true
  }
}
