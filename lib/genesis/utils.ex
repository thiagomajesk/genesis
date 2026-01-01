defmodule Genesis.Utils do
  @moduledoc false

  defguard is_name(name) when is_binary(name) or is_atom(name)
  defguard is_handle(term) when is_reference(term) or is_name(term)

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
    Enum.reduce(component_lookup, %{}, fn {name, properties}, acc ->
      case Genesis.Registry.lookup(:components, name) do
        {_entity, _name, metadata} ->
          component_type = Code.ensure_loaded!(metadata.type)
          Map.put(acc, component_type, properties)

        nil ->
          raise ArgumentError,
                "component #{inspect(name)} is not registered. " <>
                  "Ensure it is registered with Genesis.Manager.register_components/1 first"
      end
    end)
  end
end
