"use strict";

window.BranchlineRender = Object.freeze({
  text(element, value, fallback = "") {
    if (element) element.textContent = value === null || value === undefined || value === "" ? fallback : String(value);
  },
  hidden(element, hidden) {
    if (element) element.classList.toggle("is-hidden", Boolean(hidden));
  },
  announce(element, message) {
    if (element) element.textContent = String(message || "");
  }
});
