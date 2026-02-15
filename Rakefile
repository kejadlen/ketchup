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
    require "ketchup/snapshots"

    capture = Ketchup::Snapshots::Capture.new
    capture.call

    if ENV["CI"]
      require "json"
      puts({ output_dir: capture.output_dir }.to_json)
    end
  end

  desc "Compare current screenshots against baseline from latest release"
  task diff: :capture do
    require "erb"

    base_dir = Ketchup::Snapshots.cache_dir
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

    baseline_images = Dir.glob(File.join(baseline_dir, "*.png")).map { |f| File.basename(f, ".png") }.sort
    current_images = Dir.glob(File.join(current_dir, "*.png")).map { |f| File.basename(f, ".png") }.sort

    snapshots = (baseline_images | current_images).sort.map do |name|
      has_baseline = baseline_images.include?(name)
      has_current = current_images.include?(name)

      status = if !has_baseline then :new
               elsif !has_current then :removed
               end

      {
        name: name,
        status: status,
        baseline: has_baseline ? File.join("baseline", "#{name}.png") : nil,
        current: has_current ? File.join("current", "#{name}.png") : nil,
      }
    end

    template = File.read(File.expand_path("templates/snapshot_diff.erb", __dir__))
    output_path = File.join(base_dir, "diff.html")
    File.write(output_path, ERB.new(template, trim_mode: "-").result_with_hash(snapshots: snapshots))
    puts "Diff viewer: #{output_path}"
  end

  desc "Capture, diff, and open the viewer"
  task review: :diff do
    system("open", File.join(Ketchup::Snapshots.cache_dir, "diff.html"))
  end

  desc "Generate gallery HTML from images in a directory"
  task :gallery, [:images_dir, :output_path] do |_t, args|
    require "erb"

    images_dir = args.fetch(:images_dir)
    output_path = args.fetch(:output_path)

    title = "Ketchup Snapshots"
    images = Dir.glob(File.join(images_dir, "*.png")).sort.map do |f|
      { name: File.basename(f, ".png"), filename: File.basename(f) }
    end

    template = File.read(File.expand_path("templates/snapshot_gallery.erb", __dir__))
    File.write(output_path, ERB.new(template, trim_mode: "-").result_with_hash(title: title, images: images))
    puts output_path
  end
end

task default: %i[ test binstubs ]
