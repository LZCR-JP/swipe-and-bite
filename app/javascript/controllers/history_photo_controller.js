import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }
  static targets = ["image", "fallback", "credit"]

  connect() {
    if (this.loaded) return
    if ("IntersectionObserver" in window) {
      this.observer = new IntersectionObserver(entries => {
        if (!entries.some(entry => entry.isIntersecting)) return
        this.observer.disconnect()
        this.load()
      }, { rootMargin: "80px" })
      this.observer.observe(this.element)
    } else {
      this.load()
    }
  }

  disconnect() {
    this.observer?.disconnect()
    this.request?.abort()
    this.request = null
    this.imageTarget.onload = null
    this.imageTarget.onerror = null
  }

  reset() {
    this.disconnect()
    this.loaded = false
    this.imageTarget.removeAttribute("src")
    this.imageTarget.hidden = true
    this.fallbackTarget.hidden = false
    this.creditTarget.hidden = true
    this.creditTarget.replaceChildren()
  }

  async load() {
    if (this.request || this.loaded) return
    const request = new AbortController()
    this.request = request
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" }, cache: "no-store", signal: request.signal })
      if (!response.ok) return
      const data = await response.json()
      if (!data.photo_url || this.request !== request || !this.element.isConnected) return
      this.creditTarget.textContent = "Google Maps"
      for (const author of data.authors || []) {
        if (!author.displayName) continue
        this.creditTarget.append(document.createTextNode(" · "))
        let url
        try { url = new URL(author.uri) } catch (_) { /* no author link */ }
        if (url?.protocol === "https:") {
          const link = document.createElement("a")
          link.href = url.href
          link.target = "_blank"
          link.rel = "noopener noreferrer"
          link.textContent = author.displayName
          this.creditTarget.append(link)
        } else {
          this.creditTarget.append(document.createTextNode(author.displayName))
        }
      }
      this.imageTarget.onload = () => {
        if (request.signal.aborted || !this.element.isConnected) return
        this.imageTarget.hidden = false
        this.fallbackTarget.hidden = true
        this.creditTarget.hidden = false
        this.loaded = true
      }
      this.imageTarget.onerror = () => {
        this.imageTarget.hidden = true
        this.fallbackTarget.hidden = false
        this.creditTarget.hidden = true
      }
      this.imageTarget.src = data.photo_url
    } catch (_) {
      // A missing photo must never block the plan history.
    } finally {
      if (this.request === request) this.request = null
    }
  }
}
