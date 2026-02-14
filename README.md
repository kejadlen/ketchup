# Ketchup

A personal tool for tracking recurring tasks and catching up on what's overdue.

## Overview

- **Users:** Me and my family
- **Auth:** Tailscale headers (no in-app auth)
- **Stack:** Ruby, Roda, Sequel, SQLite, Phlex, Alpine.js, OverType

## Domain model

A **Series** defines a recurring obligation — "Call Mom every 2 weeks." It holds the note, interval unit (day/week/month/quarter/year), and interval count. The note's first line serves as the display name.

Each Series has one active **Task** at a time. Completing a task creates the next one, with a due date advanced by the interval from today. Tasks also hold optional per-completion notes.

A **User** owns Series (and, transitively, Tasks). The `many_through_many` association on User provides direct task access for ownership scoping.

## Main view

The dashboard has three columns:

1. **Overdue** — tasks past due, sorted by urgency (how late relative to interval)
2. **Upcoming** — a calendar showing tasks by due date, with empty days as context
3. **Sidebar** — either a new series form or the selected series detail (note, interval, due date, completion history with per-completion notes)

## Primary use case

Catching up with friends and family — some weekly, some quarterly, some yearly.

## Development

Largely vibe-coded with Claude Code. I steer direction and make design calls; Claude writes most of the code.
