import { Controller } from "@hotwired/stimulus"

// Remembers whether a <details> section is open, so the dashboard's input
// panel keeps its layout when the page refreshes after a save.
export default class extends Controller {
  connect() {
    const saved = this.read()
    if (saved !== null) this.restore(saved === "open")
    this.save = this.save.bind(this)
    this.element.addEventListener("toggle", this.save)
  }

  disconnect() {
    this.element.removeEventListener("toggle", this.save)
  }

  // Applies the saved state without the open/close animation.
  restore(open) {
    if (this.element.open === open) return
    this.element.classList.add("is-instant")
    this.element.open = open
    requestAnimationFrame(() => requestAnimationFrame(() => this.element.classList.remove("is-instant")))
  }

  save() {
    try {
      sessionStorage.setItem(this.key, this.element.open ? "open" : "closed")
    } catch {
      // Storage can be unavailable (private windows); the section just resets.
    }
  }

  read() {
    try {
      return sessionStorage.getItem(this.key)
    } catch {
      return null
    }
  }

  get key() {
    return `disclosure:${this.element.id}`
  }
}
