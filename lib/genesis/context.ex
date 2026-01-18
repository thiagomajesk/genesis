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
    * `aindex` - table that stores archetype bloom bits

  ## Archetypes

  The archetype index (`aindex`) is table that uses a bloom filter as the key
  that allows fast searches of entities based on their component composition.

  Even though the `aindex` table has roughly the same number of entries as `mtable`,
  it's implemented as a `:bag`, meaning we don't have to to scan the entire table
  to find entities matching a given archetype. This allows for efficient querying of
  entities that share the same archetype (`all_of` queries).

  NOTE: most read operations are intentionally dirty reads for performance reasons.
  """

  # Defines how many elements we want to support in the bloom filter with a low false positive rate.
  # Although this value could be calculated dynamically, I chose to have a standard for the 1% of false positives.
  # This number can be read as: "How many components can we have in the bloom filter before the false positive rate exceeds 1%?".
  # The current value of 100 components will yield a bitmask of around 962 bits (121 bytes), which is fairly reasonable.
  @bloom_limit 100

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
  """
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
  """
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
      [{entity_1, %Health{current: 100}}, {entity_2, %Health{current: 50}}]
  """
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
      %Health{current: 100}
  """
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
      [{entity_1, %Moniker{name: "Tripida"}}]
  """
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
      [{entity_1, %Health{current: 75}}]
  """
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
      [{entity_1, %Health{current: 25}}]
  """
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
      [{entity_1, %Health{current: 75}}]
  """
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
      [entity_2, entity_3, entity_4, ...]
  """
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

    # Masks specific for the bloom filter
    all_masks = build_bloom_filter(List.wrap(all))
    all_filter = Genesis.Bloom.merge_masks(all_masks)

    any_masks = build_bloom_filter(List.wrap(any))
    any_filter = Genesis.Bloom.merge_masks(any_masks)

    none_masks = build_bloom_filter(List.wrap(none))
    none_filter = Genesis.Bloom.merge_masks(none_masks)

    all_guard =
      if all_filter != 0,
        do: [{:==, {:band, :"$1", all_filter}, all_filter}],
        else: []

    any_guard =
      if any_filter != 0,
        do: [{:"/=", {:band, :"$1", any_filter}, 0}],
        else: []

    none_guard =
      if none_filter != 0,
        do: [{:==, {:band, :"$1", none_filter}, 0}],
        else: []

    guards = Enum.concat([all_guard, any_guard, none_guard])

    match_spec = [{{:"$1", :"$2"}, guards, [:"$2"]}]

    aindex = table!(context, :aindex)
    mtable = table!(context, :mtable)

    hashes = :ets.select(aindex, match_spec)
    stream = Genesis.ETS.stream_lookup(mtable, hashes)

    # Lookups for the false-positive checks
    all_lookup = all && MapSet.new(all)
    any_lookup = any && MapSet.new(any)

    # Since we are using a bloom filter, we need to verify the results to filter out false positives.
    # We don't need to check for false negatives since bloom filters guarantee no false negatives.
    verified =
      Stream.filter(stream, fn {_hash, _entity, types, _metadata} ->
        (all_lookup == nil or MapSet.subset?(all_lookup, types)) and
          (any_lookup == nil or not MapSet.disjoint?(any_lookup, types))
      end)

    Enum.map(verified, fn {_hash, entity, _types, _metadata} -> entity end)
  end

  @doc """
  Returns a stream of all metadata entries in the context.
  """
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
  """
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
  """
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
    aindex = :ets.new(:aindex, [:bag | opts])

    tables = %{
      mtable: mtable,
      ctable: ctable,
      tindex: tindex,
      nindex: nindex,
      aindex: aindex
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
    :ets.delete_all_objects(state.tables.aindex)
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

  defp ets_create(tables, entity, metadata) do
    :ets.insert(tables.aindex, {0, entity.hash})
    :ets.insert(tables.mtable, {entity.hash, entity, MapSet.new(), metadata})
    if entity.name, do: :ets.insert(tables.nindex, {entity.name, entity.hash})
  end

  defp ets_emplace(tables, mrecord, component) do
    type = Map.fetch!(component, :__struct__)

    {hash, entity, types, metadata} = mrecord

    update_archetypes(tables.aindex, hash, type)

    :ets.insert(tables.ctable, {hash, entity, type, component})
    :ets.insert(tables.tindex, {type, hash, entity, component})
    :ets.insert(tables.mtable, {hash, entity, MapSet.put(types, type), metadata})
  end

  defp ets_replace(tables, mrecord, type, new_component) do
    {hash, entity, _types, _metadata} = mrecord

    update_archetypes(tables.aindex, hash, type)

    :ets.match_delete(tables.ctable, {hash, :_, type, :_})
    :ets.match_delete(tables.tindex, {type, hash, :_, :_})
    :ets.insert(tables.ctable, {hash, entity, type, new_component})
    :ets.insert(tables.tindex, {type, hash, entity, new_component})
  end

  defp ets_erase(tables, mrecord, type, component) do
    {hash, entity, types, metadata} = mrecord

    updated_types = MapSet.delete(types, type)

    rebuild_archetypes(tables.aindex, hash, updated_types)

    :ets.delete_object(tables.ctable, {hash, entity, type, component})
    :ets.delete_object(tables.tindex, {type, hash, entity, component})
    :ets.insert(tables.mtable, {hash, entity, updated_types, metadata})
  end

  defp ets_erase_all(tables, mrecord) do
    {hash, entity, _types, metadata} = mrecord

    :ets.delete(tables.ctable, hash)
    :ets.match_delete(tables.aindex, {:_, hash})
    :ets.match_delete(tables.tindex, {:_, hash, :_, :_})
    :ets.insert(tables.mtable, {hash, entity, MapSet.new(), metadata})
  end

  defp ets_assign(tables, mrecord, components) do
    {hash, entity, _types, metadata} = mrecord

    :ets.delete(tables.ctable, hash)
    :ets.match_delete(tables.tindex, {:_, hash, :_, :_})

    # Create records for batch insertion
    {crecords, trecords, component_types} =
      Enum.reduce(components, {[], [], []}, fn component, {crecords, trecords, types} ->
        type = Map.fetch!(component, :__struct__)
        crecord = {hash, entity, type, component}
        trecord = {type, hash, entity, component}

        updated_types = [type | types]
        updated_crecords = [crecord | crecords]
        updated_trecords = [trecord | trecords]

        {updated_crecords, updated_trecords, updated_types}
      end)

    :ets.insert(tables.ctable, Enum.reverse(crecords))
    :ets.insert(tables.tindex, Enum.reverse(trecords))

    updated_types = MapSet.new(component_types)

    rebuild_archetypes(tables.aindex, hash, updated_types)

    # NOTE: update the whole object because benchmarks are showing that this is still
    # fater than calling something like update_element/3 to update only component_types.
    :ets.insert(tables.mtable, {hash, entity, updated_types, metadata})
  end

  defp ets_patch(tables, mrecord, metadata) do
    {hash, entity, types, _metadata} = mrecord

    :ets.insert(tables.mtable, {hash, entity, types, metadata})
  end

  defp ets_destroy(tables, mrecord) do
    {hash, entity, _types, _metadata} = mrecord

    :ets.delete(tables.mtable, hash)
    :ets.delete(tables.ctable, hash)
    :ets.match_delete(tables.aindex, {:_, hash})
    :ets.match_delete(tables.tindex, {:_, hash, :_, :_})
    :ets.match_delete(tables.nindex, {entity.name, hash})
  end

  defp rebuild_archetypes(aindex, hash, types) do
    masks = build_bloom_filter(types)
    updated_mask = Genesis.Bloom.merge_masks(masks)
    :ets.insert(aindex, {updated_mask, hash})
  end

  defp update_archetypes(aindex, hash, type) do
    # If we are keeping things in sync, there should be
    # only one entry per entity in the archetype index.
    [[current_mask]] = :ets.match(aindex, {:"$1", hash})

    [mask] = build_bloom_filter([type])
    updated_mask = Genesis.Bloom.merge_masks(current_mask, mask)

    :ets.match_delete(aindex, {:_, hash})
    :ets.insert(aindex, {updated_mask, hash})
  end

  defp build_bloom_filter(types) do
    mask_size = Genesis.Bloom.bloom_bits(@bloom_limit)

    Enum.map(types, fn type ->
      name = type.__component__(:name)
      events = type.__component__(:events)
      Genesis.Bloom.bloom_mask({name, events}, mask_size)
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
