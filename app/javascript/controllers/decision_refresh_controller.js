import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, signature: String }

  connect() {
    this.timer = setInterval(() => this.refresh(), 5000)
  }

  disconnect() {
    clearInterval(this.timer)
    this.request?.abort()
  }

  async refresh() {
    if (document.hidden || this.request || this.element.querySelector('[aria-busy="true"]')) return
    const request = new AbortController()
    this.request = request
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" }, cache: "no-store", signal: request.signal })
      if (!response.ok || !this.element.isConnected || this.element.querySelector('[aria-busy="true"]')) return
      const result = await response.json()
      if (result.signature !== this.signatureValue && !document.querySelector("dialog[open]")) window.location.reload()
    } catch (error) {
      // Keep the current view on temporary network errors.
    } finally {
      if (this.request === request) this.request = null
    }
  }
}
