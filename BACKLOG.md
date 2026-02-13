# Backlog

## Backlog

### Complete tasks

**What:** Mark a task as done — completes the current task, creates the next one with a due date advanced by the series interval.
**Why now:** Core loop — without this, tasks just accumulate and the app isn't usable.
**Done when:**
- A task can be marked done from the task list
- Completing a task sets `completed_at` and creates a new active task with the next due date
- Both happen atomically in a transaction

### Delay task due date

**What:** Push a task's due date forward without completing it.
**Why now:** Sometimes you know you can't get to something yet and want to stop it showing as overdue.
**Done when:**
- A task's due date can be changed from the task list
- The task remains active (not completed)

### Colorscheme

**What:** A cohesive color palette instead of ad-hoc hex values.
**Why now:** The app is visually usable but the colors are arbitrary.
**Done when:**
- Colors are defined as CSS custom properties
- Applied consistently across the app

### Markdown rendering

**What:** Render task notes as Markdown instead of plain text.
**Why now:** Notes often contain links, lists, or formatting that would benefit from rendering.
**Done when:**
- Task notes render Markdown in the task list
- The new series form still accepts plain text (rendered on display)

### Calendar view

**What:** A calendar visualization showing when tasks are due, giving a sense of upcoming load.
**Why now:** The sorted list shows priority but not temporal distribution — hard to see if next week is packed.
**Done when:**
- A calendar view shows tasks plotted on their due dates
- Overdue tasks are visually distinct

## Icebox

- Edit a task/series
- Delete a task/series
- Per-completion notes
- Fixed-schedule recurrence
- Personal/shared toggle
- CLI interface
- Sentry
