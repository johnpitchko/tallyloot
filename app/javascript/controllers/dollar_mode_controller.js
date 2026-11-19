import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["nominalValue", "realValue", "nominalBtn", "realBtn"]

  connect() {
    this.showNominal()
  }

  showNominal() {
    this.nominalValueTargets.forEach(el => el.classList.remove("is-hidden"))
    this.realValueTargets.forEach(el => el.classList.add("is-hidden"))
    this.nominalBtnTarget.classList.add("is-selected", "is-info")
    this.realBtnTarget.classList.remove("is-selected", "is-info")
  }

  showReal() {
    this.nominalValueTargets.forEach(el => el.classList.add("is-hidden"))
    this.realValueTargets.forEach(el => el.classList.remove("is-hidden"))
    this.nominalBtnTarget.classList.remove("is-selected", "is-info")
    this.realBtnTarget.classList.add("is-selected", "is-info")
  }
}
