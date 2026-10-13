"""The lab catalog, in the exact shape docs/16 stores in the ``labs`` table.

``scripts/seed_labs.py`` loads this into DynamoDB and the unit tests
read it directly, so the table and the tests cannot drift apart.

Task answers come from docs/07. ``expectedFlag`` lives here and in the
``labs`` table only: it is stripped by ``common.catalog.redact_lab``
before anything is serialized to a learner.
"""

from .catalog import FLAG_KEY

AMI_PREFIX = "/cloudybt/ami"

DEFAULT_TTL_MINUTES = 60


def _task(task_id, title, instruction, hint, flag):
    return {
        "taskId": task_id,
        "title": title,
        "instruction": instruction,
        "hint": hint,
        FLAG_KEY: flag,
    }


def _lab(lab_id, family, level, name, description, instance_type, tasks):
    return {
        "labId": lab_id,
        "family": family,
        "level": level,
        "name": name,
        "description": description,
        "instanceType": instance_type,
        "amiParameter": "{}/{}".format(AMI_PREFIX, family),
        "ttlMinutes": DEFAULT_TTL_MINUTES,
        "tasks": tasks,
    }


LABS = [
    _lab(
        "linux-beginner",
        "linux",
        "Beginner",
        "Linux Basics: Files and Permissions",
        "Learn essential Linux navigation, file inspection, and permission management.",
        "t4g.micro",
        [
            _task(
                "linux-b-1",
                "Locate the application config",
                "Connect to the lab and find the config file inside /opt/app.",
                "Use: ls -la /opt/app",
                "CB-LINUX-B-01",
            ),
            _task(
                "linux-b-2",
                "Fix the config permissions",
                "Make /opt/app/config.yml readable only by appuser.",
                "Use: chown and chmod",
                "CB-LINUX-B-02",
            ),
        ],
    ),
    _lab(
        "linux-intermediate",
        "linux",
        "Intermediate",
        "Linux Services and Users",
        "Manage users, groups, and systemd services in a realistic Linux environment.",
        "t4g.small",
        [
            _task(
                "linux-i-1",
                "Create a service account",
                "Create a system user named webapp with no login shell.",
                "Use: useradd -r -s /usr/sbin/nologin webapp",
                "CB-LINUX-I-01",
            ),
            _task(
                "linux-i-2",
                "Restart the broken service",
                "The webapp service is failing. Diagnose and restart it.",
                "Use: systemctl status webapp",
                "CB-LINUX-I-02",
            ),
        ],
    ),
    _lab(
        "linux-advanced",
        "linux",
        "Advanced",
        "Linux Troubleshooting Challenge",
        "Diagnose a broken web service caused by permissions, ports, and configuration drift.",
        "t4g.small",
        [
            _task(
                "linux-a-1",
                "Find the listening port issue",
                "The app should listen on port 8080 but it is not reachable.",
                "Use: ss -tulpn",
                "CB-LINUX-A-01",
            ),
            _task(
                "linux-a-2",
                "Restore the service",
                "Fix the configuration and make the app respond on localhost:8080.",
                "Use: curl http://localhost:8080",
                "CB-LINUX-A-02",
            ),
        ],
    ),
    _lab(
        "dba-beginner",
        "dba",
        "Beginner",
        "PostgreSQL Basics",
        "Connect to PostgreSQL, inspect databases, and run basic SQL queries.",
        "t4g.small",
        [
            _task(
                "dba-b-1",
                "Connect to PostgreSQL",
                "Connect to the local PostgreSQL instance using psql.",
                "Use: psql -U postgres",
                "CB-DBA-B-01",
            ),
            _task(
                "dba-b-2",
                "List databases",
                "List all databases and find the training database.",
                "Use: \\l",
                "CB-DBA-B-02",
            ),
        ],
    ),
    _lab(
        "dba-intermediate",
        "dba",
        "Intermediate",
        "PostgreSQL Backup and Restore",
        "Practice database backup, restore, and user management.",
        "t4g.small",
        [
            _task(
                "dba-i-1",
                "Backup the database",
                "Create a backup of the training database using pg_dump.",
                "Use: pg_dump training > training.sql",
                "CB-DBA-I-01",
            ),
            _task(
                "dba-i-2",
                "Create a read-only user",
                "Create a database user named analyst with read-only access.",
                "Use: CREATE ROLE and GRANT",
                "CB-DBA-I-02",
            ),
        ],
    ),
    _lab(
        "dba-advanced",
        "dba",
        "Advanced",
        "PostgreSQL Performance and Recovery",
        "Investigate slow queries, restore corrupted data, and verify integrity.",
        "t4g.medium",
        [
            _task(
                "dba-a-1",
                "Find the slow query",
                "Identify the query causing high load in pg_stat_activity.",
                "Use: SELECT * FROM pg_stat_activity;",
                "CB-DBA-A-01",
            ),
            _task(
                "dba-a-2",
                "Restore the missing table",
                "Restore the orders table from the provided backup file.",
                "Use: psql and the backup in /var/backups",
                "CB-DBA-A-02",
            ),
        ],
    ),
    _lab(
        "devops-beginner",
        "devops",
        "Beginner",
        "Containers Basics",
        "Run your first container and inspect the runtime environment.",
        "t4g.small",
        [
            _task(
                "devops-b-1",
                "Run a container",
                "Run the provided hello-world container image.",
                "Use: docker run",
                "CB-DEVOPS-B-01",
            ),
            _task(
                "devops-b-2",
                "Inspect running containers",
                "List running containers and find the container ID.",
                "Use: docker ps",
                "CB-DEVOPS-B-02",
            ),
        ],
    ),
    _lab(
        "devops-intermediate",
        "devops",
        "Intermediate",
        "Build and Deploy",
        "Build a container image and deploy a small web service.",
        "t4g.small",
        [
            _task(
                "devops-i-1",
                "Build the image",
                "Build the app image from /home/student/app.",
                "Use: docker build -t cloudy-app .",
                "CB-DEVOPS-I-01",
            ),
            _task(
                "devops-i-2",
                "Deploy the app",
                "Run the app on port 8080 and verify it responds.",
                "Use: docker run -p 8080:8080 cloudy-app",
                "CB-DEVOPS-I-02",
            ),
        ],
    ),
    _lab(
        "devops-advanced",
        "devops",
        "Advanced",
        "Pipeline Troubleshooting",
        "Fix a broken CI/CD deployment pipeline and restore service health.",
        "t4g.medium",
        [
            _task(
                "devops-a-1",
                "Find the failed pipeline step",
                "Inspect the pipeline logs and identify the failed stage.",
                "Use: cat /var/log/pipeline.log",
                "CB-DEVOPS-A-01",
            ),
            _task(
                "devops-a-2",
                "Restore the deployment",
                "Fix the deployment script and restart the app service.",
                "Use: ./deploy.sh",
                "CB-DEVOPS-A-02",
            ),
        ],
    ),
]

#: Users created by ``scripts/seed_users.py``. Tokens are generated at
#: seed time and printed once; only the SHA-256 hash is stored.
SEEDED_USERS = [
    {"userId": "student-01", "email": "student-01@cloudy.tn", "role": "student",
     "maxConcurrentLabs": 4, "isActive": True},
    {"userId": "student-02", "email": "student-02@cloudy.tn", "role": "student",
     "maxConcurrentLabs": 4, "isActive": True},
    {"userId": "admin-01", "email": "admin@cloudy.tn", "role": "admin",
     "maxConcurrentLabs": None, "isActive": True},
    {"userId": "auditor-01", "email": "auditor@cloudy.tn", "role": "auditor",
     "maxConcurrentLabs": None, "isActive": True},
    {"userId": "student-99", "email": "revoked@cloudy.tn", "role": "student",
     "maxConcurrentLabs": 4, "isActive": False},
]


def labs_by_id():
    return {lab["labId"]: lab for lab in LABS}
