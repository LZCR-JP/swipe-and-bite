import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sheet", "trigger"]

  open(event) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || typeof this.sheetTarget.showModal !== "function") return
    event.preventDefault()
    if (!this.sheetTarget.open) this.sheetTarget.showModal()
  }

  close() {
    if (this.sheetTarget.open) this.sheetTarget.close()
  }

  backdrop(event) {
    if (event.target === this.sheetTarget) this.close()
  }

  restoreFocus() {
    if (this.element.isConnected && this.hasTriggerTarget) this.triggerTarget.focus({ preventScroll: true })
  }

  disconnect() {
    if (this.hasSheetTarget && this.sheetTarget.open) this.sheetTarget.close()
  }
}
