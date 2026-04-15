import Config

config :specprompt, SpecPromptWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test-only-secret-key-base-that-is-at-least-64-bytes-long-for-specprompt-test",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
