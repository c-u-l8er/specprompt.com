FROM hexpm/elixir:1.17.3-erlang-27.1.2-debian-bookworm-20240904-slim AS build

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get --only prod
RUN mix deps.compile

COPY lib lib
RUN mix compile
RUN mix escript.build

FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y libssl3 libncurses6 locales && rm -rf /var/lib/apt/lists/*
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR /app
COPY --from=build /app/specprompt .

EXPOSE 4000
CMD ["./specprompt", "mcp-server"]
