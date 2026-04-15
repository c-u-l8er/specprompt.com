import Config

config :specprompt, SpecPromptWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4200")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev-only-secret-key-base-that-is-at-least-64-bytes-long-for-specprompt-dev",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:specprompt, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:specprompt, ~w(--watch)]}
  ]

config :specprompt, SpecPromptWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/specprompt_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :specprompt,
  supabase_url: "https://yiumwgidjvatnbxikzay.supabase.co",
  supabase_key: "sb_publishable_csgpwbx72vBMv0fdipTnVg_JYgHZeRa"

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
