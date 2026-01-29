defmodule Genesis.Utils do
  @moduledoc false

  defguard is_min_max(min, max) when is_integer(min) and is_integer(max) and min <= max

  defguard is_non_empty_pairs(properties)
           when (is_list(properties) and properties != []) or
                  (is_non_struct_map(properties) and properties != %{})

  def aliasify(module) when is_atom(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  def component?(module) when is_atom(module) do
    attributes = module.__info__(:attributes)
    # NOTE: For some reason, we get two keys for :behaviour
    behaviours = Keyword.get_values(attributes, :behaviour)
    Genesis.Component in List.flatten(behaviours)
  end

  def merge_components(original, overrides) do
    expanded = expand_components(overrides)
    merged = Map.merge(original, expanded, fn _k, v1, v2 -> Map.merge(v1, v2) end)
    Enum.map(merged, fn {component_type, properties} -> component_type.new(properties) end)
  end

  def extract_properties(components) do
    Enum.reduce(components, %{}, fn component, acc ->
      Map.put(acc, component.__struct__, Map.from_struct(component))
    end)
  end

  def expand_components(component_lookup) do
    components = Genesis.Manager.components()

    Enum.reduce(component_lookup, %{}, fn {name, properties}, acc ->
      case Map.fetch(components, name) do
        {:ok, component_type} ->
          component_type = Code.ensure_loaded!(component_type)
          Map.put(acc, component_type, properties)

        :error ->
          raise ArgumentError,
                "component #{inspect(name)} is not registered. " <>
                  "Ensure it is registered with Genesis.Manager.register_components/1 first"
      end
    end)
  end
end
