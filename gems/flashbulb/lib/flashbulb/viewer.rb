# frozen_string_literal: true

require "erb"
require "pathname"

module Flashbulb
  module Viewer
    TEMPLATES_DIR = Pathname(__dir__).parent.parent / "templates"

    def self.render_diff(snapshots_by_viewport:, title: "Snapshot Diff")
      template = (TEMPLATES_DIR / "snapshot_diff.erb").read(encoding: "utf-8")
      ERB.new(template, trim_mode: "-").result_with_hash(snapshots_by_viewport: snapshots_by_viewport, title: title)
    end

    def self.render_gallery(title:, images_by_viewport:)
      template = (TEMPLATES_DIR / "snapshot_gallery.erb").read(encoding: "utf-8")
      ERB.new(template, trim_mode: "-").result_with_hash(title: title, images_by_viewport: images_by_viewport)
    end
  end
end
