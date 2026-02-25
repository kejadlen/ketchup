# frozen_string_literal: true

require "phlex"

require_relative "../layout"

module Views
  module User
    class Show < Phlex::HTML
      def initialize(current_user:, csrf:, flash: nil)
        @current_user = current_user
        @csrf = csrf
        @flash = flash
      end

      def view_template
        email_path = "/users/#{@current_user[:id]}/email"
        email = @current_user[:email]

        render Layout.new(current_user: @current_user, title: "Settings — Ketchup", active_view: nil, flash: @flash, csrf: @csrf) do
          div(class: "dashboard") do
            div(class: "main-column") do
              section(class: "section", "x-data": "{ editing: false }") do
                div(class: "section-header") do
                  h2(class: "section-title") do
                    span(class: "section-title-text") { "User Settings" }
                  end
                  button(
                    class: "section-edit-btn",
                    "x-show": "!editing",
                    "x-on:click": "editing = true"
                  ) do
                    plain "Edit"
                  end
                  button(
                    class: "section-edit-btn",
                    "x-show": "editing",
                    "x-cloak": true,
                    "x-on:click": "editing = false; document.getElementById('user-form').requestSubmit()"
                  ) do
                    plain "Save"
                  end
                end

                form(method: "post", action: email_path, id: "user-form", style: "display:none") do
                  input(type: "hidden", name: "_csrf", value: @csrf.call(email_path))
                end

                dl(class: "detail-fields") do
                  dt { "Login" }
                  dd { @current_user[:login] }

                  dt { "Email" }
                  dd("x-show": "!editing") do
                    if email
                      plain email
                    else
                      span(class: "detail-placeholder") { "not set" }
                    end
                  end
                  dd("x-show": "editing", "x-cloak": true) do
                    input(
                      type: "email", name: "email",
                      form: "user-form",
                      class: "detail-input",
                      value: email,
                      placeholder: "for notifications"
                    )
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
