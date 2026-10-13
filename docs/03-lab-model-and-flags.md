# Lab Model and Flags

## Lab Object

Each lab has:

- Lab ID
- Lab family
- Difficulty level
- Lab name
- Description
- Instance type
- Approved AMI
- TTL
- Task list
- Flags

Example lab ID format:

    linux-beginner
    linux-intermediate
    dba-beginner
    devops-advanced

## Lab Families

### Linux Sysadmin

Focus:

- Shell commands
- File permissions
- Users and groups
- Services
- Logs
- Troubleshooting

### Database Administration

Focus:

- PostgreSQL basics
- Backup and restore
- Users and roles
- Query performance
- Database recovery

### DevOps Pipeline

Focus:

- Containers
- Docker basics
- Build and deploy
- CI/CD concepts
- Pipeline troubleshooting

## Difficulty Levels

### Beginner

- Simple instructions
- Guided commands
- One or two tasks
- Low troubleshooting complexity

### Intermediate

- Multiple tasks
- Some diagnosis required
- Service or database configuration involved

### Advanced

- Multi-step troubleshooting
- Broken scenario
- Learner must identify root cause
- May require log analysis and service repair

## Tasks

Each lab task should contain:

- Task ID
- Title
- Instruction
- Hint
- Expected flag

Example:

    Task ID: linux-b-1
    Title: Locate the application config
    Instruction: Find the config file inside /opt/app.
    Hint: Use ls -la /opt/app
    Flag: CB-LINUX-B-01

## Flags

Flags are proof that the learner completed a task inside the lab environment.

Flag format:

    CB-<FAMILY>-<LEVEL>-<NUMBER>

Examples:

    CB-LINUX-B-01
    CB-DBA-I-02
    CB-DEVOPS-A-01

Flags should be placed inside the lab environment by user-data, cloud-init, or lab bootstrap scripts.

Examples of flag locations:

- Inside a file after fixing permissions
- Returned by a command after restarting a service
- Visible after restoring a database table
- Available after a container responds correctly
