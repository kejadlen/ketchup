$LOAD_PATH.unshift File.expand_path("lib", __dir__)

require "minitest/test_task"
require "pathname"

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
  cache_dir = File.join(ENV.fetch("XDG_CACHE_HOME", File.expand_path("~/.cache")), "ketchup", "snapshots")
  css_sources = {
    "public/css/reset.css" => "reset.css",
    "public/css/utopia.css" => "utopia.css",
    "templates/snapshots.css" => "snapshots.css",
  }

  directory cache_dir

  css_targets = css_sources.map do |src, basename|
    target = File.join(cache_dir, basename)
    file target => [cache_dir, src] do
      cp src, target
    end
    target
  end

  desc "Capture screenshots of the app in key states"
  task :capture do
    ENV["DATABASE_URL"] = ":memory:"
    require "ketchup/snapshots"

    output_dir = File.join(cache_dir, "current")
    Ketchup::Snapshots::Capture.new(output_dir: output_dir).call

    if ENV["CI"]
      require "json"
      puts({ output_dir: output_dir }.to_json)
    end
  end

  desc "Compare current screenshots against baseline from latest release"
  task diff: [:capture, *css_targets] do
    require "erb"
    require "json"

    base_dir = Pathname(cache_dir)
    baseline_dir = base_dir / "baseline"
    current_dir = base_dir / "current"

    FileUtils.rm_rf(baseline_dir)
    baseline_dir.mkpath

    tarball = base_dir / "baseline.tar.gz"
    system("gh", "release", "download", "--pattern", "snapshots.tar.gz", "--output", tarball.to_s, "--clobber", exception: false)

    if tarball.exist?
      system("tar", "xzf", tarball.to_s, "-C", baseline_dir.to_s, exception: true)
      tarball.delete
      puts "Downloaded baseline from latest release"
    else
      puts "No baseline found — showing current screenshots only"
    end

    manifest = current_dir / "manifest.json"
    order = manifest.exist? ? JSON.parse(manifest.read).map { |e| e["name"] } : []
    baseline_images = baseline_dir.glob("*.png").map { |f| f.basename(".png").to_s }
    current_images = current_dir.glob("*.png").map { |f| f.basename(".png").to_s }
    all_names = order | current_images | baseline_images

    snapshots = all_names.map do |name|
      has_baseline = baseline_images.include?(name)
      has_current = current_images.include?(name)

      status = if !has_baseline then :new
               elsif !has_current then :removed
               end

      {
        name: name,
        status: status,
        baseline: has_baseline ? "baseline/#{name}.png" : nil,
        current: has_current ? "current/#{name}.png" : nil,
      }
    end

    template = (Pathname(__dir__) / "templates/snapshot_diff.erb").read
    output_path = base_dir / "diff.html"
    output_path.write(ERB.new(template, trim_mode: "-").result_with_hash(snapshots: snapshots))
    puts "Diff viewer: #{output_path}"
  end

  desc "Capture, diff, and open the viewer"
  task review: :diff do
    system("open", (Pathname(cache_dir) / "diff.html").to_s)
  end

  desc "Generate gallery HTML from images in a directory"
  task :gallery, [:images_dir, :output_path] do |_t, args|
    require "erb"
    require "json"

    images_dir = Pathname(args.fetch(:images_dir) { File.join(cache_dir, "current") })
    output_path = Pathname(args.fetch(:output_path) { File.join(cache_dir, "gallery.html") })

    css_sources.each_key { |src| cp src, output_path.dirname.to_s }

    manifest = images_dir / "manifest.json"
    order = manifest.exist? ? JSON.parse(manifest.read).map { |e| e["name"] } : []
    all_pngs = images_dir.glob("*.png").map { |f| f.basename(".png").to_s }
    names = order | all_pngs

    title = "Ketchup Snapshots"
    images_rel = images_dir.relative_path_from(output_path.dirname)
    images = names.map do |name|
      { name: name, filename: (images_rel / "#{name}.png").to_s }
    end

    template = (Pathname(__dir__) / "templates/snapshot_gallery.erb").read
    output_path.write(ERB.new(template, trim_mode: "-").result_with_hash(title: title, images: images))
    puts output_path
  end
end

task default: %i[ test binstubs ]
