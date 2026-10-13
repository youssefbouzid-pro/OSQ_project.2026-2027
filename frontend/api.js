(function () {
  "use strict";

  /*
   * Browser mock of the CloudyBTTounsi API.
   *
   * Every object below is shaped exactly like the real service
   * (docs/16 "API and Data Model"). Switching off the mock is a transport
   * change only: replace the bodies of the endpoint functions with fetch()
   * calls and the rest of the app keeps working unchanged.
   *
   * Server-side only, never serialized: CATALOG[*].tasks[*].expectedFlag.
   */

  var TS_NET_DOMAIN = "cloudybt-tounsi.ts.net";
  var MAX_PLATFORM_ACTIVE_LABS = 4;
  var INSTANCE_HOURLY_COST = {
    "t4g.micro": 0.0084,
    "t4g.small": 0.0168,
    "t4g.medium": 0.0336
  };
  var PROVISIONING_DELAYS = [700, 1300, 900, 1100];
  var STATE_FLOW = ["REQUESTED", "PENDING", "PROVISIONING", "TAILSCALE_ENROLLMENT", "READY"];

  // docs/16 "Recommended DynamoDB Tables" -> labs. expectedFlag stays here
  // and is stripped by publicLab() before anything reaches the app.
  var CATALOG = [
  {
    "labId": "linux-beginner",
    "family": "linux",
    "level": "Beginner",
    "name": "Linux Basics: Files and Permissions",
    "description": "Learn essential Linux navigation, file inspection, and permission management.",
    "instanceType": "t4g.micro",
    "amiParameter": "ami-approved-linux-beginner",
    "ttlMinutes": 60,
    "tasks": [
      {
        "taskId": "linux-b-1",
        "title": "Locate the application config",
        "instruction": "Connect to the lab and find the config file inside /opt/app.",
        "hint": "Use: ls -la /opt/app",
        "expectedFlag": "CB-LINUX-B-01"
      },
      {
        "taskId": "linux-b-2",
        "title": "Fix the config permissions",
        "instruction": "Make /opt/app/config.yml readable only by appuser.",
        "hint": "Use: chown and chmod",
        "expectedFlag": "CB-LINUX-B-02"
      }
    ]
  },
  {
    "labId": "linux-intermediate",
    "family": "linux",
    "level": "Intermediate",
    "name": "Linux Services and Users",
    "description": "Manage users, groups, and systemd services in a realistic Linux environment.",
    "instanceType": "t4g.small",
    "amiParameter": "ami-approved-linux-intermediate",
    "ttlMinutes": 60,
    "tasks": [
      {
        "taskId": "linux-i-1",
        "title": "Create a service account",
        "instruction": "Create a system user named webapp with no login shell.",
        "hint": "Use: useradd -r -s /usr/sbin/nologin webapp",
        "expectedFlag": "CB-LINUX-I-01"
      },
      {
        "taskId": "linux-i-2",
        "title": "Restart the broken service",
        "instruction": "The webapp service is failing. Diagnose and restart it.",
        "hint": "Use: systemctl status webapp",
        "expectedFlag": "CB-LINUX-I-02"
      }
    ]
  },
  {
    "labId": "linux-advanced",
    "family": "linux",
    "level": "Advanced",
    "name": "Linux Troubleshooting Challenge",
    "description": "Diagnose a broken web service caused by permissions, ports, and configuration drift.",
    "instanceType": "t4g.small",
    "amiParameter": "ami-approved-linux-advanced",
    "ttlMinutes": 60,
    "tasks": [
      {
        "taskId": "linux-a-1",
        "title": "Find the listening port issue",
        "instruction": "The app should listen on port 8080 but it is not reachable.",
        "hint": "Use: ss -tulpn",
        "expectedFlag": "CB-LINUX-A-01"
      },
      {
        "taskId": "linux-a-2",
        "title": "Restore the service",
        "instruction": "Fix the configuration and make the app respond on localhost:8080.",
        "hint": "Use: curl http://localhost:8080",
        "expectedFlag": "CB-LINUX-A-02"
      }
    ]
  },
  {
    "labId": "dba-beginner",
    "family": "dba",
    "level": "Beginner",
    "name": "PostgreSQL Basics",
    "description": "Connect to PostgreSQL, inspect databases, and run basic SQL queries.",
    "instanceType": "t4g.small",
    "amiParameter": "ami-approved-dba-beginner",
    "ttlMinutes": 60,
    "tasks": [
      {
        "taskId": "dba-b-1",
        "title": "Connect to PostgreSQL",
        "instruction": "Connect to the local PostgreSQL instance using psql.",
        "hint": "Use: psql -U postgres",
        "expectedFlag": "CB-DBA-B-01"
      },
      {
        "taskId": "dba-b-2",
        "title": "List databases",
        "instruction": "List all databases and find the training database.",
        "hint": "Use: \\\\l",
        "expectedFlag": "CB-DBA-B-02"
      }
    ]
  },
  {
    "labId": "dba-intermediate",
    "family": "dba",
    "level": "Intermediate",
    "name": "PostgreSQL Backup and Restore",
    "description": "Practice database backup, restore, and user management.",
    "instanceType": "t4g.small",
    "amiParameter": "ami-approved-dba-intermediate",
    "ttlMinutes": 60,
    "tasks": [
      {
        "taskId": "dba-i-1",
        "title": "Backup the database",
        "instruction": "Create a backup of the training database using pg_dump.",
        "hint": "Use: pg_dump training > training.sql",
        "expectedFlag": "CB-DBA-I-01"
      },
      {
        "taskId": "dba-i-2",
        "title": "Create a read-only user",
        "instruction": "Create a database user named analyst with read-only access.",
        "hint": "Use: CREATE ROLE and GRANT",
        "expectedFlag": "CB-DBA-I-02"
      }
    ]
  },
  {
    "labId": "dba-advanced",
    "family": "dba",
    "level": "Advanced",
    "name": "PostgreSQL Performance and Recovery",
    "description": "Investigate slow queries, restore corrupted data, and verify integrity.",
    "instanceType": "t4g.medium",
    "amiParameter": "ami-approved-dba-advanced",
    "ttlMinutes": 60,
    "tasks": [
      {
        "taskId": "dba-a-1",
        "title": "Find the slow query",
        "instruction": "Identify the query causing high load in pg_stat_activity.",
        "hint": "Use: SELECT * FROM pg_stat_activity;",
        "expectedFlag": "CB-DBA-A-01"
      },
      {
        "taskId": "dba-a-2",
        "title": "Restore the missing table",
        "instruction": "Restore the orders table from the provided backup file.",
        "hint": "Use: psql and the backup in /var/backups",
        "expectedFlag": "CB-DBA-A-02"
      }
    ]
  },
  {
    "labId": "devops-beginner",
    "family": "devops",
    "level": "Beginner",
    "name": "Containers Basics",
    "description": "Run your first container and inspect the runtime environment.",
    "instanceType": "t4g.small",
    "amiParameter": "ami-approved-devops-beginner",
    "ttlMinutes": 60,
    "tasks": [
      {
        "taskId": "devops-b-1",
        "title": "Run a container",
        "instruction": "Run the provided hello-world container image.",
        "hint": "Use: docker run",
        "expectedFlag": "CB-DEVOPS-B-01"
      },
      {
        "taskId": "devops-b-2",
        "title": "Inspect running containers",
        "instruction": "List running containers and find the container ID.",
        "hint": "Use: docker ps",
        "expectedFlag": "CB-DEVOPS-B-02"
      }
    ]
  },
  {
    "labId": "devops-intermediate",
    "family": "devops",
    "level": "Intermediate",
    "name": "Build and Deploy",
    "description": "Build a container image and deploy a small web service.",
    "instanceType": "t4g.small",
    "amiParameter": "ami-approved-devops-intermediate",
    "ttlMinutes": 60,
    "tasks": [
      {
        "taskId": "devops-i-1",
        "title": "Build the image",
        "instruction": "Build the app image from /home/student/app.",
        "hint": "Use: docker build -t cloudy-app .",
        "expectedFlag": "CB-DEVOPS-I-01"
      },
      {
        "taskId": "devops-i-2",
        "title": "Deploy the app",
        "instruction": "Run the app on port 8080 and verify it responds.",
        "hint": "Use: docker run -p 8080:8080 cloudy-app",
        "expectedFlag": "CB-DEVOPS-I-02"
      }
    ]
  },
  {
    "labId": "devops-advanced",
    "family": "devops",
    "level": "Advanced",
    "name": "Pipeline Troubleshooting",
    "description": "Fix a broken CI/CD deployment pipeline and restore service health.",
    "instanceType": "t4g.medium",
    "amiParameter": "ami-approved-devops-advanced",
    "ttlMinutes": 60,
    "tasks": [
      {
        "taskId": "devops-a-1",
        "title": "Find the failed pipeline step",
        "instruction": "Inspect the pipeline logs and identify the failed stage.",
        "hint": "Use: cat /var/log/pipeline.log",
        "expectedFlag": "CB-DEVOPS-A-01"
      },
      {
        "taskId": "devops-a-2",
        "title": "Restore the deployment",
        "instruction": "Fix the deployment script and restart the app service.",
        "hint": "Use: ./deploy.sh",
        "expectedFlag": "CB-DEVOPS-A-02"
      }
    ]
  }
];

  // docs/16 -> users. The plaintext token only exists in this mock; the
  // real service stores tokenHash and prints the token once.
  var USERS = [
    {
      token: "cldy_token_student01",
      userId: "student-01",
      email: "student-01@cloudy.tn",
      role: "student",
      maxConcurrentLabs: 4,
      isActive: true
    },
    {
      token: "cldy_token_admin01",
      userId: "admin-01",
      email: "admin@cloudy.tn",
      role: "admin",
      maxConcurrentLabs: null,
      isActive: true
    },
    {
      token: "cldy_token_auditor01",
      userId: "auditor-01",
      email: "auditor@cloudy.tn",
      role: "auditor",
      maxConcurrentLabs: null,
      isActive: true
    },
    {
      token: "cldy_token_revoked",
      userId: "student-99",
      email: "revoked@cloudy.tn",
      role: "student",
      maxConcurrentLabs: 4,
      isActive: false
    }
  ];

  var listeners = [];
  var eventSeq = 1;
  var sessionSeq = 100;

  function now() {
    return Date.now();
  }

  function iso(at) {
    return new Date(at || now()).toISOString().replace(/\.\d{3}Z$/, "Z");
  }

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

  function randomId() {
    sessionSeq += Math.floor(Math.random() * 90) + 7;
    return "sess-" + sessionSeq;
  }

  function randomInstance() {
    return "i-0" + Math.random().toString(16).slice(2, 11);
  }

  function delay(ms) {
    return new Promise(function (resolve) {
      setTimeout(resolve, ms);
    });
  }

  function labById(labId) {
    for (var i = 0; i < CATALOG.length; i += 1) {
      if (CATALOG[i].labId === labId) {
        return CATALOG[i];
      }
    }
    return null;
  }

  // Mirrors lambdas/common/catalog.py:public_lab().
  function publicLab(lab, includeTasks) {
    if (!lab) {
      return null;
    }
    var copy = {};
    Object.keys(lab).forEach(function (key) {
      if (key !== "expectedFlag") {
        copy[key] = lab[key];
      }
    });
    if (copy.tasks) {
      copy.tasks = copy.tasks.map(function (task) {
        var view = {};
        Object.keys(task).forEach(function (key) {
          if (key !== "expectedFlag") {
            view[key] = task[key];
          }
        });
        return view;
      });
    }
    if (includeTasks === false) {
      delete copy.tasks;
    }
    return copy;
  }

  // Sessions are stored with exactly the docs/16 attributes; nothing extra
  // is added here, so the serialization is the identity.
  function makeSession(fields) {
    return fields;
  }

  var activity = [
    makeEvent("FLAG_ACCEPTED", "INFO", "student-01 completed Locate the application config in sess-98765", now() - 8 * 60000, "student-01", "sess-98765"),
    makeEvent("LAB_READY", "INFO", "sess-98765 became READY, Tailscale node enrolled", now() - 13 * 60000, "student-01", "sess-98765"),
    makeEvent("LAB_REQUESTED", "INFO", "student-02 requested Linux Services and Users", now() - 42 * 60000, "student-02", "sess-77310"),
    makeEvent("LAB_TERMINATED_BY_TTL", "WARN", "sess-77310 reached its 60 minute TTL and was terminated", now() - 50 * 60000, "student-02", "sess-77310"),
    makeEvent("LAB_READY", "INFO", "sess-77042 failed to provision and was rolled back", now() - 95 * 60000, "student-03", "sess-77042")
  ].sort(function (a, b) {
    return parseTs(b.at) - parseTs(a.at);
  });

  function makeEvent(kind, level, message, at, userId, sessionId) {
    var event = {
      eventId: "evt-" + eventSeq++,
      at: iso(at),
      kind: kind,
      level: level,
      message: message
    };
    if (userId) {
      event.userId = userId;
    }
    if (sessionId) {
      event.sessionId = sessionId;
    }
    return event;
  }

  var sessions = [
    makeSession({
      sessionId: "sess-98765",
      userId: "student-01",
      labId: "linux-beginner",
      state: "READY",
      createdAt: iso(now() - 14 * 60000),
      expiresAt: iso(now() + 46 * 60000),
      endedAt: null,
      instanceId: randomInstance(),
      tailscaleHostname: "linux-beginner-98765",
      flags: { "linux-b-1": true },
      terminationReason: null
    }),
    makeSession({
      sessionId: "sess-44102",
      userId: "student-01",
      labId: "devops-beginner",
      state: "READY",
      createdAt: iso(now() - (60 * 60000 - 50000)),
      expiresAt: iso(now() + 50000),
      endedAt: null,
      instanceId: randomInstance(),
      tailscaleHostname: "devops-beginner-44102",
      flags: {},
      terminationReason: null
    }),
    makeSession({
      sessionId: "sess-77042",
      userId: "student-03",
      labId: "dba-intermediate",
      state: "FAILED",
      createdAt: iso(now() - 96 * 60000),
      expiresAt: iso(now() - 36 * 60000),
      endedAt: iso(now() - 95 * 60000),
      instanceId: null,
      tailscaleHostname: null,
      flags: {},
      terminationReason: "provisioning_failed"
    }),
    makeSession({
      sessionId: "sess-77310",
      userId: "student-02",
      labId: "linux-intermediate",
      state: "TERMINATED",
      createdAt: iso(now() - 3 * 3600000),
      expiresAt: iso(now() - 3 * 3600000 + 60 * 60000),
      endedAt: iso(now() - 50 * 60000),
      instanceId: randomInstance(),
      tailscaleHostname: "linux-intermediate-77310",
      flags: {},
      terminationReason: "ttl"
    })
  ];

  function notify(type, payload) {
    listeners.forEach(function (fn) {
      fn(type, payload);
    });
  }

  function subscribe(fn) {
    listeners.push(fn);
    return function () {
      listeners = listeners.filter(function (l) {
        return l !== fn;
      });
    };
  }

  function log(kind, level, message, userId, sessionId) {
    var entry = makeEvent(kind, level, message, now(), userId, sessionId);
    activity.unshift(entry);
    notify("activity", entry);
    return entry;
  }

  function isActive(session) {
    return session.state !== "TERMINATED" && session.state !== "FAILED";
  }

  function findUser(token) {
    if (!token) {
      return null;
    }
    return USERS.find(function (user) {
      return user.token === token;
    }) || null;
  }

  function authUser(token) {
    var user = findUser(token);
    return user && user.isActive ? user : null;
  }

  function activeCountOf(filterFn) {
    return sessions.filter(function (session) {
      return isActive(session) && filterFn(session);
    }).length;
  }

  function visibleSessions(user) {
    if (!user) {
      return [];
    }
    if (user.role === "student") {
      return sessions.filter(function (session) {
        return session.userId === user.userId;
      });
    }
    return sessions.slice();
  }

  function findSession(sessionId) {
    return sessions.find(function (session) {
      return session.sessionId === sessionId;
    }) || null;
  }

  function unauthorized() {
    return { code: "UNAUTHORIZED", message: "Invalid or revoked token." };
  }

  function me(token) {
    return delay(300).then(function () {
      var user = findUser(token);
      if (!user || !user.isActive) {
        throw unauthorized();
      }
      return {
        userId: user.userId,
        email: user.email,
        role: user.role,
        maxConcurrentLabs: user.maxConcurrentLabs
      };
    });
  }

  function listSessions(token) {
    return visibleSessions(authUser(token));
  }

  function listActivity() {
    return activity.slice();
  }

  function listLabs(token) {
    // docs/16 authorization matrix: the auditor sees the catalog without
    // task content.
    var user = authUser(token);
    var includeTasks = !user || user.role !== "auditor";
    return CATALOG.map(function (lab) {
      return publicLab(lab, includeTasks);
    });
  }

  function getLab(token, labId) {
    var lab = labById(labId);
    if (!lab) {
      return null;
    }
    var user = authUser(token);
    return publicLab(lab, !user || user.role !== "auditor");
  }

  function fqdn(session) {
    return session.tailscaleHostname ? session.tailscaleHostname + "." + TS_NET_DOMAIN : null;
  }

  function quota(token) {
    var user = authUser(token);
    if (!user || user.maxConcurrentLabs === null) {
      return null;
    }
    var active = activeCountOf(function (session) {
      return session.userId === user.userId;
    });
    return { active: active, max: user.maxConcurrentLabs };
  }

  function canStart(token) {
    var user = authUser(token);
    return !!user && (user.role === "student" || user.role === "admin");
  }

  function canDestroy(token, session) {
    var user = authUser(token);
    if (!user) {
      return false;
    }
    if (user.role === "admin") {
      return true;
    }
    if (user.role === "student") {
      return session.userId === user.userId;
    }
    return false;
  }

  function startLab(token, request) {
    return delay(600).then(function () {
      var user = authUser(token);
      if (!user) {
        throw unauthorized();
      }

      if (!canStart(token)) {
        throw { code: "FORBIDDEN", message: "Your role cannot start labs." };
      }

      var lab = labById(request.labId);
      if (!lab) {
        throw { code: "UNKNOWN_LAB", message: "Unknown lab." };
      }

      if (user.maxConcurrentLabs !== null) {
        var own = activeCountOf(function (session) {
          return session.userId === user.userId;
        });

        if (own >= user.maxConcurrentLabs) {
          throw {
            code: "ACTIVE_LIMIT",
            message: "Quota reached (" + own + " of " + user.maxConcurrentLabs + " active labs). End a session before starting another."
          };
        }
      }

      if (activeCountOf(function () {
        return true;
      }) >= MAX_PLATFORM_ACTIVE_LABS) {
        throw {
          code: "ACTIVE_LIMIT",
          message: "Platform limit reached (" + MAX_PLATFORM_ACTIVE_LABS + " active labs). Try again after one expires."
        };
      }

      var sessionId = randomId();
      var created = now();

      var session = makeSession({
        sessionId: sessionId,
        userId: user.userId,
        labId: lab.labId,
        state: "REQUESTED",
        createdAt: iso(created),
        expiresAt: iso(created + lab.ttlMinutes * 60000),
        endedAt: null,
        instanceId: randomInstance(),
        tailscaleHostname: lab.labId + "-" + sessionId.split("-")[1],
        flags: {},
        terminationReason: null
      });

      sessions.unshift(session);
      log("LAB_REQUESTED", "INFO", user.userId + " requested " + lab.name, user.userId, sessionId);
      notify("session", session);

      var elapsed = 0;
      STATE_FLOW.slice(1).forEach(function (state, index) {
        elapsed += PROVISIONING_DELAYS[index];
        setTimeout(function () {
          if (!isActive(session)) {
            return;
          }
          session.state = state;

          if (state === "PROVISIONING") {
            log("LAB_PROVISIONING", "INFO", sessionId + " EC2 instance launched from approved launch template", user.userId, sessionId);
          }

          if (state === "TAILSCALE_ENROLLMENT") {
            log("LAB_PROVISIONING", "INFO", sessionId + " enrolling Tailscale node", user.userId, sessionId);
          }

          if (state === "READY") {
            log("LAB_READY", "INFO", sessionId + " became READY: tailscale ssh student@" + fqdn(session), user.userId, sessionId);
          }

          notify("session", session);
        }, elapsed);
      });

      return session;
    });
  }

  function destroyLab(token, sessionId, reason) {
    return delay(200).then(function () {
      var user = authUser(token);
      if (!user) {
        throw unauthorized();
      }

      var session = findSession(sessionId);
      if (!session) {
        throw { code: "NOT_FOUND", message: "Session not found." };
      }

      if (!canDestroy(token, session)) {
        throw { code: "FORBIDDEN", message: "You can only end your own labs." };
      }

      if (!isActive(session)) {
        return session;
      }

      session.state = "TERMINATING";
      notify("session", session);

      return delay(500).then(function () {
        session.state = "TERMINATED";
        session.endedAt = iso();
        session.terminationReason = reason === "ttl" ? "ttl" : user.role === "admin" ? "admin" : "user";

        if (reason === "ttl") {
          log("LAB_TERMINATED_BY_TTL", "WARN", session.sessionId + " reached its TTL and was terminated", user.userId, session.sessionId);
        } else if (session.terminationReason === "admin") {
          log("LAB_TERMINATED_BY_ADMIN", "WARN", session.sessionId + " ended by admin " + user.userId, user.userId, session.sessionId);
        } else {
          log("LAB_TERMINATED_BY_USER", "INFO", session.sessionId + " ended by " + user.userId, user.userId, session.sessionId);
        }

        notify("session", session);
        return session;
      });
    });
  }

  function submitFlag(token, sessionId, taskId, flagValue) {
    return delay(350).then(function () {
      var user = authUser(token);
      if (!user) {
        throw unauthorized();
      }

      var session = findSession(sessionId);
      if (!session) {
        throw { code: "NOT_FOUND", message: "Session not found." };
      }

      if (!(user.role === "admin" || session.userId === user.userId)) {
        throw { code: "FORBIDDEN", message: "You can only submit flags for your own labs." };
      }

      if (!isActive(session)) {
        throw { code: "LAB_NOT_ACTIVE", message: "This lab is no longer active." };
      }

      var lab = labById(session.labId);
      if (!lab) {
        throw { code: "UNKNOWN_LAB", message: "Unknown lab." };
      }

      var task = lab.tasks.find(function (t) {
        return t.taskId === taskId;
      });

      if (!task) {
        throw { code: "UNKNOWN_TASK", message: "Unknown task." };
      }

      var submitted = String(flagValue || "").trim().toUpperCase();
      var expected = (task.expectedFlag || "").toUpperCase();

      log("FLAG_SUBMITTED", "INFO", user.userId + " submitted a flag for " + task.title + " in " + session.sessionId, user.userId, session.sessionId);

      if (expected && submitted === expected) {
        session.flags[taskId] = true;
        log("FLAG_ACCEPTED", "INFO", user.userId + " accepted flag for " + task.title + " in " + session.sessionId, user.userId, session.sessionId);
        notify("session", session);
        return { correct: true, taskId: taskId };
      }

      log("FLAG_REJECTED", "WARN", "Invalid flag for " + task.title + " in " + session.sessionId, user.userId, session.sessionId);
      return { correct: false, taskId: taskId };
    });
  }

  function sessionCost(session) {
    var lab = labById(session.labId);
    var hourly = (lab && INSTANCE_HOURLY_COST[lab.instanceType]) || INSTANCE_HOURLY_COST["t4g.micro"];
    var end = parseTs(session.endedAt) || (isActive(session) ? now() : parseTs(session.expiresAt));
    var hours = Math.max(0, end - parseTs(session.createdAt)) / 3600000;
    return hours * hourly;
  }

  function totalCost(token) {
    return visibleSessions(authUser(token)).reduce(function (sum, session) {
      return sum + sessionCost(session);
    }, 0);
  }

  function maxActiveLabs() {
    return MAX_PLATFORM_ACTIVE_LABS;
  }

  window.LabAPI = {
    subscribe: subscribe,
    me: me,
    startLab: startLab,
    destroyLab: destroyLab,
    submitFlag: submitFlag,
    listSessions: listSessions,
    listActivity: listActivity,
    listLabs: listLabs,
    getLab: getLab,
    fqdn: fqdn,
    quota: quota,
    canStart: canStart,
    canDestroy: canDestroy,
    sessionCost: sessionCost,
    totalCost: totalCost,
    maxActiveLabs: maxActiveLabs,
    isActive: isActive
  };
})();
