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
      [{prefab_1, %Health{current: 100}}, {prefab_2, %Health{current: 50}}]
  """
  def all(component_type) when is_atom(component_type),
    do: Genesis.Query.all(:prefabs, component_type)

  @doc """
  Retrieves the component attached to a prefab.
  Returns the component struct if present or `nil`.

  ## Examples

      iex> Genesis.Prefab.get(Health, prefab)
      %Health{current: 100}
  """
  def get(component_type, entity, default \\ nil) when is_atom(component_type),
    do: Genesis.Query.get(:prefabs, component_type, entity, default)

  @doc """
  Returns all prefab components that match the given properties.

  ## Examples

      iex> Genesis.Prefab.match(Moniker, name: "Tripida")
      [{prefab, %Moniker{name: "Tripida"}}]
  """
  def match(component_type, pairs) when is_atom(component_type),
    do: Genesis.Query.match(:prefabs, component_type, pairs)

  @doc """
  Returns all prefab components that have the given property with a value greater than or equal to the given minimum.

  ## Examples

      iex> Genesis.Prefab.at_least(Health, :current, 50)
      [{prefab, %Health{current: 75}}]
  """
  def at_least(component_type, key, value)
      when is_atom(component_type) and is_atom(key) and is_integer(value),
      do: Genesis.Query.at_least(:prefabs, component_type, key, value)

  @doc """
  Returns all prefab components that have the given property with a value less than or equal to the given maximum.

  ## Examples

      iex> Genesis.Prefab.at_most(Health, :current, 50)
      [{prefab, %Health{current: 25}}]
  """
  def at_most(component_type, key, value)
      when is_atom(component_type) and is_atom(key) and is_integer(value),
      do: Genesis.Query.at_most(:prefabs, component_type, key, value)

  @doc """
  Returns all prefab components that have the given property with a value between the given minimum and maximum (inclusive).

  ## Examples

      iex> Genesis.Prefab.between(Health, :current, 50, 100)
      [{prefab, %Health{current: 75}}]
  """
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
