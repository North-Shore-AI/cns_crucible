defmodule CnsExperiments.Adapters.Common do
  @moduledoc """
  Shared helpers for CNS adapter implementations.
  """

  alias CNS.{Evidence, Provenance, SNO}

  @spec build_snos([map()], [any()]) ::
          {:ok, %{snos: [SNO.t()], parsed: [map()]}} | {:error, term()}
  def build_snos(_examples, outputs) do
    parsed = parse_outputs(outputs)
    snos = extract_snos(parsed)

    {:ok, %{snos: snos, parsed: parsed}}
  rescue
    e -> {:error, e}
  end

  @spec parse_outputs([any()]) :: [map()]
  def parse_outputs(outputs) do
    outputs
    |> List.wrap()
    |> Enum.map(&parse_single_output/1)
  end

  @spec extract_snos([map()]) :: [SNO.t()]
  def extract_snos(parsed_results) do
    parsed_results
    |> Enum.filter(& &1.success)
    |> Enum.flat_map(&snos_from_parsed/1)
  end

  @spec graph_from_relations([map()]) :: map()
  def graph_from_relations(relations) do
    relations
    |> Enum.reduce(%{}, fn rel, acc ->
      source = rel[:source] || rel["source"]
      target = rel[:target] || rel["target"]

      acc
      |> Map.update(source, [target], fn children -> [target | children] end)
      |> Map.put_new(target, [])
    end)
    |> Enum.into(%{}, fn {k, v} -> {k, Enum.uniq(v)} end)
  end

  @spec embedding_vectors([map()]) :: [[number()]]
  def embedding_vectors(claims) do
    claims
    |> Enum.map(fn claim ->
      text = claim[:text] || claim["text"] || ""
      words = String.split(to_string(text))
      word_count = length(words)
      char_count = String.length(text)

      [word_count / 10, char_count / 100]
    end)
  end

  defp parse_single_output(output) do
    text =
      cond do
        is_binary(output) ->
          output

        is_map(output) ->
          Map.get(output, :completion) || Map.get(output, "completion") ||
            Map.get(output, :output) || Map.get(output, "output") || ""

        true ->
          to_string(output || "")
      end

    claims = extract_claims(text)
    relations = extract_relations(text)

    %{
      success: length(claims) > 0,
      claims: claims,
      relations: relations,
      raw: text
    }
  rescue
    e ->
      %{
        success: false,
        claims: [],
        relations: [],
        raw: output,
        error: Exception.message(e)
      }
  end

  defp extract_claims(text) do
    ~r/CLAIM\[([^\]]+)\](?:\s*\(Document\s+(\d+)\))?\s*:\s*([^\n]+)/
    |> Regex.scan(text)
    |> Enum.map(fn
      [_full, claim_id, "", claim_text] ->
        %{
          id: claim_id,
          text: String.trim(claim_text),
          doc_ids: []
        }

      [_full, claim_id, doc_id, claim_text] ->
        %{
          id: claim_id,
          text: String.trim(claim_text),
          doc_ids: [doc_id]
        }

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_relations(text) do
    ~r/RELATION:\s*([^\s]+)\s+(supports|refutes|contradicts)\s+([^\s\n]+)/
    |> Regex.scan(text)
    |> Enum.map(fn [_full, source, relation_type, target] ->
      %{
        source: source,
        type: String.to_atom(relation_type),
        target: target
      }
    end)
  end

  defp snos_from_parsed(parsed_result) do
    parsed_result.claims
    |> Enum.map(fn claim ->
      evidence =
        Enum.map(claim.doc_ids, fn doc_id ->
          Evidence.new("Document #{doc_id}", "", validity: 0.9)
        end)

      provenance =
        parsed_result.relations
        |> Enum.filter(fn rel -> rel.target == claim.id end)
        |> Enum.map(& &1.source)
        |> case do
          [] -> nil
          parents -> Provenance.new(:synthesizer, parent_ids: parents)
        end

      SNO.new(claim.text,
        id: claim.id,
        evidence: evidence,
        confidence: 0.8,
        provenance: provenance
      )
    end)
  end
end
