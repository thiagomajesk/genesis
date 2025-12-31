defmodule Genesis.Registry do
  @doc """
  Creates a new entity in the registry.
  Returns `{:ok, entity}` on success, or `{:error, reason}` on failure.

  Options:
    * `:name` - an optional name for the entity
    * `:metadata` - an optional map of metadata to associate with the entity
  """
  def create(registry, opts \\ []) when is_atom(registry) do
    case do_create(registry, opts) do
      {:ok, entity} ->
        {:ok, entity}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Retrieves information about an entity.
  Returns `{entity, name, metadata}` if found, or `nil`.
  """
  def info(registry, entity) when is_atom(registry) and is_reference(entity) do
    table = table!(registry, :metadata)

    # The information in the metadata table is not supposed to change often once
    # an entity is created so using dirty reads is acceptable to gain some performance.
    case :mnesia.dirty_read(table, entity) do
      [] ->
        nil

      [{_table, ^entity, name, metadata}] ->
        {entity, name, metadata}
    end
  end

  @doc """
  Looks up an entity by a registered name.
  Returns `{entity, name, metadata}` if found, or `nil`.
  """
  def lookup(registry, name) when is_atom(registry) do
    table = table!(registry, :metadata)

    # The information in the metadata table is not supposed to change often once
    # an entity is created so using dirty reads is acceptable to gain some performance.
    case :mnesia.dirty_index_read(table, name, :name) do
      [] ->
        nil

      [{_table, entity, ^name, metadata}] ->
        {entity, name, metadata}
    end
  end

  @doc """
  Fetches all components of an entity.
  Returns `{entity, components}` if found, or `nil`.
  """
  def fetch(registry, entity_or_name)

  def fetch(registry, name) when is_atom(registry) and is_binary(name) do
    with {entity, ^name, _metadata} <- lookup(registry, name), do: fetch(registry, entity)
  end

  def fetch(registry, entity) when is_atom(registry) and is_reference(entity) do
    case do_fetch(registry, entity) do
      nil ->
        nil

      {^entity, components} ->
        {entity, components}
    end
  end

  @doc """
  Associates a component to an entity, fails if the component type is already present.
  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  def emplace(registry, entity, component)
      when is_atom(registry) and is_reference(entity) and is_struct(component) do
    case do_emplace(registry, {entity, component}) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Replaces an existing component on an entity.
  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  def replace(registry, entity, component)
      when is_atom(registry) and is_reference(entity) and is_struct(component) do
    case do_replace(registry, {entity, component}) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Registers a name for an entity that doesn't have a name yet.
  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  def register(registry, entity, name) when is_atom(registry) and is_reference(entity) do
    case do_register(registry, entity, name) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Erases all components of an entity.
  When the `component_type` is provided, only that component is erased.
  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  def erase(registry, entity, component_type \\ nil)
      when is_atom(registry) and is_reference(entity) and is_atom(component_type) do
    case do_erase(registry, entity, component_type) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes all data from the registry tables.
  """
  def clear(registry) when is_atom(registry) do
    metadata_table = table!(registry, :metadata)
    components_table = table!(registry, :components)

    with :ok <- clear_table(metadata_table),
         :ok <- clear_table(components_table),
         do: :ok
  end

  @doc """
  Replaces the metadata of an entity.
  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  def patch(registry, entity, metadata)
      when is_atom(registry) and is_reference(entity) and is_map(metadata) do
    case do_patch(registry, entity, metadata) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Assigns components to an existing entity.
  Returns `{:ok, entity}` on success, or `{:error, reason}` on failure.
  """
  def assign(registry, entity, components)
      when is_atom(registry) and is_reference(entity) and is_list(components) do
    case do_assign(registry, entity, components) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Destroys an entity and removes all associated data.
  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  def destroy(registry, entity) when is_atom(registry) and is_reference(entity) do
    case do_destroy(registry, entity) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  def init(registry) when is_atom(registry) do
    with :ok <- ensure_metadata_table(registry),
         :ok <- ensure_components_table(registry),
         do: :ok
  end

  @doc """
  Executes a select query on a registry table.

  Takes registry atom, table type (`:metadata` or `:components`), and a match specification.
  """
  def select(registry, table_type, match_spec) when is_atom(registry) do
    table = table!(registry, table_type)
    transaction(fn -> :mnesia.select(table, match_spec) end)
  end

  @doc """
  Returns a stream of all metadata entries in the registry.

  Each entry is a tuple of `{entity, metadata}` where entity is a reference
  and metadata is the map of metadata associated with the entity.
  """
  def metadata(registry) when is_atom(registry) do
    registry
    |> table!(:metadata)
    |> stream_table(fn {_table, entity, name, metadata} ->
      {entity, {name, metadata}}
    end)
  end

  @doc """
  Returns a stream of all component entries in the registry.

  Each entry is a tuple of `{entity, component}` where entity is a reference
  and component is the component struct.
  """
  def components(registry) when is_atom(registry) do
    registry
    |> table!(:components)
    |> stream_table(fn {_table, entity, type, component} ->
      {entity, {type, component}}
    end)
  end

  @doc """
  Returns a stream of entities with their components grouped together.

  Each entry is a tuple of `{entity, components}` where entity is a reference
  and components is a list of component structs attached to that entity.
  """
  def entities(registry) when is_atom(registry) do
    metadata_table = table!(registry, :metadata)
    components_table = table!(registry, :components)

    metadata_stream = stream_table(metadata_table)
    components_stream = stream_table(components_table)

    stream = Stream.concat(metadata_stream, components_stream)

    Stream.transform(stream, %{}, fn
      {^metadata_table, entity, name, metadata}, acc ->
        counters = {0, MapSet.size(metadata.types)}
        {[], Map.put(acc, entity, {name, metadata, [], counters})}

      {^components_table, entity, _type, component}, acc ->
        case Map.fetch!(acc, entity) do
          {name, metadata, components, {mapped, expected}}
          when mapped + 1 >= expected ->
            components = Enum.reverse([component | components])
            record = {entity, {name, metadata, components}}
            {[record], Map.delete(acc, entity)}

          {name, metadata, components, {mapped, expected}} ->
            counters = {mapped + 1, expected}
            components = [component | components]
            record = {name, metadata, components, counters}
            {[], Map.put(acc, entity, record)}
        end
    end)
  end

  @doc """
  Utility function that allows grouping a registry stream of records by their key.
  Returns a stream of `{key, [values]}` tuples where key is usually the entity reference.
  """
  def group_by_key(stream) do
    Stream.transform(
      stream,
      fn -> %{} end,
      fn {k, v}, acc -> {[], Map.update(acc, k, [v], &[v | &1])} end,
      fn acc -> {Enum.map(acc, fn {k, vs} -> {k, Enum.reverse(vs)} end), nil} end,
      fn _ -> nil end
    )
  end

  defp table!(registry, :metadata), do: Module.concat(registry, Metadata)
  defp table!(registry, :components), do: Module.concat(registry, Components)
  defp table!(_registry, other_type), do: raise("Invalid table type: #{inspect(other_type)}")

  defp do_create(registry, opts) do
    table = table!(registry, :metadata)

    transaction(fn ->
      entity = make_ref()
      name = Keyword.get(opts, :name)
      custom_metadata = Keyword.get(opts, :metadata, %{})
      default_metadata = %{created_at: System.system_time()}
      metadata = Map.merge(default_metadata, custom_metadata)

      record = {table, entity, name, metadata}
      with :ok <- :mnesia.write(record), do: {:ok, entity}
    end)
  end

  defp do_emplace(registry, {entity, component}) do
    type = Map.fetch!(component, :__struct__)

    metadata_table = table!(registry, :metadata)
    components_table = table!(registry, :components)

    transaction(fn ->
      case :mnesia.read(metadata_table, entity) do
        [] ->
          {:error, :entity_not_found}

        [{_table, ^entity, name, metadata}] ->
          case :mnesia.index_match_object({components_table, entity, type, :_}, :type) do
            [] ->
              :mnesia.write({components_table, entity, type, component})

              types = Map.get(metadata, :types, MapSet.new())
              updated_types = MapSet.put(types, type)
              updated_metadata = Map.put(metadata, :types, updated_types)
              :mnesia.write({metadata_table, entity, name, updated_metadata})

            [{^components_table, ^entity, ^type, _component}] ->
              {:error, :already_inserted}
          end
      end
    end)
  end

  defp do_replace(registry, {entity, new_component}) do
    type = Map.fetch!(new_component, :__struct__)

    table = table!(registry, :components)

    transaction(fn ->
      case :mnesia.index_match_object({table, entity, type, :_}, :type) do
        [] ->
          {:error, :component_not_found}

        [{^table, ^entity, ^type, old_component}] ->
          :mnesia.delete_object({table, entity, type, old_component})
          :mnesia.write({table, entity, type, new_component})
      end
    end)
  end

  defp do_fetch(registry, entity) do
    metadata_table = table!(registry, :metadata)
    components_table = table!(registry, :components)

    transaction(fn ->
      case :mnesia.dirty_read(metadata_table, entity) do
        [] ->
          nil

        [{_table, ^entity, _name, _metadata}] ->
          match_spec = [{{:_, entity, :_, :"$1"}, [], [:"$1"]}]
          {entity, :mnesia.select(components_table, match_spec)}
      end
    end)
  end

  defp do_register(registry, entity, name) do
    table = table!(registry, :metadata)

    transaction(fn ->
      case :mnesia.read(table, entity) do
        [] ->
          {:error, :entity_not_found}

        [{_table, ^entity, nil, metadata}] ->
          :mnesia.write({table, entity, name, metadata})

        [{_table, ^entity, _name, _metadata}] ->
          {:error, :already_registered}
      end
    end)
  end

  defp do_erase(registry, entity, nil) do
    metadata_table = table!(registry, :metadata)
    components_table = table!(registry, :components)

    transaction(fn ->
      case :mnesia.read(metadata_table, entity) do
        [] ->
          {:error, :entity_not_found}

        [{_table, ^entity, name, metadata}] ->
          :mnesia.delete({components_table, entity})

          updated_metadata = Map.put(metadata, :types, MapSet.new())
          :mnesia.write({metadata_table, entity, name, updated_metadata})
      end
    end)
  end

  defp do_erase(registry, entity, component_type) do
    metadata_table = table!(registry, :metadata)
    components_table = table!(registry, :components)

    pattern = {components_table, entity, component_type, :_}

    transaction(fn ->
      case :mnesia.read(metadata_table, entity) do
        [] ->
          {:error, :entity_not_found}

        [{_table, ^entity, name, metadata}] ->
          case :mnesia.index_match_object(pattern, :type) do
            [] ->
              {:error, :component_not_found}

            [{table, ^entity, type, component}] ->
              :mnesia.delete_object({table, entity, type, component})

              types = Map.get(metadata, :types, MapSet.new())
              updated_types = MapSet.delete(types, type)
              updated_metadata = Map.put(metadata, :types, updated_types)
              :mnesia.write({metadata_table, entity, name, updated_metadata})
          end
      end
    end)
  end

  defp do_patch(registry, entity, new_metadata) do
    table = table!(registry, :metadata)

    transaction(fn ->
      case :mnesia.read(table, entity) do
        [] ->
          {:error, :entity_not_found}

        [{_table, ^entity, name, _metadata}] ->
          :mnesia.write({table, entity, name, new_metadata})
      end
    end)
  end

  defp do_destroy(registry, entity) do
    metadata_table = table!(registry, :metadata)
    components_table = table!(registry, :components)

    transaction(fn ->
      case :mnesia.read(metadata_table, entity) do
        [] ->
          {:error, :entity_not_found}

        [{_table, ^entity, _name, _metadata}] ->
          with :ok <- :mnesia.delete({metadata_table, entity}),
               :ok <- :mnesia.delete({components_table, entity}),
               do: :ok
      end
    end)
  end

  defp ensure_metadata_table(registry) do
    table = table!(registry, :metadata)
    options = [type: :set, attributes: [:entity, :name, :metadata]]

    with :ok <- ensure_table(table, options),
         :ok <- ensure_index(table, :name),
         do: :ok
  end

  defp ensure_components_table(registry) do
    table = table!(registry, :components)
    options = [type: :bag, attributes: [:entity, :type, :component]]

    with :ok <- ensure_table(table, options),
         :ok <- ensure_index(table, :type),
         do: :ok
  end

  defp ensure_table(table, opts) do
    case :mnesia.create_table(table, opts) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, _table}} -> :ok
      other -> raise "unexpected result: #{inspect(other)}"
    end
  end

  defp ensure_index(table, field) do
    case :mnesia.add_table_index(table, field) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, _table, _position}} -> :ok
      other -> raise "unexpected result: #{inspect(other)}"
    end
  end

  defp clear_table(table) do
    case :mnesia.clear_table(table) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> raise "mnesia clear_table aborted: #{inspect(reason)}"
      other -> raise "unexpected result: #{inspect(other)}"
    end
  end

  defp transaction(fun) do
    case :mnesia.transaction(fun) do
      {:atomic, value} ->
        value

      {:aborted, reason} ->
        raise "mnesia transaction aborted: #{inspect(reason)}"
    end
  end

  defp stream_table(table, transform \\ & &1) do
    start_fun = fn -> :mnesia.dirty_first(table) end

    next_fun = fn
      :"$end_of_table" ->
        {:halt, []}

      entity ->
        case :mnesia.dirty_read(table, entity) do
          [] ->
            {[], :mnesia.dirty_next(table, entity)}

          records ->
            entries = Enum.map(records, &transform.(&1))
            {entries, :mnesia.dirty_next(table, entity)}
        end
    end

    after_fun = fn _ -> :ok end

    Stream.resource(start_fun, next_fun, after_fun)
  end

  defp do_assign(registry, entity, components) do
    metadata_table = table!(registry, :metadata)
    components_table = table!(registry, :components)

    transaction(fn ->
      case :mnesia.read(metadata_table, entity) do
        [] ->
          {:error, :entity_not_found}

        [{_table, ^entity, name, metadata}] ->
          :mnesia.delete({components_table, entity})
          component_types = emplace_many(components_table, entity, components)
          updated_metadata = Map.put(metadata, :types, MapSet.new(component_types))
          :mnesia.write({metadata_table, entity, name, updated_metadata})
      end
    end)
  end

  defp emplace_many(components_table, entity, components) do
    Enum.map(components, fn component ->
      type = Map.fetch!(component, :__struct__)
      record = {components_table, entity, type, component}
      with :ok <- :mnesia.write(record), do: type
    end)
  end
end
