# frozen_string_literal: true

require "digest"
require "phlex"

module Views
  class Layout < Phlex::HTML
    ASSET_VERSIONS = begin
      root = File.expand_path("../../../public", __dir__)
      %w[
        /css/reset.css
        /css/utopia.css
        /css/app.css
        /js/app.js
      ].to_h {|path|
        [path, Digest::MD5.file(File.join(root, path)).hexdigest[0, 10]]
      }.freeze
    end

    def initialize(current_user:, title: "Ketchup", active_view: nil, flash: nil, csrf: nil)
      @current_user = current_user
      @title = title
      @active_view = active_view
      @flash = flash
      @csrf = csrf
    end

    def view_template(&)
      doctype
      html(lang: "en") do
        head do
          meta(charset: "utf-8")
          meta(name: "viewport", content: "width=device-width, initial-scale=1")
          title { @title }
          link(rel: "icon", href: "/favicon.svg", type: "image/svg+xml")
          link(rel: "stylesheet", href: asset_path("/css/reset.css"))
          link(rel: "stylesheet", href: asset_path("/css/utopia.css"))
          link(rel: "stylesheet", href: asset_path("/css/app.css"))
          link(rel: "preconnect", href: "https://fonts.googleapis.com")
          link(rel: "preconnect", href: "https://fonts.gstatic.com", crossorigin: true)
          link(rel: "stylesheet",
               href: "https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&display=swap")
          script(src: "https://unpkg.com/overtype@2.3.4/dist/overtype.min.js",
                 integrity: "sha384-oO6wSYxEDXeZSOcEf28Yv/b18PqYxmhTbhc9Qfn8PSQJxv82nH/6Awq3eCof6VcA",
                 crossorigin: "anonymous")
          script(src: asset_path("/js/app.js"), defer: true)
          script(src: "https://cdn.jsdelivr.net/npm/@alpinejs/persist@3.15.0/dist/cdn.min.js",
                 integrity: "sha384-6WOLkykwLb3YWzXZ6lAq+GI0p3V+enUm9jY6yIXGpIriiAUOSF5dgNJLoSSNam4j",
                 crossorigin: "anonymous", defer: true)
          script(src: "https://cdn.jsdelivr.net/npm/alpinejs@3.15.8/dist/cdn.min.js",
                 integrity: "sha384-LXWjKwDZz29o7TduNe+r/UxaolHh5FsSvy2W7bDHSZ8jJeGgDeuNnsDNHoxpSgDi",
                 crossorigin: "anonymous", defer: true)
        end
        body do
          header(class: "site-header") do
            a(href: "/", class: "site-name") { "Ketchup" }
            nav(class: "site-nav") do
              a(
                href: "/series/new",
                class: ["header-action", ("header-action--active" if @active_view == :new)]
              ) { "+New" }
            end
            a(href: "/users/#{@current_user[:id]}", class: "header-user") { @current_user[:login] }
          end
          render_flash
          yield
          render_footer
        end
      end
    end

    private

    def render_flash
      return unless @flash

      undo_path = @flash["undo_path"]

      div(class: "flash-bar") do
        span(class: "flash-message") { @flash["message"] }
        if undo_path && @csrf
          form(method: "post", action: undo_path, class: "flash-undo-form") do
            input(type: "hidden", name: "_csrf", value: @csrf.call(undo_path))
            button(type: "submit", class: "flash-undo-btn") { "Undo" }
          end
        end
      end
    end

    def asset_path(path)
      version = ASSET_VERSIONS[path]
      version ? "#{path}?v=#{version}" : path
    end

    def render_footer
      config = CONFIG
      parts = []
      parts << config.change_id if config.change_id
      parts << config.commit_sha if config.commit_sha
      parts << config.build_date if config.build_date
      footer(class: "site-footer") do
        plain parts.join(" \u00b7 ")
      end
    end
  end
end
