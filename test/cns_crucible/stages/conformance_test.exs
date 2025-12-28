defmodule CnsCrucible.Stages.ConformanceTest do
  @moduledoc """
  Conformance tests for CNS stage describe/1 contract compliance.

  All CNS stages must implement the Crucible.Stage behaviour with
  a describe/1 callback returning the canonical schema format.
  """
  use ExUnit.Case

  alias CnsCrucible.Stages.{
    AntagonistMetrics,
    LabelingQueue,
    ProposerMetrics,
    SynthesizerMetrics
  }

  @stages [
    ProposerMetrics,
    AntagonistMetrics,
    SynthesizerMetrics,
    LabelingQueue
  ]

  @valid_type_specs [
    :string,
    :integer,
    :float,
    :boolean,
    :atom,
    :map,
    :list,
    :module,
    :any
  ]

  describe "all CNS stages implement describe/1" do
    for stage <- @stages do
      test "#{inspect(stage)} has describe/1" do
        Code.ensure_loaded!(unquote(stage))
        assert function_exported?(unquote(stage), :describe, 1)
      end

      test "#{inspect(stage)} returns valid schema" do
        schema = unquote(stage).describe(%{})
        assert is_atom(schema.name)
        assert is_binary(schema.description)
        assert is_list(schema.required)
        assert is_list(schema.optional)
        assert is_map(schema.types)
      end

      test "#{inspect(stage)} has types for all optional fields" do
        schema = unquote(stage).describe(%{})

        for key <- schema.optional do
          assert Map.has_key?(schema.types, key),
                 "Optional field #{key} missing from types"
        end
      end

      test "#{inspect(stage)} has types for all required fields" do
        schema = unquote(stage).describe(%{})

        for key <- schema.required do
          assert Map.has_key?(schema.types, key),
                 "Required field #{key} missing from types"
        end
      end

      test "#{inspect(stage)} has disjoint required and optional" do
        schema = unquote(stage).describe(%{})

        intersection =
          MapSet.intersection(
            MapSet.new(schema.required),
            MapSet.new(schema.optional)
          )

        assert MapSet.size(intersection) == 0,
               "Keys #{inspect(MapSet.to_list(intersection))} in both required and optional"
      end

      test "#{inspect(stage)} defaults are only for optional fields" do
        schema = unquote(stage).describe(%{})

        if Map.has_key?(schema, :defaults) do
          for key <- Map.keys(schema.defaults) do
            assert key in schema.optional,
                   "Default for #{key} but not in optional"
          end
        end
      end

      test "#{inspect(stage)} has valid type specs" do
        schema = unquote(stage).describe(%{})

        for {key, type_spec} <- schema.types do
          assert valid_type_spec?(type_spec),
                 "Invalid type spec for #{key}: #{inspect(type_spec)}"
        end
      end
    end
  end

  # Type spec validation helpers
  defp valid_type_spec?(spec) when spec in @valid_type_specs, do: true
  defp valid_type_spec?({:struct, mod}) when is_atom(mod), do: true
  defp valid_type_spec?({:enum, values}) when is_list(values), do: true
  defp valid_type_spec?({:list, inner}), do: valid_type_spec?(inner)
  defp valid_type_spec?({:function, arity}) when is_integer(arity), do: true

  defp valid_type_spec?({:union, types}) when is_list(types),
    do: Enum.all?(types, &valid_type_spec?/1)

  defp valid_type_spec?({:map, k, v}), do: valid_type_spec?(k) and valid_type_spec?(v)
  defp valid_type_spec?(_), do: false
end
