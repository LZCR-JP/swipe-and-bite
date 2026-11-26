import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const field = this.element
    if (!field.name) return
    this.originalName = field.name
    this.minimum = Number(field.min || 0)
    this.hidden = document.createElement("input")
    this.hidden.type = "hidden"
    this.hidden.name = this.originalName
    field.after(this.hidden)
    field.removeAttribute("name")
    field.type = "text"
    this.format()
  }

  format() {
    if (!this.hidden) return
    const field = this.element
    const caret = field.selectionStart ?? field.value.length
    const digitsBefore = field.value.slice(0, caret).replace(/[^0-9]/g, "").length
    const raw = field.value.replace(/[^0-9]/g, "").replace(/^0+(?=\d)/, "").slice(0, 10)
    this.hidden.value = raw
    field.value = raw.replace(/\B(?=(\d{3})+(?!\d))/g, ",")
    field.setCustomValidity(raw && (Number(raw) < this.minimum || Number(raw) > 2147483647) ? `Enter an amount from ¥${this.minimum.toLocaleString("en-US")} to ¥2,147,483,647.` : "")
    let position = 0, count = 0
    while (position < field.value.length && count < digitsBefore) {
      if (/\d/.test(field.value[position])) count++
      position++
    }
    if (document.activeElement === field) field.setSelectionRange(position, position)
  }

  restore() {
    if (!this.hidden) return
    const field = this.element
    const raw = this.hidden.value
    this.hidden.remove()
    this.hidden = null
    field.name = this.originalName
    field.type = "number"
    field.value = raw
    field.setCustomValidity("")
  }

  disconnect() { this.restore() }
}
