# Shared series design

## Scope

Let any user mark a series as "shared with everyone." Shared series appear on every user's dashboard and can be completed, edited, archived, or unshared by anyone who can see them. The series creator retains no special status once a series is shared — visibility implies full access.

**Non-goals:**

- Per-user sharing (explicit ACLs, households, groups)
- Distinguishing creator from collaborator in the UI
- Preventing unshared edits/archives by non-creators

## Motivation

Ketchup is a personal tool for a small, trusted set of family users. Recurring obligations like a monthly dinner with friends are inherently shared — anyone in the household might be the one to follow up. Today the model forces a single owner per series, which loses information when more than one person tracks the same obligation.

## Data model

### Migration `007_add_sharing.rb`

```ruby
Sequel.migration do
  change do
    alter_table(:series) do
      add_column :shared, TrueClass, default: false, null: false
    end
    alter_table(:tasks) do
      add_foreign_key :completed_by_user_id, :users, null: true
    end
    from(:tasks).exclude(completed_at: nil).update(
      completed_by_user_id: from(:series).where(id: Sequel[:tasks][:series_id]).select(:user_id)
    )
    alter_table(:tasks) do
      add_constraint(:tasks_completed_by_consistency) do
        ({ completed_at: nil, completed_by_user_id: nil }) |
          (Sequel.~(completed_at: nil) & Sequel.~(completed_by_user_id: nil))
      end
    end
  end
end
```

Order matters: column → backfill → CHECK. Backfilled rows already satisfy the constraint by the time it lands. Existing series default to `shared = false` (private).

The CHECK enforces a biconditional: `completed_at` and `completed_by_user_id` are either both null or both set. Catches the inverse mistake too — a completer can't be set without a completion.

### Model changes

**`Task`:**

- `many_to_one :completed_by, class: :User, key: :completed_by_user_id`
- `complete!(completed_on:, by:)` writes `completed_by_user_id: by.id`
- `undo_complete!` clears `completed_by_user_id` back to `nil`

**`User`:**

- New `visible_series_dataset`:
  ```ruby
  def visible_series_dataset
    Series.where(user_id: id).or(shared: true)
  end
  ```
- New `visible_tasks_dataset` joining through `visible_series_dataset` (replaces today's `tasks_dataset` use in `active_tasks`/`overdue_tasks`/`upcoming_tasks`)
- The auto-generated `series_dataset` from `one_to_many :series` stays untouched and unused for sharing-aware lookups

## Routes

All sharing-aware routes use `@user.visible_series_dataset` instead of `@user.series_dataset`. There is no owner-only path: visibility implies full access.

| Route | Change |
|---|---|
| `POST /series` | accept `shared` param (checkbox) |
| `GET /series/:id` | scope via `visible_series_dataset` |
| `PATCH /series/:id` | scope via `visible_series_dataset`; accept `shared` in updates hash |
| `POST/DELETE /series/:id/archive` | scope via `visible_series_dataset` |
| `POST/DELETE /series/:id/tasks/:id/complete` | scope via `visible_series_dataset`; pass `by: @user` to `complete!` |
| `PATCH /series/:id/tasks/:id` | scope via `visible_series_dataset` |

`Series.create_with_first_task` gains a `shared:` keyword argument (default `false`).

## Views

### Icon helper

New file `lib/ketchup/views/shared_icon.rb` — Phlex component that emits inline SVG of SF Symbols `person.2.fill`. Centralizes the markup and lets callers pass an optional `class:` for sizing tweaks. CSS rule keeps it sized as a glyph next to text:

```css
.task-shared { width: 1em; height: 1em; vertical-align: -0.15em; fill: currentColor; }
```

### Where the icon appears

- **`Views::TaskCard`** — inside `.task-body`, after the `.task-name` link. Wrap in `<span class="task-shared" aria-label="Shared">` for screen readers.
- **`Views::Series::Show`** — next to the series title in the detail panel header.

### Form changes

- **`Views::Series::New`** — add a checkbox field `<input type="checkbox" name="shared">` with label "Shared with everyone."
- **`Views::Series::Show`** — add the same checkbox to the inline edit form. PATCH route already picks it up via the updates hash.

### Data flow

`User#active_tasks` builds rows with `select_append` for `interval_unit`/`interval_count`. Add `:shared` to that list so `TaskCard` can render the icon without a per-task DB hit.

## Edge cases

- **Toggling `shared` from true → false.** Tasks already completed by other users keep their `completed_by_user_id` as historical truth. The series stops appearing on others' dashboards going forward.
- **Owner deletes a series with non-owner completions.** `tasks.completed_by_user_id` is a nullable FK; consider `on_delete: :set_null` so user deletion (if it ever exists) doesn't cascade-destroy task history. Series deletion isn't a current code path — out of scope.

## Snapshot coverage

Add a `snap("dashboard-shared")` capture in `lib/ketchup/snapshots.rb` after seeding at least one shared series. Catches visual regressions on the icon.

## Test plan

- Migration backfill populates `completed_by_user_id` on existing completed tasks
- CHECK constraint rejects insertion of `completed_at` without `completed_by_user_id` (and vice versa)
- `Task#complete!` records the acting user
- `Task#undo_complete!` clears the completer
- `User#visible_series_dataset` returns owned + shared series
- Non-creator can complete a shared series' active task
- Non-creator can edit a shared series' note and interval
- Non-creator can archive and unarchive a shared series
- Non-creator can toggle `shared` off
- Private series remain invisible to non-owners
