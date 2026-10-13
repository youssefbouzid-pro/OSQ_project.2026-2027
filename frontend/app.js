(function () {
  "use strict";

  var api = window.LabAPI;
  var BUDGET = 20;
  var TOKEN_KEY = "cloudy.token";

  var terminating = new Set();
  var currentView = "home";
  var currentGuide = { labId: null, sessionId: null };
  var dialogLoading = false;
  var loginLoading = false;
  var confirmResolver = null;
  var authToken = null;
  var currentUser = null;
  var refs = {};

  var STATE_LABEL = {
    REQUESTED: "Requested",
    PENDING: "Pending",
    PROVISIONING: "Provisioning",
    TAILSCALE_ENROLLMENT: "Enrolling Tailscale",
    READY: "Running",
    EXPIRING: "Expiring",
    TERMINATING: "Ending",
    TERMINATED: "Ended",
    FAILED: "Failed"
  };

  var STATE_BADGE = {
    REQUESTED: "badge-pending",
    PENDING: "badge-pending",
    PROVISIONING: "badge-progress",
    TAILSCALE_ENROLLMENT: "badge-progress",
    READY: "badge-ready",
    EXPIRING: "badge-failed",
    TERMINATING: "badge-progress",
    TERMINATED: "badge-idle",
    FAILED: "badge-failed"
  };

  function esc(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function pad(n) {
    return String(n).padStart(2, "0");
  }

  function formatRemaining(ms) {
    if (ms <= 0) {
      return "00:00:00";
    }
    var total = Math.floor(ms / 1000);
    var h = Math.floor(total / 3600);
    var m = Math.floor((total % 3600) / 60);
    var s = total % 60;
    return pad(h) + ":" + pad(m) + ":" + pad(s);
  }

  function formatTime(ts) {
    var d = new Date(ts);
    return pad(d.getHours()) + ":" + pad(d.getMinutes()) + ":" + pad(d.getSeconds());
  }

  // docs/16 timestamps are ISO-8601 UTC strings, not epoch numbers.
  function parseTs(value) {
    if (!value) {
      return 0;
    }
    if (typeof value === "number") {
      return value;
    }
    var parsed = Date.parse(value);
    return isNaN(parsed) ? 0 : parsed;
  }

  // Presentation-only decorations. The API returns just `family`; these
  // labels and glyphs live here so the wire format stays docs/16-clean.
  var FAMILY_DECORATION = {
    linux: { name: "Linux Sysadmin", glyph: "$_" },
    dba: { name: "Database Administration", glyph: "DB" },
    devops: { name: "DevOps Pipeline", glyph: "CI" }
  };

  function familyName(family) {
    var info = FAMILY_DECORATION[family];
    return info ? info.name : family;
  }

  function familyGlyph(family) {
    var info = FAMILY_DECORATION[family];
    return info ? info.glyph : "";
  }

  // docs/16 "Event Kinds" rendered for the activity feed.
  var EVENT_LABEL = {
    AUTH_SIGN_IN: "Sign in",
    LAB_REQUESTED: "Requested",
    LAB_PROVISIONING: "Provisioning",
    LAB_READY: "Ready",
    LAB_FAILED: "Failed",
    FLAG_SUBMITTED: "Flag",
    FLAG_ACCEPTED: "Flag ok",
    FLAG_REJECTED: "Flag rejected",
    LAB_TERMINATED_BY_USER: "Ended",
    LAB_TERMINATED_BY_TTL: "TTL",
    LAB_TERMINATED_BY_ADMIN: "Admin"
  };

  function displayState(session) {
    if (session.state === "READY" && parseTs(session.expiresAt) - Date.now() <= 300000) {
      return "EXPIRING";
    }
    return session.state;
  }

  function badgeHtml(state) {
    return '<span class="badge ' + STATE_BADGE[state] + '"><span class="badge-dot" aria-hidden="true"></span>' + esc(STATE_LABEL[state]) + "</span>";
  }

  function levelClass(level) {
    return level.toLowerCase();
  }

  function sshCommand(session) {
    return "tailscale ssh student@" + api.fqdn(session);
  }

  function toast(message, kind) {
    var node = document.createElement("div");
    node.className = "toast" + (kind ? " is-" + kind : "");
    node.textContent = message;
    refs.toasts.appendChild(node);
    setTimeout(function () {
      node.remove();
    }, 4500);
  }

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }

    return new Promise(function (resolve, reject) {
      var area = document.createElement("textarea");
      area.value = text;
      area.setAttribute("readonly", "");
      area.style.position = "fixed";
      area.style.opacity = "0";
      document.body.appendChild(area);
      area.select();
      try {
        document.execCommand("copy") ? resolve() : reject();
      } catch (err) {
        reject(err);
      }
      area.remove();
    });
  }

  function openConfirm(options) {
    return new Promise(function (resolve) {
      confirmResolver = resolve;
      refs.confirmTitle.textContent = options.title || "Confirm";
      refs.confirmMessage.textContent = options.message || "";
      refs.confirmSubmit.textContent = options.confirmLabel || "Confirm";
      refs.confirmSubmit.className = "btn " + (options.danger ? "btn-danger" : "btn-primary");
      refs.confirmDialog.showModal();
      refs.confirmCancel.focus();
    });
  }

  function settleConfirm(result) {
    if (!confirmResolver) {
      return;
    }
    var resolve = confirmResolver;
    confirmResolver = null;
    refs.confirmDialog.close();
    resolve(result);
  }

  function canSeeActivity() {
    return !!currentUser && (currentUser.role === "admin" || currentUser.role === "auditor");
  }

  function canSeeBudget() {
    return !!currentUser && currentUser.role === "admin";
  }

  function findSession(id) {
    return api.listSessions(authToken).find(function (s) {
      return s.sessionId === id;
    });
  }

  function setView(view) {
    if (view === "activity" && !canSeeActivity()) {
      view = "home";
    }

    if (view === "lab-guide" && !currentGuide.labId) {
      view = "catalog";
    }

    currentView = view;

    document.querySelectorAll(".view").forEach(function (section) {
      section.hidden = section.id !== "view-" + view;
    });

    document.querySelectorAll(".nav-link").forEach(function (btn) {
      var active = btn.dataset.view === view;
      btn.classList.toggle("is-active", active);
      if (active) {
        btn.setAttribute("aria-current", "page");
      } else {
        btn.removeAttribute("aria-current");
      }
    });

    var crumbMap = {
      home: "Home",
      catalog: "Lab Catalog",
      "my-labs": "My Labs",
      "getting-started": "Getting Started",
      "access-setup": "Access Setup",
      help: "Help & FAQ",
      "lab-guide": "Lab Guide",
      activity: "Activity"
    };

    refs.crumbCurrent.textContent = crumbMap[view] || "Home";
    closeSidebar();
    document.getElementById("main").focus();
  }

  function openLabGuide(labId, sessionId) {
    currentGuide = {
      labId: labId,
      sessionId: sessionId || null
    };

    setView("lab-guide");
    renderLabGuide();

    var lab = api.getLab(authToken, labId);
    if (lab && refs.crumbCurrent) {
      refs.crumbCurrent.textContent = lab.name;
    }
  }

  function renderRoleVisibility() {
    document.querySelectorAll(".admin-only").forEach(function (el) {
      el.hidden = !canSeeActivity();
    });
  }

  function updateBudget() {
    if (!refs.budgetPill) {
      return;
    }

    if (!canSeeBudget()) {
      refs.budgetPill.hidden = true;
      return;
    }

    var cost = api.totalCost(authToken);
    refs.budgetPill.hidden = false;
    refs.budgetPill.textContent = "$" + cost.toFixed(2) + " / $" + BUDGET.toFixed(2);
  }

  function sessionLine(session) {
    var lab = api.getLab(authToken, session.labId);
    var state = displayState(session);
    var remaining = api.isActive(session) ? parseTs(session.expiresAt) - Date.now() : 0;
    var percent = api.isActive(session) ? Math.max(0, Math.min(100, (remaining / (lab.ttlMinutes * 60000)) * 100)) : 0;
    var barClass = percent < 15 ? "is-critical" : percent < 30 ? "is-warning" : "";

    return `
      <div class="session-row">
        <div class="session-row-main">
          <span class="cell-strong">${esc(lab.name)}</span>
          <span class="cell-id">${esc(session.sessionId)} · ${esc(lab.level)}</span>
        </div>
        <div class="session-row-state" data-session-state="${session.sessionId}">${badgeHtml(state)}</div>
        <div class="session-row-ttl">
          ${api.isActive(session) ? `
            <span class="mono" data-countdown="${session.sessionId}">${formatRemaining(remaining)}</span>
            <div class="ttl-bar"><div class="ttl-bar-fill ${barClass}" data-ttlbar="${session.sessionId}" style="width:${percent}%"></div></div>
          ` : '<span class="muted">-</span>'}
        </div>
        <div class="session-row-actions">
          <button type="button" class="btn btn-ghost" data-guide="${session.labId}" data-session="${session.sessionId}">Guide</button>
          ${session.state === "READY" ? `<button type="button" class="btn btn-secondary" data-action="copy" data-id="${session.sessionId}">Connect</button>` : ""}
          ${api.canDestroy(authToken, session) && api.isActive(session) && session.state !== "TERMINATING" ? `<button type="button" class="btn btn-danger" data-action="destroy" data-id="${session.sessionId}">End</button>` : ""}
        </div>
      </div>
    `;
  }

  function renderHome() {
    if (!authToken) {
      return;
    }

    var sessions = api.listSessions(authToken);
    var active = sessions
      .filter(function (s) {
        return api.isActive(s);
      })
      .sort(function (a, b) {
        return a.expiresAt - b.expiresAt;
      })[0];

    if (active) {
      var lab = api.getLab(authToken, active.labId);
      var state = displayState(active);
      var remaining = active.expiresAt - Date.now();

      refs.continueLab.innerHTML = `
        <div class="continue-card">
          <div class="continue-top">
            <div>
              <p class="continue-title">${esc(lab.name)}</p>
              <p class="cell-id">${esc(active.sessionId)} · ${esc(lab.level)}</p>
            </div>
            <div data-session-state="${active.sessionId}">${badgeHtml(state)}</div>
          </div>
          <div class="continue-ttl">
            <span class="mono" data-countdown="${active.sessionId}">${formatRemaining(remaining)}</span>
            <div class="ttl-bar ttl-bar-wide"><div class="ttl-bar-fill" data-ttlbar="${active.sessionId}" style="width:${Math.max(0, Math.min(100, (remaining / (active.ttlMinutes * 60000)) * 100))}%"></div></div>
          </div>
          <div class="continue-actions">
            <button type="button" class="btn btn-primary" data-guide="${active.labId}" data-session="${active.sessionId}">Open Lab Guide</button>
            ${active.state === "READY" ? `<button type="button" class="btn btn-secondary" data-action="copy" data-id="${active.sessionId}">Copy SSH</button>` : ""}
            ${api.canDestroy(authToken, active) && active.state !== "TERMINATING" ? `<button type="button" class="btn btn-danger" data-action="destroy" data-id="${active.sessionId}">End Lab</button>` : ""}
          </div>
        </div>
      `;
    } else {
      refs.continueLab.innerHTML = `
        <div class="empty-mini">
          <p>You have no active lab.</p>
          <button type="button" class="btn btn-primary" data-goto="catalog">Start a Lab</button>
        </div>
      `;
    }

    var recommended = api.listLabs(authToken).filter(function (lab) {
      return lab.level === "Beginner";
    });

    refs.recommendedLabs.innerHTML = recommended
      .map(function (lab) {
        return `
          <div class="recommended-item">
            <div>
              <p class="cell-strong">${esc(lab.name)}</p>
              <p class="cell-id">${esc(familyName(lab.family))} · ${esc(lab.level)}</p>
            </div>
            <div class="recommended-actions">
              <button type="button" class="btn btn-ghost" data-guide="${lab.labId}">Guide</button>
              <button type="button" class="btn btn-secondary" data-open-request="${lab.labId}" ${api.canStart(authToken) ? "" : "disabled"}>Start</button>
            </div>
          </div>
        `;
      })
      .join("");

    refs.setupChecklist.innerHTML = `
      <div class="setup-item"><span class="setup-check">✓</span><span>Signed in with your lab token</span></div>
      <div class="setup-item"><span class="setup-check">✓</span><span>Understand the 60-minute lab limit</span></div>
      <div class="setup-item"><span class="setup-link"><button type="button" class="btn btn-ghost" data-goto="access-setup">Set up Tailscale access</button></span></div>
      <div class="setup-item"><span class="setup-link"><button type="button" class="btn btn-ghost" data-goto="catalog">Browse the lab catalog</button></span></div>
    `;

    var recent = sessions.slice(0, 5);
    refs.recentSessions.innerHTML = recent.length
      ? recent.map(sessionLine).join("")
      : '<p class="widget-empty">No lab sessions yet.</p>';
  }

  function renderCatalog() {
    if (!authToken) {
      return;
    }

    var q = refs.catalogSearch ? refs.catalogSearch.value.trim().toLowerCase() : "";
    var family = refs.catalogFamily ? refs.catalogFamily.value : "all";
    var level = refs.catalogLevel ? refs.catalogLevel.value : "all";

    var labs = api.listLabs(authToken).filter(function (lab) {
      var haystack = [lab.name, familyName(lab.family), lab.level, lab.description].join(" ").toLowerCase();
      var matchesQuery = !q || haystack.indexOf(q) !== -1;
      var matchesFamily = family === "all" || lab.family === family;
      var matchesLevel = level === "all" || lab.level.toLowerCase() === level;
      return matchesQuery && matchesFamily && matchesLevel;
    });

    if (labs.length === 0) {
      refs.catalogGrid.innerHTML = '<div class="empty-mini"><p>No labs match your filters.</p></div>';
      return;
    }

    refs.catalogGrid.innerHTML = labs
      .map(function (lab) {
        return `
          <article class="lab-card">
            <div class="lab-card-head">
              <span class="lab-glyph" aria-hidden="true">${esc(familyGlyph(lab.family))}</span>
              <div class="lab-card-title">
                <h2>${esc(lab.name)}</h2>
                <p class="lab-type-tag">${esc(familyName(lab.family))}</p>
              </div>
              <span class="level-badge level-${levelClass(lab.level)}">${esc(lab.level)}</span>
            </div>
            <p>${esc(lab.description)}</p>
            <div class="lab-meta">
              <span class="tag">${esc(lab.instanceType)}</span>
              <span class="tag">60 min</span>
              <span class="tag">${lab.tasks.length} tasks</span>
            </div>
            <div class="lab-actions">
              <button type="button" class="btn btn-secondary" data-guide="${lab.labId}">Lab Guide</button>
              <button type="button" class="btn btn-primary" data-open-request="${lab.labId}" ${api.canStart(authToken) ? "" : "disabled"}>Start Lab</button>
            </div>
          </article>
        `;
      })
      .join("");
  }

  function renderMyLabs() {
    if (!authToken) {
      return;
    }

    var sessions = api.listSessions(authToken);

    if (sessions.length === 0) {
      refs.mylabsRows.innerHTML = "";
      refs.mylabsEmpty.hidden = false;
      return;
    }

    refs.mylabsEmpty.hidden = true;
    refs.mylabsRows.innerHTML = sessions.map(sessionLine).join("");
  }

  function renderActivity() {
    if (!authToken || !refs.activityFeed) {
      return;
    }

    var feed = api.listActivity();

    refs.activityFeed.innerHTML = feed
      .map(function (entry) {
        // docs/16 activity levels: INFO is routine (grey), WARN is orange,
        // ERROR is red.
        var marker = entry.level === "ERROR" ? " is-policy" : entry.level === "WARN" ? " is-drift" : "";
        return `
          <li class="feed-item">
            <time class="feed-time">${formatTime(parseTs(entry.at))}</time>
            <span class="feed-marker${marker}" aria-hidden="true"></span>
            <span class="feed-body">
              <span class="feed-kind">${esc(EVENT_LABEL[entry.kind] || entry.kind)}</span>
              ${esc(entry.message)}
            </span>
          </li>
        `;
      })
      .join("");
  }

  function renderLabGuide() {
    if (!authToken || !refs.labGuideContent) {
      return;
    }

    var lab = api.getLab(authToken, currentGuide.labId);
    if (!lab) {
      refs.labGuideContent.innerHTML = '<div class="panel"><div class="panel-body">Lab guide not found.</div></div>';
      return;
    }

    var session = currentGuide.sessionId ? findSession(currentGuide.sessionId) : null;
    var completed = session ? Object.keys(session.flags || {}).length : 0;
    var total = lab.tasks.length;

    var sessionBox = "";

    if (session) {
      var state = displayState(session);
      var remaining = api.isActive(session) ? parseTs(session.expiresAt) - Date.now() : 0;

      sessionBox = `
        <div class="guide-session panel-subtle">
          <div class="guide-session-row">
            <span class="detail-label">Session</span>
            <span class="mono">${esc(session.sessionId)}</span>
          </div>
          <div class="guide-session-row">
            <span class="detail-label">Status</span>
            <span data-session-state="${session.sessionId}">${badgeHtml(state)}</span>
          </div>
          <div class="guide-session-row">
            <span class="detail-label">Time left</span>
            <span class="mono" data-countdown="${session.sessionId}">${api.isActive(session) ? formatRemaining(remaining) : "-"}</span>
          </div>
          ${session.state === "READY" ? `
            <div class="guide-session-row">
              <span class="detail-label">Connect</span>
              <div class="ssh-block">
                <code>$ ${esc(sshCommand(session))}</code>
                <button type="button" class="btn btn-ghost" data-action="copy" data-id="${session.sessionId}">Copy</button>
              </div>
            </div>
          ` : ""}
        </div>
      `;
    } else {
      sessionBox = `
        <div class="guide-session panel-subtle">
          <p class="muted">Start this lab to receive a temporary environment and submit flags.</p>
          <div>
            <button type="button" class="btn btn-primary" data-open-request="${lab.labId}" ${api.canStart(authToken) ? "" : "disabled"}>Start Lab</button>
          </div>
        </div>
      `;
    }

    var tasksHtml = lab.tasks
      .map(function (task) {
        var done = !!(session && session.flags && session.flags[task.taskId]);

        return `
          <div class="task-card ${done ? "is-done" : ""}">
            <div class="task-head">
              <span class="task-title">${esc(task.title)}</span>
              <span class="tag">${done ? "Completed" : "Flag required"}</span>
            </div>
            <p class="task-instruction">${esc(task.instruction)}</p>
            <details class="task-hint">
              <summary>Hint</summary>
              <p>${esc(task.hint)}</p>
            </details>
            ${session && api.isActive(session) && !done ? `
              <div class="flag-row">
                <input class="input" type="text" placeholder="CB-..." data-flag-input="${task.taskId}" aria-label="Flag for ${esc(task.title)}">
                <button type="button" class="btn btn-secondary" data-submit-flag="${task.taskId}" data-session="${session.sessionId}">Submit Flag</button>
              </div>
            ` : ""}
            ${done ? '<p class="flag-done">Flag accepted.</p>' : ""}
            ${!session ? '<p class="muted">Start the lab to submit flags.</p>' : ""}
          </div>
        `;
      })
      .join("");

    refs.labGuideContent.innerHTML = `
      <div class="guide-grid">
        <div class="panel guide-panel">
          <div class="panel-head">
            <div>
              <h2>${esc(lab.name)}</h2>
              <p class="cell-id">${esc(familyName(lab.family))} · ${esc(lab.level)} · 60 minutes</p>
            </div>
            <span class="level-badge level-${levelClass(lab.level)}">${esc(lab.level)}</span>
          </div>
          <div class="panel-body">
            <p>${esc(lab.description)}</p>
            <div class="lab-meta">
              <span class="tag">${esc(lab.instanceType)}</span>
              <span class="tag">Tailscale SSH</span>
              <span class="tag">${lab.tasks.length} tasks</span>
            </div>
            ${sessionBox}
          </div>
        </div>

        <div class="panel guide-panel">
          <div class="panel-head">
            <h2>Tasks & Flags</h2>
            <span class="panel-note">${completed}/${total} completed</span>
          </div>
          <div class="panel-body">
            <p class="muted">Flags are placed inside the lab environment by the lab scenario. Complete each task, find the flag, and submit it here.</p>
            ${tasksHtml}
          </div>
        </div>
      </div>
    `;
  }

  function renderLabSelect() {
    if (!refs.labSelect) {
      return;
    }

    refs.labSelect.innerHTML = api
      .listLabs()
      .map(function (lab) {
        return `<option value="${lab.labId}">${esc(familyName(lab.family))} · ${esc(lab.level)} · ${esc(lab.name)}</option>`;
      })
      .join("");
  }

  function renderAll() {
    renderRoleVisibility();
    renderHome();
    renderCatalog();
    renderMyLabs();
    renderActivity();
    renderLabGuide();
    renderLabSelect();
    updateBudget();
  }

  function openDialog(preselect) {
    renderLabSelect();

    if (preselect && refs.labSelect) {
      refs.labSelect.value = preselect;
    }

    refs.formError.hidden = true;

    var q = api.quota(authToken);
    if (q) {
      refs.quotaHint.hidden = false;
      refs.quotaHint.textContent = "Current quota: " + q.active + " of " + q.max + " active labs.";
    } else {
      refs.quotaHint.hidden = true;
    }

    refs.requestDialog.showModal();
    refs.labSelect.focus();
  }

  function setLoading(loading) {
    dialogLoading = loading;
    refs.submit.classList.toggle("is-loading", loading);
    refs.submit.disabled = loading;
    refs.cancel.disabled = loading;
    refs.closeDialog.disabled = loading;
  }

  function onSubmitRequest(event) {
    event.preventDefault();
    if (dialogLoading) {
      return;
    }

    var labId = refs.labSelect.value;
    if (!labId) {
      refs.formError.textContent = "Select a lab before launching.";
      refs.formError.hidden = false;
      return;
    }

    refs.formError.hidden = true;
    setLoading(true);

    api
      .startLab(authToken, { labId: labId })
      .then(function (session) {
        setLoading(false);
        refs.requestDialog.close();
        toast("Starting " + api.getLab(authToken, labId).name, "success");
        openLabGuide(labId, session.sessionId);
        renderAll();
      })
      .catch(function (err) {
        setLoading(false);
        refs.formError.textContent = err.message || "Failed to start lab.";
        refs.formError.hidden = false;
      });
  }

  function handleAction(btn) {
    var action = btn.dataset.action;
    var id = btn.dataset.id;
    var session = findSession(id);

    if (!session) {
      return;
    }

    if (action === "copy") {
      copyText(sshCommand(session)).then(
        function () {
          toast("SSH command copied", "success");
        },
        function () {
          toast("Copy failed", "error");
        }
      );
      return;
    }

    if (action === "destroy") {
      var lab = api.getLab(authToken, session.labId);

      openConfirm({
        title: "End lab session",
        message: "End " + lab.name + " (" + session.sessionId + ")? The environment will be destroyed.",
        confirmLabel: "End Lab",
        danger: true
      }).then(function (confirmed) {
        if (!confirmed) {
          return;
        }

        api
          .destroyLab(authToken, id, "operator")
          .then(function () {
            toast(session.sessionId + " ended", "info");
            renderAll();
          })
          .catch(function (err) {
            toast(err.message || "Could not end lab", "error");
          });
      });
    }
  }

  function handleFlagSubmit(btn) {
    var taskId = btn.dataset.submitFlag;
    var sessionId = btn.dataset.session;
    var input = document.querySelector('[data-flag-input="' + taskId + '"]');
    var value = input ? input.value : "";

    btn.disabled = true;

    api
      .submitFlag(authToken, sessionId, taskId, value)
      .then(function (result) {
        btn.disabled = false;

        if (result.correct) {
          toast("Flag accepted", "success");
        } else {
          toast("Incorrect flag", "error");
        }

        renderAll();
      })
      .catch(function (err) {
        btn.disabled = false;
        toast(err.message || "Could not submit flag", "error");
      });
  }

  function tick() {
    if (!authToken) {
      return;
    }

    var sessions = api.listSessions(authToken);

    sessions.forEach(function (session) {
      var remaining = parseTs(session.expiresAt) - Date.now();

      if (session.state === "READY" && remaining <= 0 && !terminating.has(session.sessionId)) {
        terminating.add(session.sessionId);

        api
          .destroyLab(authToken, session.sessionId, "ttl")
          .then(function () {
            terminating.delete(session.sessionId);
            toast(session.sessionId + " expired", "info");
            renderAll();
          })
          .catch(function () {
            terminating.delete(session.sessionId);
          });
      }
    });

    sessions.forEach(function (session) {
      if (!api.isActive(session)) {
        return;
      }

      var lab = api.getLab(authToken, session.labId);
      var ttlMinutes = (lab && lab.ttlMinutes) || 60;
      var remaining = parseTs(session.expiresAt) - Date.now();
      var percent = Math.max(0, Math.min(100, (remaining / (ttlMinutes * 60000)) * 100));

      var countdown = document.querySelector('[data-countdown="' + session.sessionId + '"]');
      if (countdown) {
        countdown.textContent = formatRemaining(remaining);
      }

      var bar = document.querySelector('[data-ttlbar="' + session.sessionId + '"]');
      if (bar) {
        bar.style.width = percent + "%";
        bar.className = "ttl-bar-fill " + (percent < 15 ? "is-critical" : percent < 30 ? "is-warning" : "");
      }

      var state = displayState(session);
      var stateCell = document.querySelector('[data-session-state="' + session.sessionId + '"]');
      if (stateCell && stateCell.dataset.state !== state) {
        stateCell.dataset.state = state;
        stateCell.innerHTML = badgeHtml(state);
      }
    });

    updateBudget();
  }

  function showApp(user) {
    currentUser = user;
    authToken = user.token;

    try {
      sessionStorage.setItem(TOKEN_KEY, user.token);
    } catch (err) {}

    refs.authScreen.hidden = true;
    refs.appShell.hidden = false;

    refs.userId.textContent = user.userId;
    refs.userRole.textContent = user.role.toUpperCase();
    refs.userAvatar.textContent = user.userId.charAt(0).toUpperCase();

    refs.homeHeading.textContent = "Welcome back, " + user.userId;
    refs.homeSub.textContent =
      user.role === "student"
        ? "Start isolated learning labs, complete tasks, and submit flags before your session expires."
        : user.role === "admin"
          ? "Manage lab sessions, monitor usage, and support learners."
          : "Review platform activity and lab session events.";

    currentView = user.role === "auditor" ? "activity" : "home";

    renderAll();
    setView(currentView);
  }

  function setLoginLoading(loading) {
    loginLoading = loading;
    refs.loginSubmit.classList.toggle("is-loading", loading);
    refs.loginSubmit.disabled = loading;
  }

  function signIn(token, silent) {
    if (loginLoading) {
      return Promise.resolve();
    }

    refs.loginError.hidden = true;
    setLoginLoading(true);

    return api
      .me(token)
      .then(function (user) {
        setLoginLoading(false);
        showApp(user);
        if (!silent) {
          toast("Signed in as " + user.userId, "success");
        }
      })
      .catch(function (err) {
        setLoginLoading(false);

        if (silent) {
          try {
            sessionStorage.removeItem(TOKEN_KEY);
          } catch (e) {}
          return;
        }

        refs.loginError.textContent = err.message || "Sign-in failed.";
        refs.loginError.hidden = false;
        refs.tokenInput.focus();
      });
  }

  function signOut() {
    if (refs.requestDialog.open) {
      refs.requestDialog.close();
    }

    if (refs.confirmDialog.open) {
      refs.confirmDialog.close();
    }

    terminating.clear();
    currentGuide = { labId: null, sessionId: null };
    currentView = "home";

    try {
      sessionStorage.removeItem(TOKEN_KEY);
    } catch (err) {}

    authToken = null;
    currentUser = null;

    refs.appShell.hidden = true;
    refs.authScreen.hidden = false;
    refs.tokenInput.value = "";
    refs.loginError.hidden = true;
    closeSidebar();
    toast("Signed out", "info");
  }

  function toggleSidebar() {
    refs.sidebar.classList.toggle("is-open");
    refs.sidebarOverlay.classList.toggle("is-visible");
  }

  function closeSidebar() {
    refs.sidebar.classList.remove("is-open");
    refs.sidebarOverlay.classList.remove("is-visible");
  }

  function bind() {
    document.querySelectorAll(".nav-link").forEach(function (btn) {
      btn.addEventListener("click", function () {
        setView(btn.dataset.view);
      });
    });

    refs.mobileMenu.addEventListener("click", toggleSidebar);
    refs.sidebarOverlay.addEventListener("click", closeSidebar);

    refs.loginForm.addEventListener("submit", function (event) {
      event.preventDefault();
      var token = refs.tokenInput.value.trim();
      if (!token) {
        refs.loginError.textContent = "Enter your personal access token.";
        refs.loginError.hidden = false;
        return;
      }
      signIn(token, false);
    });

    document.getElementById("demo-tokens").addEventListener("click", function (event) {
      var btn = event.target.closest("[data-token]");
      if (!btn) {
        return;
      }
      refs.tokenInput.value = btn.dataset.token;
      refs.loginError.hidden = true;
      refs.tokenInput.focus();
    });

    refs.signout.addEventListener("click", signOut);

    refs.catalogSearch.addEventListener("input", renderCatalog);
    refs.catalogFamily.addEventListener("change", renderCatalog);
    refs.catalogLevel.addEventListener("change", renderCatalog);

    refs.requestForm.addEventListener("submit", onSubmitRequest);

    refs.cancel.addEventListener("click", function () {
      if (!dialogLoading) {
        refs.requestDialog.close();
      }
    });

    refs.closeDialog.addEventListener("click", function () {
      if (!dialogLoading) {
        refs.requestDialog.close();
      }
    });

    refs.requestDialog.addEventListener("cancel", function (event) {
      if (dialogLoading) {
        event.preventDefault();
      }
    });

    refs.confirmCancel.addEventListener("click", function () {
      settleConfirm(false);
    });

    refs.confirmSubmit.addEventListener("click", function () {
      settleConfirm(true);
    });

    refs.confirmClose.addEventListener("click", function () {
      settleConfirm(false);
    });

    refs.confirmDialog.addEventListener("cancel", function () {
      settleConfirm(false);
    });

    document.addEventListener("click", function (event) {
      var gotoBtn = event.target.closest("[data-goto]");
      if (gotoBtn) {
        setView(gotoBtn.dataset.goto);
        return;
      }

      var opener = event.target.closest("[data-open-request]");
      if (opener && !opener.disabled) {
        openDialog(opener.dataset.openRequest || null);
        return;
      }

      var guideBtn = event.target.closest("[data-guide]");
      if (guideBtn) {
        openLabGuide(guideBtn.dataset.guide, guideBtn.dataset.session || null);
        return;
      }

      var actionBtn = event.target.closest("button[data-action]");
      if (actionBtn) {
        handleAction(actionBtn);
        return;
      }

      var flagBtn = event.target.closest("[data-submit-flag]");
      if (flagBtn) {
        handleFlagSubmit(flagBtn);
      }
    });
  }

  function init() {
    refs = {
      authScreen: document.getElementById("auth-screen"),
      loginForm: document.getElementById("login-form"),
      tokenInput: document.getElementById("token-input"),
      loginError: document.getElementById("login-error"),
      loginSubmit: document.getElementById("login-submit"),

      appShell: document.getElementById("app-shell"),
      sidebar: document.getElementById("sidebar"),
      sidebarOverlay: document.getElementById("sidebar-overlay"),
      mobileMenu: document.getElementById("mobile-menu"),

      crumbCurrent: document.getElementById("crumb-current"),
      budgetPill: document.getElementById("budget-pill"),

      userId: document.getElementById("user-id"),
      userRole: document.getElementById("user-role"),
      userAvatar: document.getElementById("user-avatar"),
      signout: document.getElementById("signout"),

      homeHeading: document.getElementById("home-heading"),
      homeSub: document.getElementById("home-sub"),
      continueLab: document.getElementById("continue-lab"),
      recommendedLabs: document.getElementById("recommended-labs"),
      setupChecklist: document.getElementById("setup-checklist"),
      recentSessions: document.getElementById("recent-sessions"),

      catalogSearch: document.getElementById("catalog-search"),
      catalogFamily: document.getElementById("catalog-family"),
      catalogLevel: document.getElementById("catalog-level"),
      catalogGrid: document.getElementById("catalog-grid"),

      mylabsRows: document.getElementById("mylabs-rows"),
      mylabsEmpty: document.getElementById("mylabs-empty"),

      labGuideContent: document.getElementById("lab-guide-content"),

      activityFeed: document.getElementById("activity-feed"),

      toasts: document.getElementById("toast-region"),

      requestDialog: document.getElementById("request-dialog"),
      requestForm: document.getElementById("request-form"),
      labSelect: document.getElementById("lab-select"),
      formError: document.getElementById("form-error"),
      submit: document.getElementById("submit-request"),
      cancel: document.getElementById("cancel-request"),
      closeDialog: document.getElementById("close-dialog"),
      quotaHint: document.getElementById("quota-hint"),

      confirmDialog: document.getElementById("confirm-dialog"),
      confirmTitle: document.getElementById("confirm-title"),
      confirmMessage: document.getElementById("confirm-message"),
      confirmCancel: document.getElementById("confirm-cancel"),
      confirmSubmit: document.getElementById("confirm-submit"),
      confirmClose: document.getElementById("confirm-close")
    };

    bind();

    api.subscribe(function (type) {
      if (!authToken) {
        return;
      }

      if (type === "session") {
        renderAll();
      }

      if (type === "activity") {
        renderActivity();
      }
    });

    var stored = null;
    try {
      stored = sessionStorage.getItem(TOKEN_KEY);
    } catch (err) {}

    if (stored) {
      signIn(stored, true);
    }

    setInterval(tick, 1000);
  }

  document.addEventListener("DOMContentLoaded", init);
})();
