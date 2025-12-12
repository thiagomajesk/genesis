defmodule Genesis.Registry do
  use GenServer

  def start_link(opts) do
    name = Access.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, name, name: name)
  end

  @doc """
  Creates a new entity in the registry.

  Options:
    * `:name` - an optional name for the entity
    * `:metadata` - an optional map of metadata to associate with the entity
  """
  def create(registry, opts \\ []) do
    GenServer.call(registry, {:create, opts})
  end

  @doc """
  Retrieves information about an entity.
  Returns `{entity, name, metadata}` if found, or `nil` if not found
  """
  def info(registry, entity) when is_reference(entity) do
    GenServer.call(registry, {:info, entity})
  end

  @doc """
  Looks up an entity by a registered name.
  Returns `{entity, name, metadata}` if found, or `nil` if not found.
  """
  def lookup(registry, name) when is_binary(name) do
    GenServer.call(registry, {:lookup, name})
  end

  @doc """
  Fetches all components of an entity.
  Returns `{entity, components}` if found, or `nil` if not found.
  """
  def fetch(registry, entity) when is_reference(entity) do
    GenServer.call(registry, {:fetch, entity})
  end

  @doc """
  Associates a component to an entity, fails if the component type is already present.
  """
  def emplace(registry, entity, component) when is_reference(entity) and is_struct(component) do
    GenServer.call(registry, {:emplace, entity, component})
  end

  @doc """
  Replaces an existing component on an entity. Fails if the component type is not present.
  """
  def replace(registry, entity, component) when is_reference(entity) and is_struct(component) do
    GenServer.call(registry, {:replace, entity, component})
  end

  @doc """
  Registers a name for an entity that doesn't have a name yet.
  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  def register(registry, entity, name) when is_reference(entity) and is_binary(name) do
    GenServer.call(registry, {:register, entity, name})
  end

  @doc """
  Erases all components of an entity.
  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  def erase(registry, entity, component_type)
      when is_reference(entity) and is_atom(component_type) do
    GenServer.call(registry, {:erase, entity, component_type})
  end

  @doc """
  Removes all components associated with an entity.
  """
  def clear(registry, entity) when is_reference(entity) do
    GenServer.call(registry, {:clear, entity})
  end

  @doc """
  Replaces the metadata of an entity.
  """
  def patch(registry, entity, metadata) when is_reference(entity) and is_map(metadata) do
    GenServer.call(registry, {:patch, entity, metadata})
  end

  @doc """
  Destroys an entity and removes all associated data.
  """
  def destroy(registry, entity) when is_reference(entity) do
    GenServer.call(registry, {:destroy, entity})
  end

  @impl true
  def init(name) do
    metadata_table = Module.concat(name, Metadata)
    components_table = Module.concat(name, Components)

    :ok = ensure_metadata_table(metadata_table)
    :ok = ensure_components_table(components_table)

    {:ok,
     %{
       metadata_table: metadata_table,
       components_table: components_table
     }}
  end

  @impl true
  def handle_call({:create, opts}, _from, state) do
    case do_create(state, opts) do
      {:ok, entity} ->
        {:reply, {:ok, entity}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:info, entity}, _from, state) do
    # The information in the metadata table is not supposed to change often once
    # an entity is created so using dirty reads is acceptable to gain some performance.
    case :mnesia.dirty_read(state.metadata_table, entity) do
      [] ->
        {:reply, nil, state}

      [{_table, ^entity, name, metadata}] ->
        {:reply, {entity, name, metadata}, state}
    end
  end

  @impl true
  def handle_call({:lookup, name}, _from, state) do
    # The information in the metadata table is not supposed to change often once
    # an entity is created so using dirty reads is acceptable to gain some performance.
    case :mnesia.dirty_index_read(state.metadata_table, name, :name) do
      [] ->
        {:reply, nil, state}

      [{_table, entity, ^name, metadata}] ->
        {:reply, {entity, name, metadata}, state}
    end
  end

  @impl true
  def handle_call({:fetch, entity}, _from, state) do
    case do_fetch(state, entity) do
      nil ->
        {:reply, nil, state}

      {^entity, components} ->
        {:reply, {entity, components}, state}
    end
  end

  @impl true
  def handle_call({:emplace, entity, component}, _from, state) do
    case do_emplace(state, {entity, component}) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:replace, entity, component}, _from, state) do
    case do_replace(state, {entity, component}) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:register, entity, name}, _from, state) do
    case do_register(state, entity, name) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:erase, entity, component_type}, _from, state) do
    case do_erase(state, entity, component_type) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:clear, entity}, _from, state) do
    case do_clear(state, entity) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:patch, entity, metadata}, _from, state) do
    case do_patch(state, entity, metadata) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:destroy, entity}, _from, state) do
    case do_destroy(state, entity) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp do_create(state, opts) do
    table = Map.fetch!(state, :metadata_table)

    transaction(fn ->
      entity = make_ref()
      name = Keyword.get(opts, :name)
      metadata = Keyword.get(opts, :metadata, %{})

      record = {table, entity, name, metadata}
      with :ok <- :mnesia.write(record), do: {:ok, entity}
    end)
  end

  defp do_emplace(state, {entity, component}) do
    type = Map.fetch!(component, :__struct__)

    table = Map.fetch!(state, :components_table)

    transaction(fn ->
      case :mnesia.index_match_object({table, entity, type, :_}, :type) do
        [] ->
          :mnesia.write({table, entity, type, component})

        [{_table, ^entity, ^type, _component}] ->
          {:error, :already_inserted}
      end
    end)
  end

  defp do_replace(state, {entity, new_component}) do
    type = Map.fetch!(new_component, :__struct__)

    table = Map.fetch!(state, :components_table)

    transaction(fn ->
      case :mnesia.index_match_object({table, entity, type, :_}, :type) do
        [] ->
          {:error, :not_found}

        [{table, ^entity, ^type, old_component}] ->
          :mnesia.delete_object({table, entity, type, old_component})
          :mnesia.write({table, entity, type, new_component})
      end
    end)
  end

  defp do_fetch(state, entity) do
    metadata_table = Map.fetch!(state, :metadata_table)
    components_table = Map.fetch!(state, :components_table)

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

  defp do_register(state, entity, name) do
    table = Map.fetch!(state, :metadata_table)

    transaction(fn ->
      case :mnesia.read(table, entity) do
        [] ->
          {:error, :not_found}

        [{_table, ^entity, nil, metadata}] ->
          :mnesia.write({table, entity, name, metadata})

        [{_table, ^entity, name, _metadata}] ->
          {:error, {:already_registered, name}}
      end
    end)
  end

  defp do_erase(state, entity, component_type) do
    metadata_table = Map.fetch!(state, :metadata_table)
    components_table = Map.fetch!(state, :components_table)

    pattern = {components_table, entity, component_type, :_}

    transaction(fn ->
      case :mnesia.read(metadata_table, entity) do
        [] ->
          {:error, :entity_not_found}

        [{_table, ^entity, _name, _metadata}] ->
          case :mnesia.index_match_object(pattern, :type) do
            [] ->
              {:error, :component_not_found}

            [{table, ^entity, type, component}] ->
              :mnesia.delete_object({table, entity, type, component})
          end
      end
    end)
  end

  defp do_patch(state, entity, new_metadata) do
    table = Map.fetch!(state, :metadata_table)

    transaction(fn ->
      case :mnesia.read(table, entity) do
        [] ->
          {:error, :not_found}

        [{_table, ^entity, name, _metadata}] ->
          :mnesia.write({table, entity, name, new_metadata})
      end
    end)
  end

  defp do_clear(state, entity) do
    metadata_table = Map.fetch!(state, :metadata_table)
    components_table = Map.fetch!(state, :components_table)

    transaction(fn ->
      case :mnesia.read(metadata_table, entity) do
        [] ->
          {:error, :not_found}

        [{_table, ^entity, _name, _metadata}] ->
          :mnesia.delete({components_table, entity})
      end
    end)
  end

  defp do_destroy(state, entity) do
    metadata_table = Map.fetch!(state, :metadata_table)
    components_table = Map.fetch!(state, :components_table)

    transaction(fn ->
      case :mnesia.read(metadata_table, entity) do
        [] ->
          {:error, :not_found}

        [{_table, ^entity, _name, _metadata}] ->
          with :ok <- :mnesia.delete({metadata_table, entity}),
               :ok <- :mnesia.delete({components_table, entity}),
               do: :ok
      end
    end)
  end

  defp ensure_metadata_table(table) do
    options = [type: :set, attributes: [:entity, :name, :metadata]]

    with :ok <- ensure_table(table, options),
         :ok <- ensure_index(table, :name),
         do: :ok
  end

  defp ensure_components_table(table) do
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

  defp transaction(fun) do
    case :mnesia.transaction(fun) do
      {:atomic, value} ->
        value

      {:aborted, reason} ->
        raise "mnesia transaction aborted: #{inspect(reason)}"
    end
  end
end
