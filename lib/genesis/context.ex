defmodule Genesis.Context do
  @moduledoc """
  Provides low-level entity storage backed by ETS.

  A context contains two ETS tables that are always kept in sync.

    * `Metadata` - stores entity metadata such as name and custom data
    * `Components` - stores components associated with entities

  NOTE: most read operations are intentionally dirty reads for performance reasons.
  """

  use GenServer

  import Genesis.Utils, only: [is_non_empty_pairs: 1, is_min_max: 2]

  def start_link(args \\ []) do
    name = Keyword.get(args, :name)
    GenServer.start_link(__MODULE__, args, name: name)
  end

  def child_spec(args) do
    id = Keyword.get(args, :name, __MODULE__)
    restart = Keyword.get(args, :restart, :temporary)

    %{
      id: id,
      start: {__MODULE__, :start_link, [args]},
      type: :worker,
      restart: restart,
      shutdown: :brutal_kill
    }
  end

  @doc """
  Creates a new entity in the context with the given options.

  Options:
    * `:name` - an optional name for the entity
    * `:metadata` - an optional map of metadata to associate with the entity

  See `Genesis.Entity.new/1` for additional options.
  Note that the created entity has its context set automatically.
  """
  def create(context, opts \\ []) do
    GenServer.call(context, {:create, opts})
  end

  @doc """
  Retrieves information about an entity.
  Returns `{entity, types, metadata}` if found, or `nil`.
  """
  def info(context, %Genesis.Entity{} = entity) do
    mtable = table!(context, :metadata)

    case :ets.lookup(mtable, entity) do
      [] ->
        nil

      [{^entity, types, metadata}] ->
        {entity, types, metadata}
    end
  end

  @doc """
  Associates a component to an entity, fails if the component type is already present.
  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  def emplace(context, %Genesis.Entity{} = entity, component) when is_struct(component) do
    GenServer.call(context, {:emplace, entity, component})
  end

  @doc """
  Replaces an existing component on an entity.
  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  def replace(context, %Genesis.Entity{} = entity, component) when is_struct(component) do
    GenServer.call(context, {:replace, entity, component})
  end

  @doc """
  Deletes all data from the context tables.
  """
  def clear(context) do
    GenServer.call(context, :clear)
  end

  @doc """
  Replaces the metadata of an entity.
  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  def patch(context, %Genesis.Entity{} = entity, metadata) when is_map(metadata) do
    GenServer.call(context, {:patch, entity, metadata})
  end

  @doc """
  Erases all components of an entity.
  When the `component_type` is provided, only that component is erased.
  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  def erase(context, %Genesis.Entity{} = entity, component_type \\ nil)
      when is_atom(component_type) do
    GenServer.call(context, {:erase, entity, component_type})
  end

  @doc """
  Assigns components to an existing entity.
  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  def assign(context, %Genesis.Entity{} = entity, components) when is_list(components) do
    GenServer.call(context, {:assign, entity, components})
  end

  @doc """
  Destroys an entity and removes all associated data.
  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  def destroy(context, %Genesis.Entity{} = entity) do
    GenServer.call(context, {:destroy, entity})
  end

  @doc """
  Looks up an entity by a registered name.
  Returns `{entity, types, metadata}` if found, or `nil`.
  """
  def lookup(context, name) when is_binary(name) do
    mtable = table!(context, :metadata)

    match_spec = [
      {
        {:"$1", :"$2", :"$3"},
        [{:==, {:map_get, :name, :"$1"}, name}],
        [{{:"$1", :"$2", :"$3"}}]
      }
    ]

    case :ets.select(mtable, match_spec) do
      [] ->
        nil

      [{entity, types, metadata}] ->
        {entity, types, metadata}
    end
  end

  @doc """
  Checks if an entity or name exists in the context.
  Returns `true` if found, or `false` otherwise.
  """
  def exists?(context, entity_or_name)

  def exists?(context, %Genesis.Entity{} = entity) do
    :ets.member(table!(context, :metadata), entity)
  end

  def exists?(context, name) when is_binary(name) do
    match?({_entity, _types, _metadata}, lookup(context, name))
  end

  @doc """
  Fetches all components of an entity.
  Returns `{entity, components}` if found, or `nil`.
  """
  def fetch(context, entity_or_name)

  def fetch(context, name) when is_binary(name) do
    with {entity, _types, _metadata} <- lookup(context, name), do: fetch(context, entity)
  end

  def fetch(context, %Genesis.Entity{} = entity) do
    mtable = table!(context, :metadata)
    ctable = table!(context, :components)

    case :ets.lookup(mtable, entity) do
      [] ->
        nil

      [{^entity, _types, _metadata}] ->
        match_spec = [{{entity, :_, :"$1"}, [], [:"$1"]}]
        {entity, :ets.select(ctable, match_spec)}
    end
  end

  @doc """
  Returns all entities with components of the given type.
  Returns a list of tuples containing the entity and the component struct.

  ## Examples

      iex> Genesis.Context.all(context, Health)
      [{entity_1, %Health{current: 100}}, {entity_2, %Health{current: 50}}]
  """
  def all(context, component_type) when is_atom(component_type) do
    ctable = table!(context, :components)

    :ets.select(ctable, [
      {
        {:"$1", component_type, :"$2"},
        [],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  @doc """
  Retrieves the component attached to an entity.
  Returns the component struct if present or default.

  ## Examples

      iex> Genesis.Context.get(context, entity_1, Health)
      %Health{current: 100}
  """
  def get(context, %Genesis.Entity{} = entity, component_type, default \\ nil)
      when is_atom(component_type) do
    ctable = table!(context, :components)

    match_spec = [
      {
        {entity, component_type, :"$1"},
        [],
        [:"$1"]
      }
    ]

    case :ets.select(ctable, match_spec) do
      [component] -> component
      [] -> default
    end
  end

  @doc """
  Returns all entities that match the given properties for the component type.

  ## Examples

      iex> Genesis.Context.match(context, Moniker, name: "Tripida")
      [{entity_1, %Moniker{name: "Tripida"}}]
  """
  def match(context, component_type, properties)
      when is_atom(component_type) and is_non_empty_pairs(properties) do
    ctable = table!(context, :components)

    guards =
      Enum.map(properties, fn {property, value} ->
        {:==, {:map_get, property, :"$2"}, value}
      end)

    :ets.select(ctable, [
      {
        {:"$1", component_type, :"$2"},
        [{:is_map, :"$2"} | guards],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  @doc """
  Returns all entities that have the given property with a value greater than or equal to the given minimum.

  ## Examples

      iex> Genesis.Context.at_least(context, Health, :current, 50)
      [{entity_1, %Health{current: 75}}]
  """
  def at_least(context, component_type, property, value)
      when is_atom(component_type) and is_atom(property) do
    ctable = table!(context, :components)

    :ets.select(ctable, [
      {
        {:"$1", component_type, :"$2"},
        [{:is_map, :"$2"}, {:>=, {:map_get, property, :"$2"}, value}],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  @doc """
  Returns all entities that have the given property with a value less than or equal to the given maximum.

  ## Examples

      iex> Genesis.Context.at_most(context, Health, :current, 50)
      [{entity_1, %Health{current: 25}}]
  """
  def at_most(context, component_type, property, value)
      when is_atom(component_type) and is_atom(property) do
    ctable = table!(context, :components)

    :ets.select(ctable, [
      {
        {:"$1", component_type, :"$2"},
        [{:is_map, :"$2"}, {:"=<", {:map_get, property, :"$2"}, value}],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  @doc """
  Returns all entities that have the given property with a value between the given minimum and maximum (inclusive).

  ## Examples

      iex> Genesis.Context.between(context, Health, :current, 50, 100)
      [{entity_1, %Health{current: 75}}]
  """
  def between(context, component_type, property, min, max)
      when is_atom(component_type) and is_atom(property) and is_min_max(min, max) do
    ctable = table!(context, :components)

    :ets.select(ctable, [
      {
        {:"$1", component_type, :"$2"},
        [
          {:is_map, :"$2"},
          {:"=<", {:map_get, property, :"$2"}, max},
          {:>=, {:map_get, property, :"$2"}, min}
        ],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  @doc """
  Returns a list of entities that are direct children of the given entity.

  ## Examples

      iex> Genesis.Context.children_of(context, entity_1)
      [entity_2, entity_3, entity_4, ...]
  """
  def children_of(context, %Genesis.Entity{} = entity) do
    mtable = table!(context, :metadata)

    :ets.select(mtable, [
      {
        {:"$1", :"$2", :"$3"},
        [{:==, {:map_get, :parent, :"$1"}, entity}],
        [:"$1"]
      }
    ])
  end

  @doc """
  Returns a list of entities that have all the components specified in the list.

  ## Examples

      iex> Genesis.Context.all_of(context, [Component1, Component2])
      [entity_1, entity_2]
  """
  def all_of(context, component_types) when is_list(component_types) do
    search(context, all: component_types)
  end

  @doc """
  Returns a list of entities that have at least one of the components specified in the list.

  ## Examples

      iex> Genesis.Context.any_of(context, [Component1, Component2])
      [entity_1, entity_2, entity_3]
  """
  def any_of(context, component_types) when is_list(component_types) do
    search(context, any: component_types)
  end

  @doc """
  Returns a list of entities that do not have any of the components specified in the list.

  ## Examples

      iex> Genesis.Context.none_of(context, [Component1, Component2])
      [entity_1, entity_2]
  """
  def none_of(context, component_types) when is_list(component_types) do
    search(context, none: component_types)
  end

  @doc """
  Returns a list of entities that match the specified criteria.

  ## Options

    * `:all` - Matches entities that have all the specified components.
    * `:any` - Matches entities that have at least one of the specified components.
    * `:none` - Matches entities that do not have any of the specified components.
  """
  def search(context, opts) when is_list(opts) do
    all = Keyword.get(opts, :all)
    any = Keyword.get(opts, :any)
    none = Keyword.get(opts, :none)

    all_lookup = all && MapSet.new(all)
    any_lookup = any && MapSet.new(any)
    none_lookup = none && MapSet.new(none)

    context
    |> metadata()
    |> apply_filter(:all, all_lookup)
    |> apply_filter(:any, any_lookup)
    |> apply_filter(:none, none_lookup)
    |> Enum.map(fn {entity, _metadata} -> entity end)
  end

  @doc """
  Returns a stream of all metadata entries in the context.
  """
  def metadata(context) do
    mtable = table!(context, :metadata)

    # NOTE: normalize the output of the streams so it returns {key, value} tuples
    # This is useful for applying additional transformations like grouping keys.
    Genesis.ETS.stream(mtable, &Genesis.Utils.rekey/1)
  end

  @doc """
  Returns a stream of all component entries in the context.
  """
  def components(context) do
    ctable = table!(context, :components)

    # NOTE: normalize the output of the streams so it returns {key, value} tuples
    # This is useful for applying additional transformations like grouping keys.
    Genesis.ETS.stream(ctable, &Genesis.Utils.rekey/1)
  end

  @doc """
  Returns a stream of entities with their components grouped together.
  """
  def entities(context) do
    mtable = table!(context, :metadata)
    ctable = table!(context, :components)

    metadata_stream = Genesis.ETS.stream(mtable, &{mtable, &1})
    components_stream = Genesis.ETS.stream(ctable, &{ctable, &1})

    stream = Stream.concat(metadata_stream, components_stream)

    Stream.transform(stream, %{}, fn
      {^mtable, {entity, types, metadata}}, acc ->
        counters = {0, MapSet.size(types)}
        {[], Map.put(acc, entity, {types, metadata, [], counters})}

      {^ctable, {entity, _type, component}}, acc ->
        case Map.fetch!(acc, entity) do
          {types, metadata, components, {mapped, expected}}
          when mapped + 1 >= expected ->
            components = Enum.reverse([component | components])
            record = {entity, {types, metadata, components}}
            {[record], Map.delete(acc, entity)}

          {types, metadata, components, {mapped, expected}} ->
            counters = {mapped + 1, expected}
            components = [component | components]
            record = {types, metadata, components, counters}
            {[], Map.put(acc, entity, record)}
        end
    end)
  end

  @impl true
  def init(_args) do
    opts = [:protected, read_concurrency: true]
    mtable = :ets.new(:metadata, [:set | opts])
    ctable = :ets.new(:components, [:bag | opts])

    tables = %{mtable: mtable, ctable: ctable}
    Registry.register(Genesis.Registry, self(), tables)

    {:ok, %{tables: tables}}
  end

  @impl true
  def handle_call({:create, opts}, _from, state) do
    {metadata, opts} = Keyword.pop(opts, :metadata, %{})

    default_metadata = %{created_at: System.system_time()}
    updated_metadata = Map.merge(default_metadata, metadata)

    entity = Genesis.Entity.new(Keyword.put(opts, :context, self()))

    :ets.insert(state.tables.mtable, {entity, MapSet.new(), updated_metadata})

    {:reply, entity, state}
  end

  @impl true
  def handle_call({:emplace, entity, component}, _from, state) do
    type = Map.fetch!(component, :__struct__)

    case :ets.lookup(state.tables.mtable, entity) do
      [] ->
        {:reply, {:error, :entity_not_found}, state}

      [{^entity, types, metadata}] ->
        case :ets.match_object(state.tables.ctable, {entity, type, :_}) do
          [] ->
            :ets.insert(state.tables.ctable, {entity, type, component})

            updated_types = MapSet.put(types, type)
            :ets.insert(state.tables.mtable, {entity, updated_types, metadata})

            {:reply, :ok, state}

          [_component] ->
            {:reply, {:error, :already_inserted}, state}
        end
    end
  end

  @impl true
  def handle_call({:replace, entity, new_component}, _from, state) do
    type = Map.fetch!(new_component, :__struct__)

    case :ets.match_object(state.tables.ctable, {entity, type, :_}) do
      [] ->
        {:reply, {:error, :component_not_found}, state}

      [{^entity, ^type, old_component}] ->
        :ets.delete_object(state.tables.ctable, {entity, type, old_component})
        :ets.insert(state.tables.ctable, {entity, type, new_component})
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(state.tables.mtable)
    :ets.delete_all_objects(state.tables.ctable)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:patch, entity, new_metadata}, _from, state) do
    case :ets.lookup(state.tables.mtable, entity) do
      [] ->
        {:reply, {:error, :entity_not_found}, state}

      [{^entity, types, _metadata}] ->
        :ets.insert(state.tables.mtable, {entity, types, new_metadata})
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:erase, entity, nil}, _from, state) do
    case :ets.lookup(state.tables.mtable, entity) do
      [] ->
        {:reply, {:error, :entity_not_found}, state}

      [{^entity, _types, metadata}] ->
        :ets.delete(state.tables.ctable, entity)

        :ets.insert(state.tables.mtable, {entity, MapSet.new(), metadata})

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:erase, entity, component_type}, _from, state) do
    case :ets.lookup(state.tables.mtable, entity) do
      [] ->
        {:reply, {:error, :entity_not_found}, state}

      [{^entity, types, metadata}] ->
        matches = :ets.match_object(state.tables.ctable, {entity, component_type, :_})

        case matches do
          [] ->
            {:reply, {:error, :component_not_found}, state}

          [{^entity, ^component_type, component}] ->
            :ets.delete_object(state.tables.ctable, {entity, component_type, component})

            updated_types = MapSet.delete(types, component_type)
            :ets.insert(state.tables.mtable, {entity, updated_types, metadata})

            {:reply, :ok, state}
        end
    end
  end

  @impl true
  def handle_call({:assign, entity, components}, _from, state) do
    case :ets.lookup(state.tables.mtable, entity) do
      [] ->
        {:reply, {:error, :entity_not_found}, state}

      [{^entity, _types, metadata}] ->
        :ets.delete(state.tables.ctable, entity)
        component_types = emplace_many(state.tables.ctable, entity, components)
        :ets.insert(state.tables.mtable, {entity, MapSet.new(component_types), metadata})

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:destroy, entity}, _from, state) do
    case :ets.lookup(state.tables.mtable, entity) do
      [] ->
        {:reply, {:error, :entity_not_found}, state}

      [{^entity, _types, _metadata}] ->
        :ets.delete(state.tables.mtable, entity)
        :ets.delete(state.tables.ctable, entity)
        {:reply, :ok, state}
    end
  end

  defp apply_filter(stream, _filter, nil), do: stream

  defp apply_filter(stream, :all, lookup) do
    Stream.filter(stream, fn {_entity, {types, _metadata}} ->
      MapSet.subset?(lookup, types)
    end)
  end

  defp apply_filter(stream, :any, lookup) do
    Stream.filter(stream, fn {_entity, {types, _metadata}} ->
      not MapSet.disjoint?(lookup, types)
    end)
  end

  defp apply_filter(stream, :none, lookup) do
    Stream.filter(stream, fn {_entity, {types, _metadata}} ->
      MapSet.disjoint?(lookup, types)
    end)
  end

  defp emplace_many(components_table, entity, components) do
    Enum.map(components, fn component ->
      type = Map.fetch!(component, :__struct__)
      record = {entity, type, component}
      :ets.insert(components_table, record)
      type
    end)
  end

  defp table!(context, :metadata) do
    pid = resolve_context(context)

    case Registry.lookup(Genesis.Registry, pid) do
      [{^pid, %{mtable: mtable}}] -> mtable
      [] -> raise "Metadata table not found for context #{inspect(context)}"
    end
  end

  defp table!(context, :components) do
    pid = resolve_context(context)

    case Registry.lookup(Genesis.Registry, pid) do
      [{^pid, %{ctable: ctable}}] -> ctable
      [] -> raise "Components table not found for context #{inspect(context)}"
    end
  end

  defp resolve_context(context) when is_pid(context), do: context

  defp resolve_context(context) when is_atom(context) do
    case Process.whereis(context) do
      nil -> raise "Context #{inspect(context)} is not running"
      pid -> pid
    end
  end
end
