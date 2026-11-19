import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    federalBrackets: Array,
    federalBpa: Number,
    provinceData: Object,
  };
  static targets = ["grossInput", "provinceSelect", "preview"];

  connect() {
    this.update();
  }

  update() {
    const gross = parseInt(this.grossInputTarget.value.replace(/,/g, "")) || 0;
    if (gross <= 0) {
      this.previewTarget.textContent = "";
      return;
    }

    const province = this.hasProvinceSelectTarget ? this.provinceSelectTarget.value : null;
    const tax = this.#computeTax(gross, province);
    const net = gross - tax;

    const monthly = Math.round(net / 12);
    this.previewTarget.textContent =
      `≈ ${this.#formatCurrency(net)} net/year (${this.#formatCurrency(monthly)}/month) — estimated after federal + provincial tax`;
  }

  #computeTax(gross, province) {
    return this.#federalTax(gross) + this.#provincialTax(gross, province);
  }

  #federalTax(gross) {
    const netIncome = Math.max(gross - this.federalBpaValue, 0);
    if (netIncome <= 0) return 0;
    return this.#marginalTax(netIncome, this.federalBracketsValue);
  }

  #provincialTax(gross, province) {
    if (!province) return 0;
    const data = this.provinceDataValue[province];
    if (!data) return 0;
    const netIncome = Math.max(gross - data.bpa, 0);
    if (netIncome <= 0) return 0;
    return this.#marginalTax(netIncome, data.brackets);
  }

  #marginalTax(netIncome, brackets) {
    let tax = 0;
    brackets.forEach((bracket, i) => {
      if (netIncome <= bracket.threshold) return;
      const upper = brackets[i + 1]?.threshold ?? Infinity;
      const inBracket = Math.min(netIncome, upper) - bracket.threshold;
      tax += inBracket * bracket.rate;
    });
    return Math.round(tax);
  }

  #formatCurrency(amount) {
    return new Intl.NumberFormat("en-CA", {
      style: "currency",
      currency: "CAD",
      maximumFractionDigits: 0,
    }).format(amount);
  }
}
