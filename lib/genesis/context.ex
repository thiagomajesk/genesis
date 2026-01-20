# Before changing this file, see the Erlang/OTP section on tables and databases
# for best practices and optimizations tricks: https://www.erlang.org/doc/system/tablesdatabases.
defmodule Genesis.Context do
  @moduledoc """
  Provides low-level entity storage backed by ETS.

  A context contains the following ETS tables that are always kept in sync.

    * `mtable` - table that stores metadata associated with entities
    * `ctable` - table that stores components associated with entities
    * `nindex` - table that stores metadata indexed by name
    * `tindex` - table that stores components indexed by type

  Note that most read operations are intentionally dirty reads for performance reasons.
  """

  use GenServer

  import Genesis.Utils, only: [is_non_empty_pairs: 1, is_min_max: 2]

  @doc """
  Starts a new `Genesis.Context`.
  Same as `GenServer.start_link/3`.
  """
  @doc group: "Process API"
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, args)
  end

  @doc """
  Returns a specification to start a context under a supervisor.

  See `Supervisor`.
  """
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
    * `:name` - registers the entity under the given name (optional)
    * `:metadata` - associates metadata to the entity (optional)

  See `Genesis.Entity.new/1` for additional options.
  Note that the created entity has its context set automatically.

  ## Examples

      # Create an entity
      Genesis.Context.create(context)
      #=> {:ok, entity}

      # Create a named entity with metadata
      Genesis.Context.create(context,
        name: "Shopkeeper",
        metadata: %{faction: :alliance}
      )
  """
  def create(context, opts \\ []) do
    GenServer.call(context, {:create, opts})
  end

  @doc """
  Retrieves information about an entity.
  Returns `{entity, types, metadata}` if found, or `nil`.

  ## Examples

      Genesis.Context.info(context, entity)
      #=> {entity, [], %{}}
  """
  @doc group: "Query API"
  def info(context, %Genesis.Entity{} = entity) do
    mtable = table!(context, :mtable)

    case :ets.lookup(mtable, entity.hash) do
      [] ->
        nil

      [{_key, _entity, types, metadata}] ->
        {entity, types, metadata}
    end
  end

  @doc """
  Associates a component to an entity, fails if the component type is already present.
  Returns `:ok` on success, or `{:error, reason}` on failure.

  ## Examples

      {:ok, entity} = Genesis.Context.create(context)

      Genesis.Context.emplace(context, entity, %Position{x: 10, y: 20})
  """
  def emplace(context, %Genesis.Entity{} = entity, component) when is_struct(component) do
    GenServer.call(context, {:emplace, entity, component})
  end

  @doc """
  Replaces an existing component on an entity.
  Returns `:ok` on success, or `{:error, reason}` on failure.

  ## Examples

      {:ok, entity} = Genesis.Context.create(context)
      Genesis.Context.emplace(context, entity, %Position{x: 0, y: 0})

      # Replaces the position component entirely
      Genesis.Context.replace(context, entity, %Position{x: 10, y: 20})
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

  ## Examples

      metadata = %{created_at: System.system_time()}
      Genesis.Context.patch(context, entity, metadata)
  """
  def patch(context, %Genesis.Entity{} = entity, metadata) when is_map(metadata) do
    GenServer.call(context, {:patch, entity, metadata})
  end

  @doc """
  Removes components from an entity.
  When the `component_type` is provided, only that component is removed.
  Returns `:ok` on success, or `{:error, reason}` on failure.

  ## Examples

      # Removes a specific component from the entity
      Genesis.Context.erase(context, entity, Health)

      # Removes all components from the entity
      Genesis.Context.erase(context, entity)
  """
  def erase(context, %Genesis.Entity{} = entity, component_type \\ nil)
      when is_atom(component_type) do
    GenServer.call(context, {:erase, entity, component_type})
  end

  @doc """
  Assigns components to an existing entity.
  Components of the same type will be replaced.
  Returns `:ok` on success, or `{:error, reason}` on failure.

  ## Examples

      {:ok, entity} = Genesis.Context.create(context)

      components = [%Health{current: 100, maximum: 100}]
      Genesis.Context.assign(context, entity, components)
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

  ## Examples

      {:ok, npc} = Genesis.Context.create(context, name: "Shopkeeper")
      Genesis.Context.emplace(context, npc, %Health{current: 100})

      Genesis.Context.lookup(context, "Shopkeeper")
      #=> {entity, [Health], %{created_at: 1234567890}}
  """
  @doc group: "Query API"
  def lookup(context, name) when is_binary(name) do
    mtable = table!(context, :mtable)
    nindex = table!(context, :nindex)

    with [{_name, hash}] <- :ets.lookup(nindex, name),
         [{_key, entity, types, metadata}] <- :ets.lookup(mtable, hash),
         do: {entity, types, metadata},
         else: (_ -> nil)
  end

  @doc """
  Checks if an entity or name exists in the context.
  Returns `true` if found, or `false` otherwise.

  ## Examples

      # Using an entity
      Genesis.Context.exists?(context, entity)

      # Using a name
      Genesis.Context.exists?(context, "Player")
  """
  @doc group: "Query API"
  def exists?(context, entity_or_name)

  def exists?(context, %Genesis.Entity{} = entity) do
    :ets.member(table!(context, :mtable), entity.hash)
  end

  def exists?(context, name) when is_binary(name) do
    :ets.member(table!(context, :nindex), name)
  end

  @doc """
  Fetches all components of an entity.
  Returns `{entity, components}` if found, or `nil`.

  ## Examples

      # Fetch by entity
      Genesis.Context.fetch(context, entity)
      #=> {entity, [%Health{current: 100}, %Position{x: 10, y: 20}]}

      # Fetch by name
      Genesis.Context.fetch(context, "Enemy")
      #=> {#Entity<9876543>, [%Health{current: 50}, %Position{x: 5, y: 15}]}
  """
  @doc group: "Query API"
  def fetch(context, entity_or_name)

  def fetch(context, name) when is_binary(name) do
    with {entity, _types, _metadata} <- lookup(context, name), do: fetch(context, entity)
  end

  def fetch(context, %Genesis.Entity{} = entity) do
    mtable = table!(context, :mtable)
    ctable = table!(context, :ctable)

    case :ets.lookup(mtable, entity.hash) do
      [] ->
        nil

      [{_key, _entity, _types, _metadata}] ->
        match_spec = [{{entity.hash, :_, :_, :"$1"}, [], [:"$1"]}]
        {entity, :ets.select(ctable, match_spec)}
    end
  end

  @doc """
  Returns all entities with components of the given type.
  Returns a list of tuples containing the entity and the component struct.

  ## Examples

      iex> Genesis.Context.all(context, Health)
      #=> [{entity_1, %Health{current: 100}}, {entity_2, %Health{current: 50}}]
  """
  @doc group: "Query API"
  def all(context, component_type) when is_atom(component_type) do
    tindex = table!(context, :tindex)

    :ets.select(tindex, [
      {
        {component_type, :_, :"$1", :"$2"},
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
      #=> %Health{current: 100}
  """
  @doc group: "Query API"
  def get(context, %Genesis.Entity{} = entity, component_type, default \\ nil)
      when is_atom(component_type) do
    ctable = table!(context, :ctable)

    match_spec = [
      {
        {entity.hash, :_, component_type, :"$1"},
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
      #=> [{entity_1, %Moniker{name: "Tripida"}}]
  """
  @doc group: "Query API"
  def match(context, component_type, properties)
      when is_atom(component_type) and is_non_empty_pairs(properties) do
    tindex = table!(context, :tindex)

    guards =
      Enum.map(properties, fn {property, value} ->
        {:==, {:map_get, property, :"$2"}, value}
      end)

    :ets.select(tindex, [
      {
        {component_type, :_, :"$1", :"$2"},
        [{:is_map, :"$2"} | guards],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  @doc """
  Returns all entities that have the given property with a value greater than or equal to the given minimum.

  ## Examples

      iex> Genesis.Context.at_least(context, Health, :current, 50)
      #=> [{entity_1, %Health{current: 75}}]
  """
  @doc group: "Query API"
  def at_least(context, component_type, property, value)
      when is_atom(component_type) and is_atom(property) do
    tindex = table!(context, :tindex)

    :ets.select(tindex, [
      {
        {component_type, :_, :"$1", :"$2"},
        [{:is_map, :"$2"}, {:>=, {:map_get, property, :"$2"}, value}],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  @doc """
  Returns all entities that have the given property with a value less than or equal to the given maximum.

  ## Examples

      iex> Genesis.Context.at_most(context, Health, :current, 50)
      #=> [{entity_1, %Health{current: 25}}]
  """
  @doc group: "Query API"
  def at_most(context, component_type, property, value)
      when is_atom(component_type) and is_atom(property) do
    tindex = table!(context, :tindex)

    :ets.select(tindex, [
      {
        {component_type, :_, :"$1", :"$2"},
        [{:is_map, :"$2"}, {:"=<", {:map_get, property, :"$2"}, value}],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  @doc """
  Returns all entities that have the given property with a value between the given minimum and maximum (inclusive).

  ## Examples

      iex> Genesis.Context.between(context, Health, :current, 50, 100)
      #=> [{entity_1, %Health{current: 75}}]
  """
  @doc group: "Query API"
  def between(context, component_type, property, min, max)
      when is_atom(component_type) and is_atom(property) and is_min_max(min, max) do
    tindex = table!(context, :tindex)

    :ets.select(tindex, [
      {
        {component_type, :_, :"$1", :"$2"},
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
      #=> [entity_2, entity_3, entity_4, ...]
  """
  @doc group: "Query API"
  def children_of(context, %Genesis.Entity{} = entity) do
    mtable = table!(context, :mtable)

    :ets.select(mtable, [
      {
        {:_, :"$1", :_, :_},
        [{:==, {:map_get, :hash, {:map_get, :parent, :"$1"}}, entity.hash}],
        [:"$1"]
      }
    ])
  end

  @doc """
  Returns a list of entities that have all the components specified in the list.

  ## Examples

      iex> Genesis.Context.all_of(context, [Health, Velocity])
      #=> [entity_1, entity_2]
  """
  @doc group: "Query API"
  def all_of(context, component_types) when is_list(component_types) do
    search(context, all: component_types)
  end

  @doc """
  Returns a list of entities that have at least one of the components specified in the list.

  ## Examples

      iex> Genesis.Context.any_of(context, [Health, Velocity])
      #=> [entity_1, entity_2, entity_3]
  """
  @doc group: "Query API"
  def any_of(context, component_types) when is_list(component_types) do
    search(context, any: component_types)
  end

  @doc """
  Returns a list of entities that do not have any of the components specified in the list.

  ## Examples

      iex> Genesis.Context.none_of(context, [Health, Velocity])
      #=> [entity_1, entity_2]
  """
  @doc group: "Query API"
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
  @doc group: "Query API"
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
  Note that this function will cause the entire table to be iterated.
  """
  @doc group: "Introspection API"
  def metadata(context) do
    mtable = table!(context, :mtable)

    # NOTE: normalize the output of the streams so it returns {key, value} tuples
    # This is useful for applying additional transformations like grouping keys.
    Genesis.ETS.stream(mtable, fn {_key, entity, types, metadata} ->
      {entity, {types, metadata}}
    end)
  end

  @doc """
  Returns a stream of all component entries in the context.
  Note that this function will cause the entire table to be iterated.
  """
  @doc group: "Introspection API"
  def components(context) do
    ctable = table!(context, :ctable)

    # NOTE: normalize the output of the streams so it returns {key, value} tuples
    # This is useful for applying additional transformations like grouping keys.
    Genesis.ETS.stream(ctable, fn {_key, entity, type, component} ->
      {entity, {type, component}}
    end)
  end

  @doc """
  Returns a stream of entities with their components grouped together.
  Note that this function will cause the entire table to be iterated.
  """
  @doc group: "Introspection API"
  def entities(context) do
    mtable = table!(context, :mtable)
    ctable = table!(context, :ctable)

    metadata_stream = Genesis.ETS.stream(mtable, &{mtable, &1})
    components_stream = Genesis.ETS.stream(ctable, &{ctable, &1})

    stream = Stream.concat(metadata_stream, components_stream)

    Stream.transform(stream, %{}, fn
      {^mtable, {_key, entity, types, metadata}}, acc ->
        counters = {0, MapSet.size(types)}
        {[], Map.put(acc, entity, {types, metadata, [], counters})}

      {^ctable, {_key, entity, _type, component}}, acc ->
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
    mtable = :ets.new(:mtable, [:set | opts])
    ctable = :ets.new(:ctable, [:bag | opts])
    tindex = :ets.new(:tindex, [:bag | opts])
    nindex = :ets.new(:nindex, [:set | opts])

    tables = %{
      mtable: mtable,
      ctable: ctable,
      tindex: tindex,
      nindex: nindex
    }

    Registry.register(Genesis.Registry, self(), tables)

    {:ok, %{tables: tables}}
  end

  @impl true
  def handle_call({:create, opts}, _from, state) do
    {metadata, opts} = Keyword.pop(opts, :metadata, %{})

    name = Keyword.get(opts, :name)
    default_metadata = %{created_at: System.system_time()}
    updated_metadata = Map.merge(default_metadata, metadata)

    opts = Keyword.put(opts, :context, self())

    cond do
      not is_nil(name) and :ets.member(state.tables.nindex, name) ->
        {:reply, {:error, :name_already_registered}, state}

      true ->
        entity = Genesis.Entity.new(opts)
        ets_create(state.tables, entity, updated_metadata)

        {:reply, {:ok, entity}, state}
    end
  end

  @impl true
  def handle_call({:emplace, entity, component}, _from, state) do
    type = Map.fetch!(component, :__struct__)

    case :ets.lookup(state.tables.mtable, entity.hash) do
      [] ->
        {:reply, {:error, :entity_not_found}, state}

      [mrecord] ->
        case :ets.match_object(state.tables.ctable, {entity.hash, :_, type, :_}) do
          [] ->
            ets_emplace(state.tables, mrecord, component)
            {:reply, :ok, state}

          [_component] ->
            {:reply, {:error, :already_inserted}, state}
        end
    end
  end

  @impl true
  def handle_call({:replace, entity, new_component}, _from, state) do
    type = Map.fetch!(new_component, :__struct__)

    case :ets.match_object(state.tables.ctable, {entity.hash, :_, type, :_}) do
      [] ->
        {:reply, {:error, :component_not_found}, state}

      [mrecord] ->
        ets_replace(state.tables, mrecord, type, new_component)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(state.tables.mtable)
    :ets.delete_all_objects(state.tables.ctable)
    :ets.delete_all_objects(state.tables.tindex)
    :ets.delete_all_objects(state.tables.nindex)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:patch, entity, metadata}, _from, state) do
    case :ets.lookup(state.tables.mtable, entity.hash) do
      [] ->
        {:reply, {:error, :entity_not_found}, state}

      [mrecord] ->
        ets_patch(state.tables, mrecord, metadata)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:erase, entity, nil}, _from, state) do
    case :ets.lookup(state.tables.mtable, entity.hash) do
      [] ->
        {:reply, {:error, :entity_not_found}, state}

      [mrecord] ->
        ets_erase_all(state.tables, mrecord)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:erase, entity, component_type}, _from, state) do
    case :ets.lookup(state.tables.mtable, entity.hash) do
      [] ->
        {:reply, {:error, :entity_not_found}, state}

      [mrecord] ->
        case :ets.match_object(state.tables.ctable, {entity.hash, :_, component_type, :_}) do
          [] ->
            {:reply, {:error, :component_not_found}, state}

          [{_key, _entity, _component_type, component}] ->
            ets_erase(state.tables, mrecord, component_type, component)

            {:reply, :ok, state}
        end
    end
  end

  @impl true
  def handle_call({:assign, entity, components}, _from, state) do
    case :ets.lookup(state.tables.mtable, entity.hash) do
      [] ->
        {:reply, {:error, :entity_not_found}, state}

      [mrecord] ->
        ets_assign(state.tables, mrecord, components)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:destroy, entity}, _from, state) do
    case :ets.lookup(state.tables.mtable, entity.hash) do
      [] ->
        {:reply, {:error, :entity_not_found}, state}

      [mrecord] ->
        ets_destroy(state.tables, mrecord)
        {:reply, :ok, state}
    end
  end

  defp ets_create(%{mtable: mtable, nindex: nindex}, entity, metadata) do
    :ets.insert(mtable, {entity.hash, entity, MapSet.new(), metadata})
    if entity.name, do: :ets.insert(nindex, {entity.name, entity.hash})
  end

  defp ets_emplace(%{ctable: ctable, mtable: mtable, tindex: tindex}, mrecord, component) do
    type = Map.fetch!(component, :__struct__)

    {hash, entity, types, metadata} = mrecord
    :ets.insert(ctable, {hash, entity, type, component})
    :ets.insert(tindex, {type, hash, entity, component})
    :ets.insert(mtable, {hash, entity, MapSet.put(types, type), metadata})
  end

  defp ets_replace(%{ctable: ctable, tindex: tindex}, mrecord, type, new_component) do
    {hash, entity, _types, _metadata} = mrecord
    :ets.match_delete(ctable, {hash, :_, type, :_})
    :ets.match_delete(tindex, {type, hash, :_, :_})
    :ets.insert(ctable, {hash, entity, type, new_component})
    :ets.insert(tindex, {type, hash, entity, new_component})
  end

  defp ets_erase(%{ctable: ctable, mtable: mtable, tindex: tindex}, mrecord, type, component) do
    {hash, entity, types, metadata} = mrecord
    :ets.delete_object(ctable, {hash, entity, type, component})
    :ets.delete_object(tindex, {type, hash, entity, component})
    :ets.insert(mtable, {hash, entity, MapSet.delete(types, type), metadata})
  end

  defp ets_erase_all(%{ctable: ctable, mtable: mtable, tindex: tindex}, mrecord) do
    {hash, entity, _types, metadata} = mrecord

    :ets.delete(ctable, hash)
    :ets.match_delete(tindex, {:_, hash, :_, :_})
    :ets.insert(mtable, {hash, entity, MapSet.new(), metadata})
  end

  defp ets_assign(%{ctable: ctable, mtable: mtable, tindex: tindex}, mrecord, components) do
    {hash, entity, _types, metadata} = mrecord

    :ets.delete(ctable, hash)
    :ets.match_delete(tindex, {:_, hash, :_, :_})

    {crecords, trecords, component_types} =
      Enum.reduce(components, {[], [], []}, fn component, {crecords, trecords, types} ->
        type = Map.fetch!(component, :__struct__)
        crecord = {hash, entity, type, component}
        trecord = {type, hash, entity, component}
        {[crecord | crecords], [trecord | trecords], [type | types]}
      end)

    :ets.insert(ctable, Enum.reverse(crecords))
    :ets.insert(tindex, Enum.reverse(trecords))

    # NOTE: update the whole object because benchmarks are showing that this is still
    # fater than calling something like update_element/3 to update only component_types.
    :ets.insert(mtable, {hash, entity, MapSet.new(component_types), metadata})
  end

  defp ets_patch(%{mtable: mtable}, mrecord, metadata) do
    {hash, entity, types, _metadata} = mrecord
    :ets.insert(mtable, {hash, entity, types, metadata})
  end

  defp ets_destroy(%{mtable: mtable, ctable: ctable, tindex: tindex, nindex: nindex}, mrecord) do
    {hash, entity, _types, _metadata} = mrecord
    :ets.delete(mtable, hash)
    :ets.delete(ctable, hash)
    :ets.match_delete(tindex, {:_, hash, :_, :_})
    :ets.match_delete(nindex, {entity.name, hash})
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

  defp table!(context, name) do
    pid = resolve_context(context)

    case Registry.lookup(Genesis.Registry, pid) do
      [{^pid, %{^name => table}}] -> table
      [] -> raise "table #{name} not found for context #{inspect(context)}"
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
