defmodule CnsExperiments.Data.ScifactLoader do
  @moduledoc """
  Load real SciFact training data from JSONL files.
  """

  @data_path "priv/data/scifact_claim_extractor_clean.jsonl"

  @doc """
  Load SciFact examples from the JSONL file.

  ## Options
    - :limit - Maximum number of examples to load
    - :shuffle - Whether to shuffle the data (default: false)
  """
  def load(opts \\ []) do
    limit = Keyword.get(opts, :limit, :all)
    shuffle = Keyword.get(opts, :shuffle, false)

    path = Application.app_dir(:cns_experiments, @data_path)

    if File.exists?(path) do
      examples =
        path
        |> File.stream!()
        |> Stream.map(&Jason.decode!/1)
        |> Stream.map(&format_example/1)
        |> Enum.to_list()

      examples = if shuffle, do: Enum.shuffle(examples), else: examples

      case limit do
        :all -> {:ok, examples}
        n when is_integer(n) -> {:ok, Enum.take(examples, n)}
      end
    else
      {:error, "SciFact data not found at #{path}"}
    end
  end

  defp format_example(json) do
    %{
      id: "scifact_#{json["metadata"]["claim_id"]}",
      prompt: json["prompt"],
      completion: json["completion"],
      input: json["prompt"],
      output: json["completion"],
      metadata: json["metadata"]
    }
  end
end
