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
        end
        body do
          header(class: "site-header") do
            span(class: "site-name") { "Ketchup" }
            span(class: "user") { @current_user[:name] || @current_user[:login] }
          end
          yield
        end
      end
    end
  end
end
