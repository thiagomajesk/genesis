defmodule Genesis.Prefab do
  @moduledoc """
  Provides querying capabilities for prefabs registered in the manager.

  Prefabs are templates for creating entities with predefined components and properties.
  They can extend other prefabs to inherit their components, and override or merge properties.
  """

  defstruct name: nil, extends: [], components: []

  alias __MODULE__

  def all(component_type) when is_atom(component_type),
    do: Genesis.Query.all(:prefabs, component_type)

  def get(component_type, entity, default \\ nil) when is_atom(component_type),
    do: Genesis.Query.get(:prefabs, component_type, entity, default)

  def match(component_type, pairs) when is_atom(component_type),
    do: Genesis.Query.match(:prefabs, component_type, pairs)

  def at_least(component_type, key, value)
      when is_atom(component_type) and is_atom(key) and is_integer(value),
      do: Genesis.Query.at_least(:prefabs, component_type, key, value)

  def at_most(component_type, key, value)
      when is_atom(component_type) and is_atom(key) and is_integer(value),
      do: Genesis.Query.at_most(:prefabs, component_type, key, value)

  def between(component_type, key, min, max)
      when is_atom(component_type) and is_atom(key) and
             is_integer(min) and is_integer(max) and min <= max,
      do: Genesis.Query.between(:prefabs, component_type, key, min, max)

  @doc false
  def load(attrs, opts \\ []) do
    registered_prefabs = Keyword.get(opts, :prefabs, [])
    registered_components = Keyword.get(opts, :components, [])

    prefabs_lookup = Map.new(registered_prefabs)
    components_lookup = Map.new(registered_components)

    name = Map.fetch!(attrs, :name)
    extends = Map.get(attrs, :extends, [])
    components = Map.fetch!(attrs, :components)

    declared =
      Enum.map(components, fn {component, props} ->
        module = Map.fetch!(components_lookup, component)
        loaded = Code.ensure_loaded!(module)
        {loaded, {:merge, props}}
      end)

    inherited =
      Enum.flat_map(extends, fn name ->
        %{components: components} = Map.fetch!(prefabs_lookup, name)
        Enum.map(components, &{&1.__struct__, {:inherit, Map.from_struct(&1)}})
      end)

    merged_components = merge_components(inherited, declared)
    final_components = Enum.map(merged_components, fn {module, props} -> module.new(props) end)

    %Prefab{name: name, extends: extends, components: final_components}
  end

  defp merge_components(inherited, declared) do
    Enum.reduce(inherited ++ declared, %{}, fn
      {module, {:inherit, props}}, acc ->
        Map.put(acc, module, props)

      {module, {:merge, props}}, acc ->
        case Map.fetch(acc, module) do
          {:ok, existing} ->
            merged = Map.merge(existing, props)
            Map.put(acc, module, merged)

          :error ->
            Map.put(acc, module, props)
        end
    end)
  end
end
