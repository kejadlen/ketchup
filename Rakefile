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

namespace :snapshots do
  desc "Capture screenshots of the app in key states"
  task :capture do
    ENV["DATABASE_URL"] = ":memory:"
    require "ketchup/web"
    require "ketchup/seed"
    require "ketchup/snapshots"
    require "puma"
    require "puma/configuration"

    output_dir = File.join(Snapshots.cache_dir, "current")

    config = Puma::Configuration.new do |c|
      c.app Web.freeze.app
      c.bind "tcp://127.0.0.1:0"
      c.log_requests false
      c.quiet
    end

    launcher = Puma::Launcher.new(config)
    thread = Thread.new { launcher.run }
    sleep 1 until launcher.connected_ports.any?

    port = launcher.connected_ports.first
    Snapshots.capture(output_dir: output_dir, port: port)
    launcher.stop
    thread.join

    if ENV["CI"]
      require "json"
      puts({ output_dir: output_dir }.to_json)
    else
      puts "Screenshots saved to #{output_dir}"
    end
  end

  desc "Compare current screenshots against baseline from latest release"
  task :diff do
    require "ketchup/snapshots"

    base_dir = Snapshots.cache_dir
    baseline_dir = File.join(base_dir, "baseline")
    current_dir = File.join(base_dir, "current")

    FileUtils.rm_rf(baseline_dir)
    FileUtils.mkdir_p(baseline_dir)

    tarball = File.join(base_dir, "baseline.tar.gz")
    system("gh", "release", "download", "--pattern", "snapshots.tar.gz", "--output", tarball, "--clobber", exception: false)

    if File.exist?(tarball)
      system("tar", "xzf", tarball, "-C", baseline_dir, exception: true)
      File.delete(tarball)
      puts "Downloaded baseline from latest release"
    else
      puts "No baseline found — showing current screenshots only"
    end

    Rake::Task["snapshots:capture"].invoke

    output_path = File.join(base_dir, "diff.html")
    Snapshots.generate_diff_html(
      baseline_dir: baseline_dir,
      current_dir: current_dir,
      output_path: output_path
    )
    puts "Diff viewer: #{output_path}"
  end

  desc "Capture, diff, and open the viewer"
  task :review do
    Rake::Task["snapshots:diff"].invoke
    system("open", File.join(Snapshots.cache_dir, "diff.html"))
  end
end

task default: %i[ test binstubs ]
