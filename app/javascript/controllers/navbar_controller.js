import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="navbar"
export default class extends Controller {
  static targets = ["menu"];

  toggle() {
    this.element.querySelector(".navbar-burger").classList.toggle("is-active");
    this.menuTarget.classList.toggle("is-active");
  }
}
