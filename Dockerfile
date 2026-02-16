FROM ruby:4.0-slim AS build

RUN apt-get update && apt-get install -y build-essential && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set without development && bundle install

COPY . .

FROM ruby:4.0-slim

ARG COMMIT_SHA
ARG CHANGE_ID
ARG BUILD_DATE
ENV COMMIT_SHA=${COMMIT_SHA}
ENV CHANGE_ID=${CHANGE_ID}
ENV BUILD_DATE=${BUILD_DATE}

WORKDIR /app

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app

EXPOSE 9292

CMD ["rackup", "-o", "0.0.0.0"]
