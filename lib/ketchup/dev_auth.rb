# frozen_string_literal: true

module Ketchup
  class DevAuth
    def initialize(app, login)
      @app = app
      @login = login
      @rack_header = "HTTP_#{CONFIG.auth_header.upcase.tr("-", "_")}"
    end

    def call(env)
      env[@rack_header] ||= @login
      @app.call(env)
    end
  end
end
