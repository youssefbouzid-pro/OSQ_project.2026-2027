(function () {
  "use strict";

  function isDesktop() {
    return window.matchMedia && window.matchMedia("(min-width: 981px)").matches;
  }

  function applyStoredState() {
    try {
      var stored = localStorage.getItem("osq.nav.hidden");
      if (stored === null) {
        stored = localStorage.getItem("cloudy.nav.hidden");
        if (stored !== null) {
          localStorage.setItem("osq.nav.hidden", stored);
          localStorage.removeItem("cloudy.nav.hidden");
        }
      }
      if (stored === "1") {
        document.body.classList.add("nav-hidden");
      }
    } catch (err) {}
  }

  function init() {
    applyStoredState();

    var buttons = document.querySelectorAll(".sidebar-toggle");

    buttons.forEach(function (btn) {
      btn.addEventListener("click", function () {
        if (!isDesktop()) {
          return;
        }

        document.body.classList.toggle("nav-hidden");

        try {
          localStorage.setItem(
            "osq.nav.hidden",
            document.body.classList.contains("nav-hidden") ? "1" : "0"
          );
        } catch (err) {}
      });
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
