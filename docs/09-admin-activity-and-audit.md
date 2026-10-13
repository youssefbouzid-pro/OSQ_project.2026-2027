# Admin Activity and Audit

## Purpose

The Activity page provides operational visibility for admins and auditors.

It is not intended for normal learners.

## Visible Roles

- Admin
- Auditor

## Activity Events

The platform should record:

- User signed in
- Lab requested
- Lab provisioning started
- Lab became ready
- Lab failed
- Flag submitted
- Flag accepted
- Invalid flag attempted
- Lab ended by user
- Lab expired by TTL
- Admin ended lab

## Event Fields

Each activity event should include:

- Event ID
- Timestamp
- Event kind
- Severity or level
- Message
- Optional user ID
- Optional session ID

## Admin Capabilities

Admin can:

- View all sessions
- End any active lab
- See activity feed
- See budget indicator
- Diagnose failed sessions

## Auditor Capabilities

Auditor can:

- View activity feed
- Review events in read-only mode
- Access help pages

Auditor cannot:

- Start labs
- End labs
- Modify sessions
- Submit flags

## Budget Indicator

The budget indicator should be visible only to admins.

It should show:

- Estimated current cost
- Monthly budget limit

Example:

    $3.42 / $20.00

Learners should not see cost information.

## Activity Retention

For the PoC:

- Activity can be stored in memory or mock state.

For production:

- Activity should be persisted.
- Activity should be exportable.
- Activity should be protected from tampering.
