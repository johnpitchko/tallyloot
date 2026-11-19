import { Controller } from "@hotwired/stimulus";

const CPP_MAX_ANNUAL = 17196;
const OAS_MAX_ANNUAL = 8713;

const CPP_INCOME_FACTORS = {
  low: 0.40,
  middle: 0.65,
  high: 0.85,
  maximum: 1.00,
};

export default class extends Controller {
  static values = { type: String };
  static targets = [
    "panel",
    "yearsContributed", "incomeBracket",
    "yearsResident",
    "estimatedAmount",
    "annualAmount",
  ];

  connect() {
    this._estimate = null;
  }

  togglePanel() {
    this.panelTarget.classList.toggle("is-hidden");
  }

  calculate() {
    let amount;
    if (this.typeValue === "cpp") {
      const years = Math.min(parseInt(this.yearsContributedTarget.value) || 0, 39);
      const factor = CPP_INCOME_FACTORS[this.incomeBracketTarget.value] || 0;
      amount = Math.round((years / 39) * CPP_MAX_ANNUAL * factor);
    } else {
      const years = Math.min(parseInt(this.yearsResidentTarget.value) || 0, 40);
      amount = Math.round((years / 40) * OAS_MAX_ANNUAL);
    }

    this._estimate = amount;
    this.estimatedAmountTarget.textContent = new Intl.NumberFormat("en-CA", {
      style: "currency",
      currency: "CAD",
      maximumFractionDigits: 0,
    }).format(amount);
  }

  apply() {
    if (this._estimate !== null) {
      this.annualAmountTarget.value = this._estimate;
      this.annualAmountTarget.dispatchEvent(new Event("blur"));
      this.panelTarget.classList.add("is-hidden");
    }
  }

  cancel() {
    this.panelTarget.classList.add("is-hidden");
  }
}
