import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frame"]
  static values = { basePath: String }

  change(event) {
    this.frameTarget.src = `${this.basePathValue}/${event.target.value}`
  }
}
