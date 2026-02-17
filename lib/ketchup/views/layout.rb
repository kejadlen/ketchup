# frozen_string_literal: true

require "phlex"

module Views
  class Layout < Phlex::HTML
    def initialize(current_user:, title: "Ketchup")
      @current_user = current_user
      @title = title
    end

    def view_template(&)
      doctype
      html(lang: "en") do
        head do
          meta(charset: "utf-8")
          meta(name: "viewport", content: "width=device-width, initial-scale=1")
          title { @title }
          link(rel: "icon", href: "/favicon.svg", type: "image/svg+xml")
          link(rel: "stylesheet", href: "/css/reset.css")
          link(rel: "stylesheet", href: "/css/utopia.css")
          link(rel: "stylesheet", href: "/css/app.css")
          script(src: "https://unpkg.com/overtype@2.1.1/dist/overtype.min.js",
                 integrity: "sha384-zp8RL0j4VLfaFKgqehca9l8rfcE4Jh0Nt1CFoVyUBn+qa4velUokXJXsW2h0J5xT",
                 crossorigin: "anonymous")
          script(src: "/js/app.js", defer: true)
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
            a(href: "/series/new", class: "mobile-new-link") { "+ New" }
            span(class: "user") { @current_user[:name] || @current_user[:login] }
          end
          yield
          render_footer
        end
      end
    end

    private

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
