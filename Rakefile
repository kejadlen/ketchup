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
    "Water the plants\n\nCheck soil moisture first",
    "Clean the kitchen",
    "Back up laptop\n\nTime Machine to external drive\nAlso sync cloud photos",
    "Review finances",
    "Dentist appointment\n\nDr. Chen, 10am\n555-0142 to reschedule",
    "Oil change",
    "Haircut",
    "Replace HVAC filter\n\nSize: 20x25x1",
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

  notes.each do |note|
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

  puts "Seeded #{notes.length} series for #{user.name} (#{user.login})"
end

task default: %i[ test binstubs ]
