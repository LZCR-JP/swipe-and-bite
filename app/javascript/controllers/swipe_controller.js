import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "card",
    "likeButton",
    "dislikeButton",
    "likeStamp",
    "dislikeStamp"
  ]

  static values = {
    threshold: { type: Number, default: 110 }
  }

  start(event) {
    if (this.submitting || this.dragging) return
    if (event.target.closest("button, a, form")) return
    if (event.button !== undefined && event.button !== 0) return

    this.dragging = true
    this.startX = event.clientX
    this.pointerId = event.pointerId
    this.cardTarget.setPointerCapture(event.pointerId)
    this.cardTarget.style.transition = "none"
    this.cardTarget.classList.add("is-dragging")
  }

  move(event) {
    if (!this.dragging || event.pointerId !== this.pointerId) return

    const distance = event.clientX - this.startX
    const rotation = distance / 18
    const strength = Math.min(Math.abs(distance) / this.thresholdValue, 1)

    this.cardTarget.style.transform =
      `translateX(${distance}px) rotate(${rotation}deg)`

    this.likeStampTarget.style.opacity = distance > 0 ? strength : 0
    this.dislikeStampTarget.style.opacity = distance < 0 ? strength : 0
  }

  finish(event) {
    if (!this.dragging || event.pointerId !== this.pointerId) return

    const distance = event.clientX - this.startX

    if (distance >= this.thresholdValue) {
      this.throwCard("right")
    } else if (distance <= -this.thresholdValue) {
      this.throwCard("left")
    } else {
      this.resetCard()
    }
  }

  cancel(event) {
    if (!this.dragging || event.pointerId !== this.pointerId) return
    this.resetCard()
  }

  throwCard(direction) {
    if (this.submitting) return

    this.dragging = false
    this.submitting = true
    this.cardTarget.classList.remove("is-dragging")

    const distance = direction === "right" ? "120vw" : "-120vw"
    const rotation = direction === "right" ? "24deg" : "-24deg"

    const duration = this.reducedMotion ? 0 : 220
    this.cardTarget.style.transition = `transform ${duration}ms cubic-bezier(.22, 1, .36, 1)`
    this.cardTarget.style.transform =
      `translateX(${distance}) rotate(${rotation})`

    this.submitTimer = window.setTimeout(() => {
      const button = direction === "right"
        ? this.likeButtonTarget
        : this.dislikeButtonTarget

      button.click()
    }, duration)
  }

  resetCard() {
    this.dragging = false
    this.pointerId = null
    this.cardTarget.classList.remove("is-dragging")
    const duration = this.reducedMotion ? 0 : 300
    this.cardTarget.style.transition = `transform ${duration}ms cubic-bezier(.22, 1, .36, 1)`
    this.cardTarget.style.transform = ""
    this.likeStampTarget.style.opacity = 0
    this.dislikeStampTarget.style.opacity = 0

  }

  get reducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }

  disconnect() {
    window.clearTimeout(this.submitTimer)
  }
}
