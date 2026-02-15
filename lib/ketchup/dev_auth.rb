# frozen_string_literal: true

module Ketchup
  class DevAuth
    def initialize(app, default_user)
      login, name = default_user.split(":", 2)
      @app = app
      @login = login
      @name = name || login
    end

    def call(env)
      unless env["HTTP_TAILSCALE_USER_LOGIN"]
        env["HTTP_TAILSCALE_USER_LOGIN"] = @login
        env["HTTP_TAILSCALE_USER_NAME"] = @name
      end
      @app.call(env)
    end
  end
end
