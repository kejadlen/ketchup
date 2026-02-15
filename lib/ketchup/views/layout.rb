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
          link(rel: "stylesheet", href: "/css/reset.css")
          link(rel: "stylesheet", href: "/css/utopia.css")
          link(rel: "stylesheet", href: "/css/app.css")
          script(src: "https://unpkg.com/overtype/dist/overtype.min.js")
          script(src: "/js/app.js", defer: true)
          script(src: "https://cdn.jsdelivr.net/npm/@alpinejs/persist@3/dist/cdn.min.js", defer: true)
          script(src: "https://cdn.jsdelivr.net/npm/alpinejs@3/dist/cdn.min.js", defer: true)
        end
        body do
          header(class: "site-header") do
            a(href: "/", class: "site-name") { "Ketchup" }
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
