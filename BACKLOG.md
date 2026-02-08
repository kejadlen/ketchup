# Backlog

## Backlog

### 1. Set up domain layer with Task model and persistence

**What:** Create the Task model (note, interval unit, interval count, due date, personal/shared, owner) with Sequel migration and a repository/service layer separated from the web layer.
**Who:** Foundation for everything else.
**Why now:** Nothing works without this.
**Done when:**
- Sequel migration creates the tasks table
- Task domain object exists independent of web layer
- Can create and retrieve a task via the domain layer
- Tests pass

### 2. Create a task via the web UI

**What:** A form to create a new task — note (textarea), interval unit, interval count, first due date, personal/shared toggle. Submitted task is saved to the DB for the current user (identified by Tailscale header).
**Who:** You.
**Why now:** Can't use the app without tasks.
**Done when:**
- Form at a route (e.g., `/tasks/new`) with all fields
- Submitting saves the task tied to the current user
- User is identified from the Tailscale remote user header
- Redirects somewhere sensible after creation

### 3. View the task list (main view)

**What:** The main screen shows all tasks the current user can see (their personal tasks + all shared tasks), sorted: overdue first by relative lateness, then upcoming by due date.
**Who:** You and your family.
**Why now:** This is the core of the app — the "catch up" view.
**Done when:**
- Main page shows tasks sorted correctly
- Overdue tasks are visually distinct from upcoming ones
- Task name (first line of note) is displayed
- Personal tasks only show for their owner; shared tasks show for everyone

## Icebox

- Mark a task as done (completes it, schedules next occurrence)
- Edit a task
- Delete a task
- Per-completion notes
- Fixed-schedule recurrence
- CLI interface
