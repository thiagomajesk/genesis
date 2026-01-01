defmodule Genesis.Query do
  @moduledoc """
  Provides query functions over registry metadata and components.
  """

  @doc """
  Returns a list of entities that have all the components specified in the list.

  ## Examples

      iex> Genesis.Query.all_of(registry, [Component1, Component2])
      [entity_1, entity_2]
  """
  def all_of(registry, component_types) when is_atom(registry) and is_list(component_types),
    do: search(registry, all: component_types)

  @doc """
  Returns a list of entities that have at least one of the components specified in the list.

  ## Examples

      iex> Genesis.Query.any_of(registry, [Component1, Component2])
      [entity_1, entity_2, entity_3]
  """
  def any_of(registry, component_types) when is_atom(registry) and is_list(component_types),
    do: search(registry, any: component_types)

  @doc """
  Returns a list of entities that do not have any of the components specified in the list.

  ## Examples

      iex> Genesis.Query.none_of(registry, [Component1, Component2])
      [entity_1, entity_2]
  """
  def none_of(registry, component_types) when is_atom(registry) and is_list(component_types),
    do: search(registry, none: component_types)

  @doc """
  Returns a list of entities that match the specified criteria.

  ## Options

    * `:all` - Matches entities that have all the specified components.
    * `:any` - Matches entities that have at least one of the specified components.
    * `:none` - Matches entities that do not have any of the specified components.
  """
  def search(registry, opts) when is_atom(registry) and is_list(opts) do
    all = Keyword.get(opts, :all)
    any = Keyword.get(opts, :any)
    none = Keyword.get(opts, :none)

    all_lookup = all && MapSet.new(all)
    any_lookup = any && MapSet.new(any)
    none_lookup = none && MapSet.new(none)

    registry
    |> Genesis.Registry.metadata()
    |> apply_filter(:all, all_lookup)
    |> apply_filter(:any, any_lookup)
    |> apply_filter(:none, none_lookup)
    |> Enum.map(fn {entity, _metadata} -> entity end)
  end

  @doc false
  def __match__(registry, component_type, properties) do
    guards =
      Enum.map(properties, fn {property, value} ->
        {:==, {:map_get, property, :"$2"}, value}
      end)

    match_spec = [
      {
        {:_, :"$1", component_type, :"$2"},
        [{:is_map, :"$2"} | guards],
        [{{:"$1", :"$2"}}]
      }
    ]

    Genesis.Registry.select(registry, :components, match_spec)
  end

  @doc false
  def __at_least__(registry, component_type, property, value) do
    match_spec = [
      {
        {:_, :"$1", component_type, :"$2"},
        [{:is_map, :"$2"}, {:>=, {:map_get, property, :"$2"}, value}],
        [{{:"$1", :"$2"}}]
      }
    ]

    Genesis.Registry.select(registry, :components, match_spec)
  end

  @doc false
  def __at_most__(registry, component_type, property, value) do
    match_spec = [
      {
        {:_, :"$1", component_type, :"$2"},
        [{:is_map, :"$2"}, {:"=<", {:map_get, property, :"$2"}, value}],
        [{{:"$1", :"$2"}}]
      }
    ]

    Genesis.Registry.select(registry, :components, match_spec)
  end

  @doc false
  def __between__(registry, component_type, property, min, max) do
    match_spec = [
      {
        {:_, :"$1", component_type, :"$2"},
        [
          {:is_map, :"$2"},
          {:"=<", {:map_get, property, :"$2"}, max},
          {:>=, {:map_get, property, :"$2"}, min}
        ],
        [{{:"$1", :"$2"}}]
      }
    ]

    Genesis.Registry.select(registry, :components, match_spec)
  end

  @doc false
  def __all__(registry, component_type) do
    match_spec = [
      {
        {:_, :"$1", component_type, :"$2"},
        [],
        [{{:"$1", :"$2"}}]
      }
    ]

    Genesis.Registry.select(registry, :components, match_spec)
  end

  @doc false
  def __get__(registry, component_type, entity, default) do
    match_spec = [
      {
        {:_, entity, component_type, :"$1"},
        [],
        [:"$1"]
      }
    ]

    case Genesis.Registry.select(registry, :components, match_spec) do
      [component] -> component
      [] -> default
    end
  end

  @doc false
  def __exists__(registry, entity_or_name) do
    Genesis.Registry.exists?(registry, entity_or_name)
  end

  defp apply_filter(stream, _filter, nil), do: stream

  defp apply_filter(stream, :all, lookup) do
    Stream.filter(stream, fn {_entity, {_name, metadata}} ->
      MapSet.subset?(lookup, metadata.types)
    end)
  end

  defp apply_filter(stream, :any, lookup) do
    Stream.filter(stream, fn {_entity, {_name, metadata}} ->
      not MapSet.disjoint?(lookup, metadata.types)
    end)
  end

  defp apply_filter(stream, :none, lookup) do
    Stream.filter(stream, fn {_entity, {_name, metadata}} ->
      MapSet.disjoint?(lookup, metadata.types)
    end)
  end
end
