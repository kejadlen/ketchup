# frozen_string_literal: true

require "phlex"

module Views
  class Layout < Phlex::HTML
    def initialize(title: "Ketchup")
      @title = title
    end

    def view_template(&)
      doctype
      html(lang: "en") do
        head do
          meta(charset: "utf-8")
          meta(name: "viewport", content: "width=device-width, initial-scale=1")
          title { @title }
          link(rel: "stylesheet", href: "/css/app.css")
        end
        body(&)
      end
    end
  end
end
