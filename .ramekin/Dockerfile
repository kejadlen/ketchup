FROM ruby:4.0-slim AS ruby

FROM ramekin-agent

RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    libyaml-0-2 \
    libsqlite3-dev \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Ruby 4.0 from the official image (Debian repos only have 3.3).
COPY --from=ruby /usr/local/bin/ruby /usr/local/bin/
COPY --from=ruby /usr/local/bin/bundle /usr/local/bin/
COPY --from=ruby /usr/local/lib/libruby.so* /usr/local/lib/
COPY --from=ruby /usr/local/lib/ruby/ /usr/local/lib/ruby/
COPY --from=ruby /usr/local/include/ /usr/local/include/

# For bootstrapping, so that we can use `rake` to create binstubs
COPY --from=ruby /usr/local/bin/rake /usr/local/bin/
RUN bundle config set --global bin /usr/local/bin

# Install gems (including dev group for tests and snapshots).
COPY Gemfile Gemfile.lock ./
RUN bundle install

WORKDIR /workspace

ENV RANGER_DEFAULT_BACKLOG=ketchup

ENTRYPOINT ["pi"]
