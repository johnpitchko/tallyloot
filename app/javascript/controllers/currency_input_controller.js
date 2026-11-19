import { Controller } from "@hotwired/stimulus";

// Formats a plain integer input with thousands commas on blur, strips them on focus,
// and ensures the raw number (no commas) is submitted with the form.
export default class extends Controller {
  connect() {
    this._form = this.element.closest("form");
    this._stripOnSubmit = () => {
      this._strip();
      // Re-format after all submit handlers run so the field stays readable
      // during the round-trip (Turbo reads the stripped value before this fires).
      setTimeout(() => this._format(), 0);
    };
    this._reformatOnSubmitEnd = () => this._format();
    if (this._form) {
      this._form.addEventListener("submit", this._stripOnSubmit);
      this._form.addEventListener("turbo:submit-end", this._reformatOnSubmitEnd);
    }
    this._format();
  }

  disconnect() {
    if (this._form) {
      this._form.removeEventListener("submit", this._stripOnSubmit);
      this._form.removeEventListener("turbo:submit-end", this._reformatOnSubmitEnd);
    }
  }

  focus() {
    const raw = this._rawValue();
    this.element.value = raw !== null ? String(raw) : "";
  }

  blur() {
    this._format();
  }

  _format() {
    const raw = this._rawValue();
    if (raw === null) return;
    this.element.value = new Intl.NumberFormat("en-CA").format(raw);
  }

  _strip() {
    const raw = this._rawValue();
    this.element.value = raw !== null ? String(raw) : "";
  }

  _rawValue() {
    const num = parseInt(this.element.value.replace(/,/g, ""), 10);
    return isNaN(num) ? null : num;
  }
}
