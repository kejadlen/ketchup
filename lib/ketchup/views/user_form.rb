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

      div(class: "column column-aside", "x-data": "{ editing: false }") do
        div(class: "column-header") do
          h2 { @current_user[:login] }
          button(
            class: "aside-heading-action",
            "x-show": "!editing",
            "x-on:click": "editing = true"
          ) { "Edit" }
          button(
            type: "submit",
            form: "user-form",
            class: "aside-heading-action",
            "x-show": "editing",
            "x-cloak": true
          ) { "Save" }
        end

        form(method: "post", action: email_path, id: "user-form", class: "task-detail") do
          input(type: "hidden", name: "_csrf", value: @csrf.call(email_path))

          dl(class: "task-detail-fields") do
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
