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
  def load(attrs, opts \\ []) do
    registered_prefabs = Keyword.get(opts, :prefabs, [])
    registered_components = Keyword.get(opts, :components, [])

    name = Map.fetch!(attrs, :name)
    extends = Map.get(attrs, :extends, [])
    components = Map.fetch!(attrs, :components)

    prefabs_lookup = Map.new(registered_prefabs)
    components_lookup = Map.new(registered_components)

    declared = fetch_declared_components(components_lookup, components, name)
    inherited = fetch_inherited_components(prefabs_lookup, extends, name)
    merged_components = merge_components(Map.new(inherited), Map.new(declared))

    %Prefab{name: name, extends: extends, components: merged_components}
  end

  defp fetch_declared_components(components_lookup, components, prefab_name) do
    Enum.map(components, fn {component_alias, props} ->
      component_type = ensure_loaded!(components_lookup, component_alias, prefab_name)
      {component_type, props}
    end)
  end

  defp fetch_inherited_components(prefabs_lookup, extends, prefab_name) do
    Enum.flat_map(extends, fn parent_name ->
      components = fetch_components!(prefabs_lookup, parent_name, prefab_name)
      Enum.map(components, &{&1.__struct__, Map.from_struct(&1)})
    end)
  end

  defp merge_components(inherited, declared) do
    merged = Map.merge(inherited, declared, fn _k, v1, v2 -> Map.merge(v1, v2) end)
    Enum.map(merged, fn {component_type, props} -> component_type.new(props) end)
  end

  defp ensure_loaded!(components_lookup, component_alias, prefab_name) do
    case Map.fetch(components_lookup, component_alias) do
      {:ok, type} ->
        Code.ensure_loaded!(type)

      :error ->
        raise ArgumentError,
              "component #{inspect(component_alias)} used in prefab #{inspect(prefab_name)} is not registered. " <>
                "Register it with Genesis.Manager.register_components/1 first"
    end
  end

  defp fetch_components!(prefabs_lookup, parent_name, child_name) do
    case Map.fetch(prefabs_lookup, parent_name) do
      {:ok, %{components: components}} ->
        components

      :error ->
        raise ArgumentError,
              "prefab #{inspect(child_name)} extends #{inspect(parent_name)} but #{inspect(parent_name)} is not registered"
    end
  end
end
