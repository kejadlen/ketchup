# frozen_string_literal: true

require "phlex"

module Views
  class UserForm < Phlex::HTML
    def initialize(current_user:, csrf:)
      @current_user = current_user
      @csrf = csrf
    end

    def view_template
      email_path = "/users/#{@current_user[:id]}/email"
      email = @current_user[:email]

      div(class: "panel-inner", "x-data": "{ editing: false }") do
        div(class: "panel-header") do
          a(href: "/", class: "panel-close", "aria-label": "Close") { "←" }
          div(class: "panel-actions") do
            button(
              class: "panel-action",
              "x-show": "!editing",
              "x-on:click": "editing = true"
            ) { "Edit" }
            button(
              type: "submit",
              form: "user-form",
              class: "panel-action",
              "x-show": "editing",
              "x-cloak": true
            ) { "Save" }
          end
        end

        div(class: "panel-body") do
          h2(class: "panel-body-title") { @current_user[:login] }

          form(method: "post", action: email_path, id: "user-form") do
            input(type: "hidden", name: "_csrf", value: @csrf.call(email_path))

            dl(class: "detail-fields") do
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
