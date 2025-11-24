defmodule CnsExperiments.Adapters.Metrics do
  @moduledoc """
  Implementation of `Crucible.CNS.Adapter` that wires CNS metrics into Crucible.

  Derived from the former `CNS.CrucibleAdapter`, now hosted in the integration
  app to keep `cns` free of Crucible dependencies.
  """

  @behaviour Crucible.CNS.Adapter

  require Logger

  alias CNS.{Config, SNO, Topology}
  alias CNS.Validation.Semantic
  alias CnsExperiments.Adapters.Common

  @impl true
  @spec evaluate(list(map()), list(String.t()), map()) :: {:ok, map()} | {:error, term()}
  def evaluate(examples, outputs, opts \\ %{})

  def evaluate([], [], _opts), do: {:ok, empty_metrics()}

  def evaluate(examples, outputs, _opts) when length(examples) != length(outputs) do
    {:error,
     {:mismatched_lengths,
      "examples count (#{length(examples)}) != outputs count (#{length(outputs)})"}}
  end

  def evaluate(examples, outputs, opts) do
    opts = normalize_opts(opts)

    try do
      parsed_results = Common.parse_outputs(outputs)
      corpus = build_corpus(examples)
      snos = Common.extract_snos(parsed_results)

      schema_metrics = compute_schema_metrics(parsed_results)
      citation_metrics = compute_citation_metrics(snos, corpus)
      semantic_metrics = compute_semantic_metrics(examples, outputs, snos, corpus, opts)
      topology_metrics = compute_topology_metrics(snos)
      chirality_metrics = compute_chirality_metrics(snos)

      overall_metrics =
        compute_overall_quality(
          schema_metrics,
          citation_metrics,
          semantic_metrics,
          topology_metrics,
          chirality_metrics
        )

      metrics =
        %{}
        |> Map.merge(schema_metrics)
        |> Map.merge(citation_metrics)
        |> Map.merge(semantic_metrics)
        |> Map.merge(topology_metrics)
        |> Map.merge(chirality_metrics)
        |> Map.merge(overall_metrics)

      {:ok, metrics}
    rescue
      e ->
        Logger.error(
          "[CnsExperiments.Adapters.Metrics] evaluation failed: #{Exception.message(e)}"
        )

        {:error, Exception.message(e)}
    end
  end

  defp normalize_opts(nil), do: %{}
  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(_), do: %{}

  defp empty_metrics do
    %{
      schema_compliance: 1.0,
      parseable_count: 0,
      unparseable_count: 0,
      citation_accuracy: 1.0,
      valid_citations: 0,
      invalid_citations: 0,
      hallucinated_citations: 0,
      mean_entailment: nil,
      mean_similarity: nil,
      topology: %{
        mean_beta1: 0.0,
        max_beta1: 0,
        dag_count: 0,
        cyclic_count: 0
      },
      chirality: %{
        mean_score: 0.0,
        polarity_conflicts: 0,
        high_conflict_count: 0
      },
      overall_quality: 1.0,
      meets_threshold: true
    }
  end

  defp build_corpus(examples) do
    Enum.reduce(examples, %{}, fn example, acc ->
      case example do
        %{"metadata" => %{"doc_ids" => doc_ids}} when is_list(doc_ids) ->
          Enum.reduce(doc_ids, acc, fn doc_id, inner_acc ->
            Map.put(inner_acc, to_string(doc_id), %{
              "id" => to_string(doc_id),
              "text" => Map.get(example, "prompt", ""),
              "abstract" => Map.get(example, "completion", "")
            })
          end)

        %{"metadata" => %{doc_ids: doc_ids}} when is_list(doc_ids) ->
          Enum.reduce(doc_ids, acc, fn doc_id, inner_acc ->
            Map.put(inner_acc, to_string(doc_id), %{
              "id" => to_string(doc_id),
              "text" => Map.get(example, "prompt", ""),
              "abstract" => Map.get(example, "completion", "")
            })
          end)

        _ ->
          acc
      end
    end)
  end

  defp compute_schema_metrics(parsed_results) do
    total = length(parsed_results)
    parseable = Enum.count(parsed_results, & &1.success)
    unparseable = total - parseable

    compliance = if total > 0, do: parseable / total, else: 1.0

    %{
      schema_compliance: Float.round(compliance, 4),
      parseable_count: parseable,
      unparseable_count: unparseable
    }
  end

  defp compute_citation_metrics(snos, corpus) do
    all_citations =
      snos
      |> Enum.flat_map(fn sno ->
        Enum.map(sno.evidence, fn evidence ->
          case Regex.run(~r/Document\s+(\d+)/, evidence.source) do
            [_, doc_id] -> doc_id
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
      end)

    if Enum.empty?(all_citations) do
      %{
        citation_accuracy: 1.0,
        valid_citations: 0,
        invalid_citations: 0,
        hallucinated_citations: 0
      }
    else
      valid = Enum.count(all_citations, &Map.has_key?(corpus, &1))
      invalid = length(all_citations) - valid

      %{
        citation_accuracy: Float.round(valid / length(all_citations), 4),
        valid_citations: valid,
        invalid_citations: invalid,
        hallucinated_citations: invalid
      }
    end
  end

  defp compute_semantic_metrics(examples, outputs, snos, _corpus, _opts) do
    if length(examples) > 0 and length(outputs) > 0 do
      similarities =
        Enum.zip(examples, outputs)
        |> Enum.map(fn {example, output} ->
          expected = Map.get(example, "completion", "")
          Semantic.compute_similarity(expected, output)
        end)

      entailments =
        snos
        |> Enum.map(fn sno ->
          sno.confidence * SNO.evidence_score(sno)
        end)

      mean_sim =
        if length(similarities) > 0 do
          Float.round(Enum.sum(similarities) / length(similarities), 4)
        else
          nil
        end

      mean_ent =
        if length(entailments) > 0 do
          Float.round(Enum.sum(entailments) / length(entailments), 4)
        else
          nil
        end

      %{
        mean_entailment: mean_ent,
        mean_similarity: mean_sim
      }
    else
      %{
        mean_entailment: nil,
        mean_similarity: nil
      }
    end
  end

  defp compute_topology_metrics(snos) do
    if Enum.empty?(snos) do
      %{
        topology: %{
          mean_beta1: 0.0,
          max_beta1: 0,
          dag_count: 0,
          cyclic_count: 0
        }
      }
    else
      graph = Topology.build_graph(snos)
      betti = Topology.betti_numbers(graph)
      is_dag = Topology.is_dag?(graph)
      cycles = Topology.detect_cycles(graph)

      %{
        topology: %{
          mean_beta1: Float.round(betti.b1 / max(1, length(snos)), 4),
          max_beta1: betti.b1,
          dag_count: if(is_dag, do: 1, else: 0),
          cyclic_count: length(cycles)
        }
      }
    end
  end

  defp compute_chirality_metrics(snos) do
    if Enum.empty?(snos) do
      %{
        chirality: %{
          mean_score: 0.0,
          polarity_conflicts: 0,
          high_conflict_count: 0
        }
      }
    else
      conflicts = detect_polarity_conflicts(snos)

      chirality_score =
        if length(conflicts) > 0 do
          Float.round(length(conflicts) / length(snos), 4)
        else
          0.0
        end

      %{
        chirality: %{
          mean_score: chirality_score,
          polarity_conflicts: length(conflicts),
          high_conflict_count: Enum.count(conflicts, fn {_a, _b, score} -> score > 0.7 end)
        }
      }
    end
  end

  defp detect_polarity_conflicts(snos) do
    pairs = for a <- snos, b <- snos, a.id < b.id, do: {a, b}

    Enum.flat_map(pairs, fn {sno_a, sno_b} ->
      if contains_opposition?(sno_a.claim, sno_b.claim) do
        [{sno_a.id, sno_b.id, 0.8}]
      else
        []
      end
    end)
  end

  defp contains_opposition?(text_a, text_b) do
    opposites = [
      {"increases", "decreases"},
      {"supports", "refutes"},
      {"true", "false"},
      {"yes", "no"},
      {"positive", "negative"}
    ]

    text_a_lower = String.downcase(text_a)
    text_b_lower = String.downcase(text_b)

    Enum.any?(opposites, fn {word_a, word_b} ->
      (String.contains?(text_a_lower, word_a) and String.contains?(text_b_lower, word_b)) or
        (String.contains?(text_a_lower, word_b) and String.contains?(text_b_lower, word_a))
    end)
  end

  defp compute_overall_quality(schema, citation, semantic, topology, chirality) do
    targets = Config.quality_targets()

    weights = %{
      schema: 0.25,
      citation: 0.25,
      semantic: 0.30,
      topology: 0.10,
      chirality: 0.10
    }

    schema_score = schema.schema_compliance
    citation_score = citation.citation_accuracy
    semantic_score = semantic.mean_entailment || semantic.mean_similarity || 0.5
    topology_score = 1.0 - min(1.0, topology.topology.mean_beta1)
    chirality_score = 1.0 - chirality.chirality.mean_score

    overall =
      weights.schema * schema_score +
        weights.citation * citation_score +
        weights.semantic * semantic_score +
        weights.topology * topology_score +
        weights.chirality * chirality_score

    meets_threshold =
      schema.schema_compliance >= targets.schema_compliance and
        citation.citation_accuracy >= targets.citation_accuracy and
        (semantic.mean_entailment || 0.5) >= targets.mean_entailment

    %{
      overall_quality: Float.round(overall, 4),
      meets_threshold: meets_threshold
    }
  end
end
