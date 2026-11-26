import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }
  static targets = ["label", "count", "bar"]

  connect() {
    this.timer = setInterval(() => this.refresh(), 5000)
  }

  disconnect() {
    clearInterval(this.timer)
    this.request?.abort()
  }

  async refresh() {
    if (document.hidden || this.request) return
    const request = new AbortController()
    this.request = request
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" }, cache: "no-store", signal: request.signal })
      if (!this.element.isConnected) return
      if (response.status === 404) {
        clearInterval(this.timer)
        window.location.reload()
        return
      }
      if (!response.ok) return
      const progress = await response.json()
      if (!progress.ongoing) {
        clearInterval(this.timer)
        window.location.reload()
        return
      }
      const total = Math.max(1, progress.total)
      this.labelTarget.textContent = progress.completed >= total ? "Ready to find matches" : "Waiting for responses"
      this.countTarget.textContent = `${progress.completed} / ${total}`
      this.barTarget.max = total
      this.barTarget.value = Math.min(progress.completed, total)
    } catch (error) {
      // The card remains usable if the network drops.
    } finally {
      if (this.request === request) this.request = null
    }
  }
}
