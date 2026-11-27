import { Controller } from "@hotwired/stimulus"

// Survives Stimulus reconnects and Turbo navigation even if storage is unavailable.
const shownInDocument = new Set()

export default class extends Controller {
  static values = { url: String }
  static targets = ["banner", "link", "heading", "description", "celebration", "confetti", "photoFrame", "photo", "credits", "restaurant", "address", "planLink"]

  connect() {
    this.connected = true
    if (this.celebrationTarget.open) this.celebrationTarget.close()
    this.bannerTarget.hidden = true
    this.activeKey = null
    this.onVisible = () => { if (!document.hidden) this.refresh() }
    document.addEventListener("visibilitychange", this.onVisible)
    this.timer = setInterval(() => this.refresh(), 5000)
    this.refresh()
  }

  disconnect() {
    this.connected = false
    clearInterval(this.timer)
    clearTimeout(this.hideTimer)
    document.removeEventListener("visibilitychange", this.onVisible)
    const request = this.request
    this.request = null
    request?.abort()
    this.activeKey = null
    this.photoRequest?.abort()
    if (this.hasCelebrationTarget && this.celebrationTarget.open) this.celebrationTarget.close()
  }

  beforeCache() {
    this.closeCelebration()
    this.bannerTarget.hidden = true
  }

  async refresh() {
    if (!this.connected || document.hidden || this.request || document.querySelector("dialog[open]")) return
    const request = new AbortController()
    this.request = request
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" }, cache: "no-store", signal: request.signal })
      if (!response.ok || !this.element.isConnected || this.request !== request) return
      const result = await response.json()
      if (!this.element.isConnected || this.request !== request) return
      const list = document.querySelector("[data-joined-plans-signature]")
      if (list && list.dataset.joinedPlansSignature !== result.signature) {
        window.location.reload()
        return
      }
      // Leave a displayed banner visible until dismissed or its timer expires.
      if (this.activeKey) return
      const update = result.updates.find(item => !this.wasSeen(item.key))
      if (!update) return
      if (update.state === "confirmed" && update.restaurant && this.hasCelebrationTarget && typeof this.celebrationTarget.showModal === "function") {
        this.showCelebration(update)
        return
      }
      this.activeKey = update.key
      this.headingTarget.textContent = update.state === "confirmed" ? "It's confirmed!" : "Time to vote"
      this.descriptionTarget.textContent = update.title + " · View plan"
      this.linkTarget.href = update.path
      // A notification is consumed on display, not on click or dismissal.
      this.markSeen(update.key)
      this.bannerTarget.hidden = false
      this.hideTimer = setTimeout(() => this.dismiss(), 8000)
    } catch (error) {
      // The Plans page remains usable during a temporary connection failure.
    } finally {
      if (this.request === request) this.request = null
    }
  }

  showCelebration(update) {
    if (document.querySelector("dialog[open]")) return
    this.restaurantTarget.textContent = update.restaurant
    this.addressTarget.textContent = update.address || ""
    this.planLinkTarget.href = update.path
    this.photoFrameTarget.hidden = true
    this.photoTarget.removeAttribute("src")
    this.creditsTarget.replaceChildren()
    this.confettiTarget.replaceChildren()
    if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      const colors = ["#ff6900", "#ffbc55", "#ffd9a6", "#292929", "#2ebd85", "#ffffff"]
      for (let i = 0; i < 48; i++) {
        const piece = document.createElement("span")
        const angle = (i / 48) * Math.PI * 2
        const radius = 100 + Math.random() * 145
        piece.style.setProperty("--dx", `${Math.cos(angle) * radius}px`)
        piece.style.setProperty("--dy", `${Math.sin(angle) * radius - 45}px`)
        piece.style.setProperty("--spin", `${Math.round(Math.random() * 720 - 360)}deg`)
        piece.style.setProperty("--delay", `${Math.random() * 180}ms`)
        piece.style.backgroundColor = colors[i % colors.length]
        this.confettiTarget.append(piece)
      }
    }
    this.celebrationTarget.showModal()
    this.activeKey = update.key
    this.markSeen(update.key)
    if (update.photo_endpoint) this.loadPhoto(update)
  }

  async loadPhoto(update) {
    this.photoRequest?.abort()
    const request = new AbortController()
    this.photoRequest = request
    try {
      const response = await fetch(update.photo_endpoint, { headers: { Accept: "application/json" }, cache: "no-store", signal: request.signal })
      if (!response.ok) return
      const result = await response.json()
      if (!result.photo_url || this.photoRequest !== request || !this.celebrationTarget.open) return
      this.photoTarget.alt = `Photo of ${update.restaurant}`
      this.photoTarget.onload = () => { if (this.celebrationTarget.open && this.photoRequest === request) this.photoFrameTarget.hidden = false }
      this.photoTarget.onerror = () => { this.photoFrameTarget.hidden = true }
      this.creditsTarget.textContent = "Google Maps"
      for (const author of result.authors || []) {
        if (!author.displayName) continue
        this.creditsTarget.append(document.createTextNode(" · "))
        let url
        try { url = new URL(author.uri) } catch (_) { /* no link */ }
        if (url?.protocol === "https:") {
          const link = document.createElement("a")
          link.href = url.href
          link.target = "_blank"
          link.rel = "noopener noreferrer"
          link.textContent = author.displayName
          this.creditsTarget.append(link)
        } else {
          this.creditsTarget.append(document.createTextNode(author.displayName))
        }
      }
      this.photoTarget.src = result.photo_url
    } catch (_) { /* Confirmation is still usable without a photo. */ }
  }

  closeCelebration() {
    if (this.celebrationTarget.open) this.celebrationTarget.close()
  }

  celebrationClosed() {
    this.photoRequest?.abort()
    this.photoRequest = null
    this.activeKey = null
    if (this.connected && this.element.isConnected) this.refresh()
  }

  wasSeen(key) {
    if (shownInDocument.has(key)) return true
    const storageKey = `swipe-bite:plan-update:${key}`
    // Honor previously dismissed notifications from the old controller too.
    try { if (localStorage.getItem(storageKey) === "1") return true } catch (_) { /* unavailable */ }
    try { return sessionStorage.getItem(storageKey) === "1" } catch (_) { return false }
  }

  markSeen(key) {
    if (!key) return
    shownInDocument.add(key)
    const storageKey = `swipe-bite:plan-update:${key}`
    try { localStorage.setItem(storageKey, "1") } catch (_) { /* unavailable */ }
    try { sessionStorage.setItem(storageKey, "1") } catch (_) { /* unavailable */ }
  }

  dismiss() {
    clearTimeout(this.hideTimer)
    this.bannerTarget.hidden = true
    this.activeKey = null
    this.refresh()
  }
}
