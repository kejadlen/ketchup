# Ketchup

A personal tool for tracking recurring tasks and catching up on what's overdue.

## Overview

Ketchup tracks recurring obligations — "Call Mom every 2 weeks," "Renew passport every 10 years" — and surfaces what's overdue so nothing slips through the cracks. It's a personal tool for me and my family, not a SaaS product.

There's no login screen. Users are identified by a reverse proxy header (`AUTH_HEADER`, defaults to `Remote-User`), so authentication is handled at the network layer — originally Tailscale, but any authenticating proxy works.

The stack is deliberately simple:

- **Roda** — routing
- **Sequel** + **SQLite** — persistence
- **Phlex** — views
- **Alpine.js** — client-side reactivity
- **OverType** — inline markdown editing
- **Puma** — app server
- **Sentry** / **OpenTelemetry** — optional observability

## Domain model

A **Series** defines a recurring obligation — "Call Mom every 2 weeks." It holds a markdown note, an interval unit (day/week/month/quarter/year), and an interval count. The note's first line serves as the display name.

Each Series has one active **Task** at a time. Completing a task creates the next one, with a due date advanced by the interval from today. Tasks hold optional per-completion notes.

A **User** owns Series and, transitively, Tasks. The `many_through_many` association on User provides direct task access for ownership scoping.

There's a [screenshot gallery](https://kejadlen.github.io/ketchup/) — it's auto-generated for development, not a showcase, but it gives a sense of the UI.

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
docker run -p 9292:9292 -e TZ=America/Los_Angeles ketchup
```

> [!IMPORTANT]
> Set `TZ` to match the users' timezone. The app uses `Date.today` to decide what's overdue — if the container's timezone is wrong, tasks will flip between overdue and upcoming at the wrong time of day.
