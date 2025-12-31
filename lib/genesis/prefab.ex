defmodule Genesis.Prefab do
  @moduledoc """
  Provides querying capabilities for prefabs registered in the manager.

  Prefabs are templates for creating entities with predefined components and properties.
  They can extend other prefabs to inherit their components, and override or merge properties.
  """

  defstruct name: nil, extends: [], components: []

  alias __MODULE__

  @doc """
  Returns all prefab components of the given type.
  Returns a list of tuples containing the prefab and the component struct.

  ## Examples

      iex> Genesis.Prefab.all(Health)
      [{entity_1, %Health{current: 100}}, {entity_2, %Health{current: 50}}]
  """
  def all(component_type) when is_atom(component_type),
    do: Genesis.Query.__all__(:prefabs, component_type)

  @doc """
  Retrieves the component attached to a prefab.
  Returns the component struct if present or `nil`.

  ## Examples

      iex> Genesis.Prefab.get(Health, entity_1)
      %Health{current: 100}
  """
  def get(component_type, entity, default \\ nil) when is_atom(component_type),
    do: Genesis.Query.__get__(:prefabs, component_type, entity, default)

  @doc """
  Returns all prefab components that match the given properties.

  ## Examples

      iex> Genesis.Prefab.match(Moniker, name: "Tripida")
      [{entity_1, %Moniker{name: "Tripida"}}]
  """
  def match(component_type, pairs) when is_atom(component_type),
    do: Genesis.Query.__match__(:prefabs, component_type, pairs)

  @doc """
  Returns all prefab components that have the given property with a value greater than or equal to the given minimum.

  ## Examples

      iex> Genesis.Prefab.at_least(Health, :current, 50)
      [{entity_1, %Health{current: 75}}]
  """
  def at_least(component_type, key, value)
      when is_atom(component_type) and is_atom(key) and is_integer(value),
      do: Genesis.Query.__at_least__(:prefabs, component_type, key, value)

  @doc """
  Returns all prefab components that have the given property with a value less than or equal to the given maximum.

  ## Examples

      iex> Genesis.Prefab.at_most(Health, :current, 50)
      [{entity_1, %Health{current: 25}}]
  """
  def at_most(component_type, key, value)
      when is_atom(component_type) and is_atom(key) and is_integer(value),
      do: Genesis.Query.__at_most__(:prefabs, component_type, key, value)

  @doc """
  Returns all prefab components that have the given property with a value between the given minimum and maximum (inclusive).

  ## Examples

      iex> Genesis.Prefab.between(Health, :current, 50, 100)
      [{entity_1, %Health{current: 75}}]
  """
  def between(component_type, key, min, max)
      when is_atom(component_type) and is_atom(key) and
             is_integer(min) and is_integer(max) and min <= max,
      do: Genesis.Query.__between__(:prefabs, component_type, key, min, max)

  @doc false
  def load(attrs) do
    name = Map.fetch!(attrs, :name)
    extends = Map.get(attrs, :extends, [])
    components = Map.fetch!(attrs, :components)

    extended = fetch_extended_components(extends, name)
    declared = fetch_declared_components(components, name)

    merged_components = merge_components(declared, extended)
    %Prefab{name: name, extends: extends, components: merged_components}
  end

  defp fetch_extended_components(extends, child_name) do
    Enum.reduce(extends, %{}, fn parent_name, acc ->
      case Genesis.Registry.fetch(:prefabs, parent_name) do
        {_entity, parent_components} ->
          Enum.reduce(parent_components, acc, fn component, acc ->
            Map.put(acc, component.__struct__, Map.from_struct(component))
          end)

        nil ->
          raise ArgumentError,
                "prefab #{inspect(child_name)} extends #{inspect(parent_name)} but #{inspect(parent_name)} is not registered"
      end
    end)
  end

  defp fetch_declared_components(components, prefab_name) do
    Enum.reduce(components, %{}, fn {component_alias, component_props}, acc ->
      case Genesis.Registry.lookup(:components, component_alias) do
        {_entity, _name, metadata} ->
          component_type = Code.ensure_loaded!(metadata.type)
          Map.put(acc, component_type, component_props)

        nil ->
          raise ArgumentError,
                "component #{inspect(component_alias)} used in prefab #{inspect(prefab_name)} is not registered. " <>
                  "Register it with Genesis.Manager.register_components/1 first"
      end
    end)
  end

  defp merge_components(declared, extended) do
    merged = Map.merge(extended, declared, fn _k, v1, v2 -> Map.merge(v1, v2) end)
    Enum.map(merged, fn {component_type, props} -> component_type.new(props) end)
  end
end
