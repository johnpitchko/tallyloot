import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { type: String };

  connect() {
    setTimeout(() => this.dismiss(), 5000);
  }

  dismiss() {
    // Add fade-out class
    this.element.classList.add("fade-out");

    // Remove from DOM after transition
    this.element.addEventListener(
      "transitionend",
      () => {
        this.element.remove();
      },
      { once: true },
    );
  }
}
