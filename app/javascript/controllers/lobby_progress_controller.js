import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, signature: String }
  static targets = ["panel", "announcement"]

  connect() {
    this.timer = setInterval(() => this.refresh(), 5000)
  }

  disconnect() {
    clearInterval(this.timer)
    this.request?.abort()
  }

  async refresh() {
    if (document.hidden || this.request || this.panelTarget.querySelector('[aria-busy="true"]')) return
    const request = new AbortController()
    this.request = request
    try {
      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("view", "lobby")
      url.searchParams.set("signature", this.signatureValue)
      const response = await fetch(url, { headers: { Accept: "application/json" }, cache: "no-store", signal: request.signal })
      if (!response.ok || !this.element.isConnected || this.panelTarget.querySelector('[aria-busy="true"]')) return
      const result = await response.json()
      if (!this.element.isConnected || this.panelTarget.querySelector('[aria-busy="true"]')) return
      if (!result.ongoing) { window.location.reload(); return }
      if (!result.html) return
      const expanded = this.panelTarget.querySelector("details[open]")
      const hadRefreshFocus = document.activeElement?.matches('[data-action="lobby-progress#refresh"]')
      // Only replace the participant panel, not the invite, map or entire page.
      this.panelTarget.innerHTML = result.html
      this.signatureValue = result.signature
      if (expanded) this.panelTarget.querySelector("details")?.setAttribute("open", "")
      if (hadRefreshFocus) this.panelTarget.querySelector('[data-action="lobby-progress#refresh"]')?.focus({ preventScroll: true })
      this.announcementTarget.textContent = `${result.guest_joined} of ${result.guest_total} guests joined, ${result.completed} of ${result.total} swipes completed.`
    } catch (error) {
      // Retry on the next poll; the existing view remains usable.
    } finally {
      if (this.request === request) this.request = null
    }
  }
}
