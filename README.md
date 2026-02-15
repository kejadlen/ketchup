# Ketchup

A personal tool for tracking recurring tasks and catching up on what's overdue.

## Overview

Ketchup is for me and my family. Authentication comes from Tailscale headers — there's no in-app login. The stack is Ruby 4, Roda, Sequel, SQLite, Phlex, Alpine.js, and OverType (for inline markdown editing). Puma serves it, Sentry tracks errors in production.

## Domain model

A **Series** defines a recurring obligation — "Call Mom every 2 weeks." It holds a markdown note, an interval unit (day/week/month/quarter/year), and an interval count. The note's first line serves as the display name.

Each Series has one active **Task** at a time. Completing a task creates the next one, with a due date advanced by the interval from today. Tasks hold optional per-completion notes.

A **User** owns Series and, transitively, Tasks. The `many_through_many` association on User provides direct task access for ownership scoping.

## Main view

The dashboard has three columns:

1. Overdue — tasks past due, sorted by urgency (how late relative to interval) or by date
2. Upcoming — a calendar view showing tasks by due date, with month headers, weekend highlighting, and toggleable empty days for context
3. Sidebar — either a new series form or the selected series detail, where notes, interval, and due date are editable inline

Sort order and calendar preferences persist across sessions via Alpine's Persist plugin.

## Primary use case

Catching up with friends and family — some weekly, some quarterly, some yearly.

## Development

Largely vibe-coded with Claude Code. I steer direction and make design calls; Claude writes most of the code.

### Setup

```
bundle install
rake seed       # populate sample data (requires visiting the app first to create a user)
rake dev        # start dev server with auto-restart, served via Tailscale
```

### Testing

```
rake test       # Minitest suite (the default rake task)
```

### Visual snapshots

Ferrum captures headless Chrome screenshots of the app in key states. The snapshot tasks compare current screenshots against the baseline from the latest GitHub release.

```
rake snapshots:capture   # take screenshots
rake snapshots:diff      # capture and generate a side-by-side diff viewer
rake snapshots:review    # capture, diff, and open in browser
rake snapshots:gallery   # generate an HTML gallery
```

### CI/CD

GitHub Actions runs tests, builds a Docker image tagged `YYYYMMDD-<sha>`, and pushes it to `ghcr.io`. Each push to main also creates a GitHub release with snapshot artifacts. A separate workflow deploys a snapshot gallery to GitHub Pages.

### Docker

```
docker build -t ketchup .
docker run -p 9292:9292 ketchup
```
