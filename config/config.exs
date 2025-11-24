import Config

# Prevent CrucibleFramework from starting a database repo during tests/examples.
config :crucible_framework, :enable_repo, false

# Provide a minimal repo config to silence connection attempts when the application boots.
config :crucible_framework, CrucibleFramework.Repo,
  database: "placeholder",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"
