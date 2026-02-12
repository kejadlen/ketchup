$LOAD_PATH.unshift File.expand_path("lib", __dir__)

require "minitest/test_task"

Minitest::TestTask.create

directory ".direnv"

desc "Create bundler binstubs (runs when Gemfile.lock changes)"
file ".direnv/.bundled" => ["Gemfile.lock"] do
  sh "bundle binstubs --all"
  touch ".direnv/.bundled"
end

task binstubs: ".direnv/.bundled"

desc "Start dev server with auto-restart, served via Tailscale"
task :dev do
  sh "tailscale serve --bg 9292"
  sh "fd | entr -r rackup"
end

desc "Seed database with sample series and tasks"
task :seed do
  require "ketchup/models"

  DB[:tasks].delete
  DB[:series].delete

  user = User.first || abort("No users yet — visit the app first to create one")

  notes = [
    "Call Mom",
    "Water the plants\n\nCheck soil moisture *before* watering",
    "Clean the kitchen",
    "Back up laptop\n\n- Time Machine to external drive\n- Sync cloud photos\n- Verify **offsite** backup",
    "Review finances",
    "Dentist appointment\n\n**Dr. Chen**, 10am\n555-0142 to reschedule",
    "Oil change",
    "Haircut",
    "Replace HVAC filter\n\nSize: **20x25x1**",
    "Check smoke detectors",
  ]

  max_count = {
    "day" => 14,
    "week" => 4,
    "month" => 6,
    "quarter" => 2,
    "year" => 2,
  }

  # How far back a due date can plausibly be overdue, in days
  overdue_spread = {
    "day" => 7,
    "week" => 21,
    "month" => 60,
    "quarter" => 120,
    "year" => 180,
  }

  all_series = notes.map do |note|
    unit = max_count.keys.sample
    count = rand(1..max_count.fetch(unit))
    spread = overdue_spread.fetch(unit)
    due_date = Date.today + rand(-spread..spread)

    Series.create_with_first_task(
      user: user,
      note: note,
      interval_unit: unit,
      interval_count: count,
      first_due_date: due_date
    )
  end

  # Add completed task history to some series
  completion_notes = [
    "Done, no issues",
    "Rescheduled from **last week**",
    "Took longer than expected — **2 hours** instead of 1",
    "Had to call back *twice*",
    "All good\n\n- Changed filter\n- Reset thermostat",
  ]

  all_series.sample(6).each do |s|
    interval_days = case s.interval_unit
                    when "day" then s.interval_count
                    when "week" then 7 * s.interval_count
                    when "month" then 30 * s.interval_count
                    when "quarter" then 91 * s.interval_count
                    when "year" then 365 * s.interval_count
                    end

    active = s.active_task
    prev_date = active.due_date
    rand(1..4).times do
      prev_date -= interval_days
      note = rand < 0.5 ? completion_notes.sample : nil
      Task.create(
        series_id: s.id,
        due_date: prev_date,
        completed_at: prev_date.to_time + rand(0..3) * 86400,
        note: note
      )
    end
  end

  puts "Seeded #{notes.length} series for #{user.name} (#{user.login})"
end

task default: %i[ test binstubs ]
