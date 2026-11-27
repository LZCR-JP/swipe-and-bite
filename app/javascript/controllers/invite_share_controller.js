import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, title: String }
  static targets = ["button", "label", "sheet", "fallback", "message"]

  async share() {
    this.messageTarget.textContent = ""
    if (typeof navigator.share === "function" && (!navigator.canShare || navigator.canShare({ url: this.urlValue }))) {
      try {
        await navigator.share({ title: this.titleValue, text: "Join my plan on Swipe & Bite!", url: this.urlValue })
        return
      } catch (error) {
        if (error.name === "AbortError") return
      }
    }
    if (!this.sheetTarget.open) this.sheetTarget.showModal()
  }

  close() {
    this.sheetTarget.close()
  }

  dismissBackdrop(event) {
    if (event.target === this.sheetTarget) this.close()
  }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.urlValue)
      this.messageTarget.textContent = "Link copied."
    } catch {
      this.fallbackTarget.focus()
      this.fallbackTarget.select()
      this.messageTarget.textContent = "Select and copy the link."
    }
  }

  disconnect() {
    if (this.hasSheetTarget && this.sheetTarget.open) this.sheetTarget.close()
  }
}
