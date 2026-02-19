# frozen_string_literal: true

require "phlex"

require_relative "user_form"

module Views
  class UserPanel < Phlex::HTML
    def initialize(current_user:, csrf:)
      @current_user = current_user
      @csrf = csrf
    end

    def view_template
      render UserForm.new(current_user: @current_user, csrf: @csrf)
    end
  end
end
