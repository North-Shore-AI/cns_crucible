defmodule Mix.Tasks.Cns.RunClaimExperiment do
  @moduledoc """
  Run the CNS claim extraction experiment.

  ## Usage

      mix cns.run_claim_experiment [--limit N]

  ## Options

    * `--limit` - Number of examples to process (default: 50)
    * `--train` - Enable LoRA training (default: false)
  """

  use Mix.Task

  @shortdoc "Run CNS claim extraction experiment"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [limit: :integer, train: :boolean]
      )

    Mix.Task.run("app.start")

    limit = Keyword.get(opts, :limit, 50)
    train = Keyword.get(opts, :train, false)

    IO.puts("Running CNS claim extraction experiment...")
    IO.puts("  Limit: #{limit}")
    IO.puts("  Train: #{train}")
    IO.puts("")

    {:ok, report} = CnsExperiments.Experiments.ClaimExtraction.run(limit: limit, train: train)
    IO.puts(report)
  end
end
