# User Roles and Permissions

## Student

Can:

- Sign in
- Browse labs
- Start labs
- View active and previous labs
- Open lab guides
- Submit flags
- End their own labs
- Access help pages

Cannot:

- See admin activity
- See budget or cost data
- See internal governance pages
- End other users' labs

## Admin

Can:

- Do everything a student can do
- See platform activity
- See budget indicator
- End any lab
- Inspect session status across users
- Access admin activity view

Cannot:

- Bypass lab TTL in the learner UI
- Modify learner flag submissions manually in the PoC unless future admin tooling is added

## Auditor

Can:

- View activity
- View help pages
- Review session events in read-only mode

Cannot:

- Start labs
- Modify sessions
- End labs
- Submit flags

## Permission Matrix

| Action | Student | Admin | Auditor |
|---|---:|---:|---:|
| Sign in | Yes | Yes | Yes |
| Browse catalog | Yes | Yes | Limited |
| Start lab | Yes | Yes | No |
| View own labs | Yes | Yes | No |
| View all labs | No | Yes | Read-only |
| Submit flags | Yes | Yes | No |
| End own lab | Yes | Yes | No |
| End any lab | No | Yes | No |
| View activity feed | No | Yes | Yes |
| View budget indicator | No | Yes | No |
| View internal docs in repo | Possible | Possible | Possible |
| View internal docs in learner UI | No | No | No |
