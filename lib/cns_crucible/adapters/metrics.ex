defmodule CnsCrucible.Adapters.Metrics do
  @moduledoc """
  Implementation of `Crucible.Analysis.Adapter` that wires CNS metrics into Crucible.

  Derived from the former `CNS.CrucibleAdapter`, now hosted in the integration
  app to keep `cns` free of Crucible dependencies.
  """

  require Logger

  alias CNS.{Config, SNO, Topology}
  alias CNS.Validation.Semantic
  alias CnsCrucible.Adapters.Common

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
        Logger.error("[CnsCrucible.Adapters.Metrics] evaluation failed: #{Exception.message(e)}")

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
    Enum.reduce(examples, %{}, &add_example_docs/2)
  end

  defp add_example_docs(example, acc) do
    doc_ids = get_doc_ids(example)
    text = Map.get(example, "prompt", "")
    abstract = Map.get(example, "completion", "")

    Enum.reduce(doc_ids, acc, fn doc_id, inner_acc ->
      Map.put(inner_acc, to_string(doc_id), %{
        "id" => to_string(doc_id),
        "text" => text,
        "abstract" => abstract
      })
    end)
  end

  defp get_doc_ids(%{"metadata" => %{"doc_ids" => doc_ids}}) when is_list(doc_ids), do: doc_ids
  defp get_doc_ids(%{"metadata" => %{doc_ids: doc_ids}}) when is_list(doc_ids), do: doc_ids
  defp get_doc_ids(_), do: []

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
    all_citations = extract_all_citations(snos)
    build_citation_metrics(all_citations, corpus)
  end

  defp extract_all_citations(snos) do
    Enum.flat_map(snos, &extract_sno_citations/1)
  end

  defp extract_sno_citations(sno) do
    sno.evidence
    |> Enum.map(&extract_doc_id/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_doc_id(evidence) do
    case Regex.run(~r/Document\s+(\d+)/, evidence.source) do
      [_, doc_id] -> doc_id
      _ -> nil
    end
  end

  defp build_citation_metrics([], _corpus) do
    %{
      citation_accuracy: 1.0,
      valid_citations: 0,
      invalid_citations: 0,
      hallucinated_citations: 0
    }
  end

  defp build_citation_metrics(citations, corpus) do
    valid = Enum.count(citations, &Map.has_key?(corpus, &1))
    invalid = length(citations) - valid

    %{
      citation_accuracy: Float.round(valid / length(citations), 4),
      valid_citations: valid,
      invalid_citations: invalid,
      hallucinated_citations: invalid
    }
  end

  defp compute_semantic_metrics([], _, _, _, _), do: %{mean_entailment: nil, mean_similarity: nil}
  defp compute_semantic_metrics(_, [], _, _, _), do: %{mean_entailment: nil, mean_similarity: nil}

  defp compute_semantic_metrics(examples, outputs, snos, _corpus, _opts) do
    similarities =
      Enum.zip(examples, outputs)
      |> Enum.map(fn {example, output} ->
        expected = Map.get(example, "completion", "")
        Semantic.compute_similarity(expected, output)
      end)

    entailments =
      Enum.map(snos, fn sno ->
        sno.confidence * SNO.evidence_score(sno)
      end)

    %{
      mean_entailment: safe_mean(entailments),
      mean_similarity: safe_mean(similarities)
    }
  end

  defp safe_mean([]), do: nil
  defp safe_mean(values), do: Float.round(Enum.sum(values) / length(values), 4)

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
      is_dag = Topology.dag?(graph)
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
      conflict_count = length(conflicts)

      chirality_score =
        if conflict_count > 0 do
          Float.round(conflict_count / length(snos), 4)
        else
          0.0
        end

      %{
        chirality: %{
          mean_score: chirality_score,
          polarity_conflicts: conflict_count,
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
