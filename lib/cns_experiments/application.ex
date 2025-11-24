defmodule CnsExperiments.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Add supervised children here as needed
      # {CnsExperiments.ModelServer, []}
    ]

    opts = [strategy: :one_for_one, name: CnsExperiments.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
