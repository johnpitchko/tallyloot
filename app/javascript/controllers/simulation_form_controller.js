import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="simulation-form"
// Debounces form auto-submission so the simulation re-runs 500ms after
// any input change, without requiring the user to click "Run Simulation".
export default class extends Controller {
  static values = { delay: { type: Number, default: 500 } };

  connect() {
    this._timer = null;
  }

  disconnect() {
    clearTimeout(this._timer);
  }

  schedule() {
    clearTimeout(this._timer);
    if (!this.element.checkValidity()) return;
    this._timer = setTimeout(() => this.element.requestSubmit(), this.delayValue);
  }
}
