# Frontend Pages and Features

## Design Principle

The frontend should feel like a learning platform, not an internal cloud operations console.

Learners should see simple actions:

- Browse labs
- Start lab
- Open guide
- Connect
- Submit flag
- End lab

## Page: Home

Purpose:

- Welcome the learner
- Show continue-learning card
- Show recommended labs
- Show setup checklist
- Show recent sessions

Primary actions:

- Browse Labs
- Getting Started
- Open active lab

## Page: Lab Catalog

Purpose:

- List available labs
- Filter by family
- Filter by difficulty
- Search labs
- Open lab guide
- Start lab

Lab card should show:

- Lab name
- Family
- Difficulty badge
- Description
- Duration
- Task count
- Start button
- Guide button

## Page: My Labs

Purpose:

- Show learner sessions
- Show session state
- Show time remaining
- Provide connect and guide actions
- Allow ending active labs

Session row should show:

- Lab name
- Session ID
- Difficulty
- Status badge
- TTL countdown
- Actions

## Page: Lab Guide

Purpose:

- Show lab details
- Show tasks
- Show hints
- Show flag submission
- Show session connection details

If no active session exists:

- Show lab description
- Show tasks in read-only mode
- Show Start Lab button

If active session exists:

- Show session status
- Show TTL countdown
- Show SSH command
- Show task flag inputs
- Show completed tasks

## Page: Getting Started

Purpose:

- Explain how labs work
- Explain TTL
- Explain flags
- Explain session expiration

## Page: Access Setup

Purpose:

- Explain Tailscale installation
- Explain how to verify connection
- Explain how to connect to a lab
- Provide troubleshooting steps

## Page: Help & FAQ

Purpose:

- Answer common learner questions
- Reduce support friction
- Provide troubleshooting guidance

## Admin-Only Page: Activity

Purpose:

- Show platform events
- Show session activity
- Show flag activity
- Show expiration events

Visible only to:

- Admin
- Auditor
