"use strict";

(function exposeBranchlineA11y(global) {
  function installTabs(tablist, onActivate) {
    if (!tablist) return;
    const tabs = Array.from(tablist.querySelectorAll('[role="tab"]'));
    function activate(tab, focus = true) {
      tabs.forEach((item) => item.tabIndex = item === tab ? 0 : -1);
      onActivate(tab);
      if (focus) tab.focus();
    }
    tabs.forEach((tab, index) => {
      tab.tabIndex = tab.getAttribute("aria-selected") === "true" ? 0 : -1;
      tab.addEventListener("keydown", (event) => {
        let next = -1;
        if (event.key === "ArrowRight" || event.key === "ArrowDown") next = (index + 1) % tabs.length;
        if (event.key === "ArrowLeft" || event.key === "ArrowUp") next = (index - 1 + tabs.length) % tabs.length;
        if (event.key === "Home") next = 0;
        if (event.key === "End") next = tabs.length - 1;
        if (next >= 0) {
          event.preventDefault();
          activate(tabs[next]);
        }
      });
    });
  }

  function installDialog(dialog) {
    if (!dialog) return;
    let returnFocus = null;
    dialog.addEventListener("close", () => {
      if (returnFocus instanceof HTMLElement && returnFocus.isConnected) returnFocus.focus();
      returnFocus = null;
    });
    dialog.addEventListener("keydown", (event) => {
      if (event.key !== "Tab") return;
      const focusable = Array.from(dialog.querySelectorAll('button:not([disabled]), a[href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'));
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    });
    return {
      show() {
        returnFocus = document.activeElement;
        if (typeof dialog.showModal === "function") dialog.showModal();
        else dialog.setAttribute("open", "");
        const focusTarget = dialog.querySelector('[autofocus], button:not([disabled]), [href], input:not([disabled])');
        window.setTimeout(() => focusTarget?.focus(), 0);
      },
      close() {
        if (typeof dialog.close === "function") dialog.close();
        else dialog.removeAttribute("open");
      }
    };
  }

  global.BranchlineA11y = Object.freeze({ installTabs, installDialog });
})(window);
