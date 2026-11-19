import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="simulation-advisory"
// Handles two responsibilities for each user's simulation box:
//
// 1. Advisory notice: warns the user that changing retirement age does not
//    automatically update pension/benefit collection ages.
//
// 2. Cross-field validation: retirement age must be strictly less than
//    life expectancy. Uses setCustomValidity() so the browser's constraint
//    API and checkValidity() on the form both reflect the error state,
//    preventing auto-submit while invalid.
export default class extends Controller {
  static targets = [
    "notice",
    "retirementAgeInput",
    "lifeExpectancyInput",
    "ageError",
  ];

  showNotice() {
    this.noticeTarget.style.display = "";
    this.validate();
  }

  validate() {
    if (
      !this.hasRetirementAgeInputTarget ||
      !this.hasLifeExpectancyInputTarget
    )
      return;

    const retAge = parseInt(this.retirementAgeInputTarget.value, 10);
    const lifeExp = parseInt(this.lifeExpectancyInputTarget.value, 10);
    const invalid = !isNaN(retAge) && !isNaN(lifeExp) && retAge >= lifeExp;

    this.retirementAgeInputTarget.classList.toggle("is-danger", invalid);
    this.retirementAgeInputTarget.setCustomValidity(
      invalid
        ? `Must be less than life expectancy (${lifeExp}).`
        : "",
    );

    if (this.hasAgeErrorTarget) {
      this.ageErrorTarget.textContent = invalid
        ? `Retirement age must be less than life expectancy (${lifeExp}).`
        : "";
      this.ageErrorTarget.style.display = invalid ? "" : "none";
    }
  }
}
