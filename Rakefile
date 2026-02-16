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

  Ketchup::Seed.call(user: user, series: Ketchup::Seed::DATA)
  puts "Seeded #{Ketchup::Seed::DATA.length} series for #{user.name} (#{user.login})"
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
    require "ketchup/snapshots"

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

    snapshots = Ketchup::Snapshots::Diff.new(baseline_dir: baseline_dir, current_dir: current_dir).comparisons

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
    require "ketchup/snapshots"

    images_dir = Pathname(args.fetch(:images_dir) { File.join(cache_dir, "current") })
    output_path = Pathname(args.fetch(:output_path) { File.join(cache_dir, "gallery.html") })

    css_sources.each_key { |src| cp src, output_path.dirname.to_s }

    entries = Ketchup::Snapshots::Entry.read_manifest(images_dir)

    title = "Ketchup Snapshots"
    images_rel = images_dir.relative_path_from(output_path.dirname)
    images = entries.map do |entry|
      { entry: entry, filename: (images_rel / "#{entry.name}.png").to_s }
    end

    template = (Pathname(__dir__) / "templates/snapshot_gallery.erb").read
    output_path.write(ERB.new(template, trim_mode: "-").result_with_hash(title: title, images: images))
    puts output_path
  end
end

desc "Generate RBS from inline annotations and run Steep type checker"
task :check do
  sh "rbs-inline --output lib/"
  sh "steep check"
end

task default: %i[ test check binstubs ]
