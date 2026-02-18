# frozen_string_literal: true

require "phlex"

require_relative "series_detail"

module Views
  class SeriesPanel < Phlex::HTML
    def initialize(series:, csrf: nil)
      @series = series
      @csrf = csrf
    end

    def view_template
      render SeriesDetail.new(series: @series, csrf: @csrf)
    end
  end
end
