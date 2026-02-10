# ketchup

A personal/family tool for tracking recurring tasks and catching up on what's overdue.

## Overview

- **Users:** Me and my family
- **Auth:** Handled via Tailscale — rely on remote user header (no in-app auth)
- **Interface:** Web app (Roda), architected so a CLI can be added later
- **Stack:** Ruby, Roda, Sequel, SQLite3

## Key concepts

- **Tasks** are recurring, with a configurable interval (day/week/month/quarter/year) and interval count
  - Recurrence is based on interval+count from last completion (not fixed schedule — but may add fixed schedule later)
- Each user has their own tasks
- Tasks can also be **shared** — visible to all users, anyone can mark them done, overdue shows for everyone
- One-off tasks are out of scope for now
- No task assignment — shared tasks are not assigned to a specific person
- Each task has a **note** (free text) — the first line is the task name
  - Per-completion notes may be added later

## Task fields

- **Note** — free text; first line serves as the task name/title
- **Interval unit** — day, week, month, quarter, or year
- **Interval count** — e.g., 2 (combined with unit: "every 2 weeks")
- **First due date** — user picks this on creation
- **Personal or shared**

## Primary use case

Catching up with friends and family — some weekly, some quarterly, some yearly, etc.

## Main view

A single list of tasks in priority order, automatically sorted:

1. **Overdue tasks first** — ordered by how late they are *relative to their interval* (most proportionally overdue at top)
2. **Upcoming tasks after** — ordered by due date (soonest first)

## Architecture

Domain logic should be separated from the web layer so a CLI can be added later.
