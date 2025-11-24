defmodule Crucible.Lora do
  @moduledoc """
  Lightweight stub to preserve compatibility with legacy CNS experiment modules.

  The modern pipeline uses `Crucible.IR.Experiment` with `CrucibleFramework.run/1`.
  These functions return simple defaults so older helper modules continue to compile.
  """

  @type experiment :: %{id: String.t()}

  def create_experiment(opts) do
    {:ok, %{id: "legacy-#{System.unique_integer([:positive])}", opts: opts}}
  end

  def batch_dataset(data, batch_size) when is_list(data) do
    Enum.chunk_every(data, batch_size)
  end

  def adapter_module, do: __MODULE__

  def start_session(_experiment), do: {:ok, :legacy_session}

  def forward_backward(_session, batch, _opts), do: {:ok, %{loss: 0.0, batch: batch}}

  def format_training_data(batch, _opts), do: batch

  def calculate_metrics(results) when is_list(results) do
    losses =
      results
      |> Enum.flat_map(fn
        %{loss: loss} -> [loss]
        _ -> []
      end)

    mean_loss = if losses == [], do: 0.0, else: Enum.sum(losses) / length(losses)

    %{
      total_steps: length(results),
      mean_loss: mean_loss
    }
  end

  def checkpoint_name(experiment_id, step), do: "#{experiment_id}_checkpoint_#{step}"

  def create_sampler(_session, _checkpoint_name), do: {:ok, :legacy_sampler}

  def sample(_sampler, _prompt, _opts), do: {:ok, ["legacy-completion"]}
end
