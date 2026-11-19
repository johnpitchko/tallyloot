import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="year-calculator"
// Calculates and displays the year a user will reach a certain age
export default class extends Controller {
  static targets = ["birthDate", "currentAge", "retirementAge", "retirementYear", "lifeExpectancy", "lifeExpectancyYear"];

  connect() {
    this.calculate();
  }

  calculate() {
    const birthDate = this.birthDateTarget.value;
    if (!birthDate) {
      this.clearAll();
      return;
    }

    const birth = new Date(birthDate);
    const today = new Date();

    // Calculate current age, only counting birthday once it has passed this year
    let currentAge = today.getFullYear() - birth.getFullYear();
    const hadBirthdayThisYear =
      today.getMonth() > birth.getMonth() ||
      (today.getMonth() === birth.getMonth() && today.getDate() >= birth.getDate());
    if (!hadBirthdayThisYear) currentAge -= 1;
    this.currentAgeTarget.textContent = currentAge;

    const birthYear = birth.getFullYear();

    // Calculate retirement year
    const retirementAge = parseInt(this.retirementAgeTarget.value, 10);
    if (retirementAge && !isNaN(retirementAge)) {
      const retirementYear = birthYear + retirementAge;
      this.retirementYearTarget.textContent = retirementYear;
    } else {
      this.retirementYearTarget.textContent = "—";
    }

    // Calculate life expectancy year
    const lifeExpectancy = parseInt(this.lifeExpectancyTarget.value, 10);
    if (lifeExpectancy && !isNaN(lifeExpectancy)) {
      const lifeExpectancyYear = birthYear + lifeExpectancy;
      this.lifeExpectancyYearTarget.textContent = lifeExpectancyYear;
    } else {
      this.lifeExpectancyYearTarget.textContent = "—";
    }
  }

  clearAll() {
    this.currentAgeTarget.textContent = "—";
    this.retirementYearTarget.textContent = "—";
    this.lifeExpectancyYearTarget.textContent = "—";
  }
}
