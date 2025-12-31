defmodule Genesis.Manager do
  @doc """
  Creates a new entity in the registry.

      iex> Genesis.Manager.entity!()
      #Reference<0.1234567890.1234567890.12345>
  """
  def entity!(metadata \\ %{}) do
    case Genesis.Registry.create(:entities, metadata: metadata) do
      {:ok, entity} -> entity
      {:error, reason} -> raise "Failed to create entity: #{inspect(reason)}"
    end
  end

  @doc """
  Returns a stream of components registered in the manager.

      iex> Genesis.Manager.components() |> Enum.to_list()
      [{"health", Health}, {"position", Position}]
  """
  def components do
    stream = Genesis.Registry.metadata(:components)

    Stream.map(stream, fn {_entity, {name, metadata}} ->
      {name, metadata.type}
    end)
  end

  @doc """
  Returns a stream of prefabs registered in the manager.

      iex> Genesis.Manager.prefabs() |> Enum.to_list()
      [{"Being", %Genesis.Prefab{components: components}}]
  """
  def prefabs do
    stream = Genesis.Registry.entities(:prefabs)

    Stream.map(stream, fn {_entity, {name, metadata, components}} ->
      extends = Map.get(metadata, :extends, [])
      {name, %Genesis.Prefab{name: name, extends: extends, components: components}}
    end)
  end

  @doc """
  Returns all event handlers registered in the manager.
  """
  def handlers do
    Enum.reduce(:persistent_term.get(), %{}, fn
      {{:genesis, :events, event}, handlers}, acc ->
        Map.put(acc, event, Enum.reverse(handlers))

      {_other_key, _other_value}, acc ->
        acc
    end)
  end

  @doc """
  Returns the handlers registered for a specific event.
  """
  def handlers(event) when is_atom(event) do
    key = {:genesis, :events, event}
    Enum.reverse(:persistent_term.get(key, []))
  end

  @doc """
  Registers a component module with an optional custom alias.

  Alias are useful to scope components in different domains.
  If only the module is provided, a default alias is used.

      iex> Genesis.Manager.register_components([Health])
      iex> Genesis.Manager.register_components([{"prefix::health", Health}])
  """
  def register_components(components) when is_list(components) do
    registered =
      components
      |> Enum.map(&register_component!/1)
      |> Enum.reduce(%{}, fn {_entity, metadata}, lookup ->
        Enum.reduce(metadata.events, lookup, fn event, lookup ->
          Map.update(lookup, event, [metadata.type], &[metadata.type | &1])
        end)
      end)

    Enum.each(registered, fn {event, component_types} ->
      :persistent_term.put({:genesis, :events, event}, component_types)
    end)
  end

  @doc """
  Registers a new prefab definition.
  Prefabs are templates for creating entities with predefined components and properties.
  """
  def register_prefab(attrs) when is_map(attrs) do
    %{name: name, extends: extends, components: components} = Genesis.Prefab.load(attrs)

    case Genesis.Registry.lookup(:prefabs, name) do
      {_entity, _name, _metadata} ->
        {:error, :already_registered}

      nil ->
        metadata = %{extends: extends}
        options = [name: name, metadata: metadata]

        with {:ok, entity} <- Genesis.Registry.create(:prefabs, options),
             :ok <- Genesis.Registry.assign(:prefabs, entity, components) do
          {:ok, {entity, metadata, components}}
        end
    end
  end

  @doc false
  def init do
    with :ok <- Genesis.Registry.init(:prefabs),
         :ok <- Genesis.Registry.init(:entities),
         :ok <- Genesis.Registry.init(:components),
         do: :ok
  end

  @doc false
  def reset() do
    with :ok <- clear_event_lookup(),
         :ok <- Genesis.Registry.clear(:prefabs),
         :ok <- Genesis.Registry.clear(:entities),
         :ok <- Genesis.Registry.clear(:components),
         do: :ok
  end

  def register_component!(component_type) when is_atom(component_type) do
    register_component!({Genesis.Utils.aliasify(component_type), component_type})
  end

  def register_component!({name, component_type}) when is_atom(component_type) do
    if not Genesis.Utils.component?(component_type) do
      raise ArgumentError, "Invalid component type #{inspect(component_type)}"
    end

    case Genesis.Registry.lookup(:components, name) do
      {_entity, name, _metadata} ->
        raise ArgumentError, "component #{inspect(name)} is already registered"

      nil ->
        created_at = System.system_time()
        events = component_type.__component__(:events)
        metadata = %{created_at: created_at, events: events, type: component_type}

        case Genesis.Registry.create(:components, name: name, metadata: metadata) do
          {:ok, entity} ->
            {entity, metadata}

          {:error, reason} ->
            raise "failed to register component #{inspect(name)}: #{inspect(reason)}"
        end
    end
  end

  defp clear_event_lookup() do
    events = Map.keys(handlers())

    Enum.each(events, fn event ->
      :persistent_term.erase({:genesis, :events, event})
    end)
  end
end
