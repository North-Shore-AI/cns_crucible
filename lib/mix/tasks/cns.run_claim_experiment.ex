defmodule Mix.Tasks.Cns.RunClaimExperiment do
  @moduledoc """
  Run the CNS claim extraction experiment.

  ## Usage

      mix cns.run_claim_experiment [--limit N]

  ## Options

    * `--limit` - Number of examples to process (default: 50)
  """

  use Mix.Task

  @shortdoc "Run CNS claim extraction experiment"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [limit: :integer]
      )

    Mix.Task.run("app.start")

    limit = Keyword.get(opts, :limit, 50)
    IO.puts("Running CNS claim extraction experiment...")
    IO.puts("  Limit: #{limit}")
    IO.puts("")

    {:ok, report} = CnsExperiments.Experiments.ClaimExtraction.run(limit: limit)
    IO.puts(report)
  end
end
