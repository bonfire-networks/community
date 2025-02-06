import Config

#### General configuration useful for tests, everything else should be in `community.exs` or `Community.RuntimeConfig`

# You probably won't want to touch these. You might override some in
# other config files.

config :bonfire, :repo_module, Bonfire.Common.Repo

config :phoenix, :json_library, Jason

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :mime, :types, %{
  "application/activity+json" => ["activity+json"]
}

config :community, :otp_app, :community
config :bonfire_common, :otp_app, :community
config :community, :repo_module, Bonfire.Common.Repo
config :community, ecto_repos: [Bonfire.Common.Repo]
config :bonfire_common, :localisation_path, "priv/localisation"

config :bonfire_data_identity, Bonfire.Data.Identity.Credential, hasher_module: Argon2

import_config "community.exs"
# import_config "#{Mix.env()}.exs"
