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
  require "ketchup/seed"

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
    "day" => 14, "week" => 4, "month" => 6, "quarter" => 2, "year" => 2
  }
  overdue_spread = {
    "day" => 7, "week" => 21, "month" => 60, "quarter" => 120, "year" => 180
  }
  completion_notes = [
    "Done, no issues",
    "Rescheduled from **last week**",
    "Took longer than expected — **2 hours** instead of 1",
    "Had to call back *twice*",
    "All good\n\n- Changed filter\n- Reset thermostat",
  ]

  series_data = notes.map do |note|
    unit = max_count.keys.sample
    count = rand(1..max_count.fetch(unit))
    spread = overdue_spread.fetch(unit)
    due_date = Date.today + rand(-spread..spread)

    interval_days = case unit
                    when "day" then count
                    when "week" then 7 * count
                    when "month" then 30 * count
                    when "quarter" then 91 * count
                    when "year" then 365 * count
                    end

    history = if [true, false].sample
                rand(1..4).times.map do |i|
                  past_date = due_date - (interval_days * (i + 1))
                  {
                    due_date: past_date,
                    completed_at: past_date.to_time + rand(0..3) * 86400,
                    note: rand < 0.5 ? completion_notes.sample : nil
                  }
                end
              else
                []
              end

    {
      note: note,
      interval_unit: unit,
      interval_count: count,
      due_date: due_date,
      history: history
    }
  end

  Seed.call(user: user, series: series_data)
  puts "Seeded #{notes.length} series for #{user.name} (#{user.login})"
end

task default: %i[ test binstubs ]
