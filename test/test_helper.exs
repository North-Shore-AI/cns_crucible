Application.put_env(:crucible_framework, :enable_repo, false)
Application.put_env(:crucible_framework, :ecto_repos, [])
ExUnit.start()
