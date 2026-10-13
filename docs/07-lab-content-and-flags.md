# Lab Content and Flags

## Lab Content Delivery

Each lab environment should be configured automatically when the EC2 instance launches.

Recommended injection methods:

- EC2 user-data
- cloud-init
- Bootstrap shell script
- Approved AMI with lab files preinstalled

The lab environment should contain:

- Task files
- Broken scenario or exercise target
- Hidden or protected flags
- Verification commands
- Optional README inside the instance

## Example Linux Beginner Scenario

Lab:

    Linux Basics: Files and Permissions

Scenario:

    The application configuration file has incorrect ownership and permissions.

Tasks:

1. Locate the application config.
2. Fix the config permissions.

Flag examples:

    CB-LINUX-B-01
    CB-LINUX-B-02

Possible flag placement:

- CB-LINUX-B-01 appears after listing /opt/app
- CB-LINUX-B-02 appears inside a root-only file after permission fix

## Example DBA Beginner Scenario

Lab:

    PostgreSQL Basics

Scenario:

    The learner must connect to PostgreSQL and inspect the training database.

Tasks:

1. Connect using psql.
2. List databases and locate the training database.

Flag examples:

    CB-DBA-B-01
    CB-DBA-B-02

## Example DevOps Beginner Scenario

Lab:

    Containers Basics

Scenario:

    The learner must run and inspect a container.

Tasks:

1. Run the provided container image.
2. Inspect running containers and locate the container ID.

Flag examples:

    CB-DEVOPS-B-01
    CB-DEVOPS-B-02

## Flag Validation Rules

- Flags should be case-insensitive in the UI.
- Leading and trailing whitespace should be ignored.
- Flags should only be accepted for active sessions.
- Flags should only be accepted by the session owner or an admin.
- Completed flags should be stored per session.

## Flag Security

For the PoC:

- Flags can be static strings.
- Flags can be stored in the mock API.

For a stronger implementation:

- Flags can be randomly generated per session.
- Flags can be written to the instance by user-data.
- Flags can be revealed only after the correct task is completed.
