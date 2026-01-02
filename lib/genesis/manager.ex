defmodule Genesis.Manager do
  @moduledoc """
  Manages the registration and lifecycle of components and prefabs.
  """

  use GenServer

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
  Clones an entity or named prefab from a specified registry into the target registry.
  """
  def clone!(entity, opts \\ []) when is_reference(entity) do
    metadata = Keyword.get(opts, :metadata, %{})

    if not is_map(metadata) do
      raise ArgumentError, ":metadata option must be a map"
    end

    overrides = Keyword.get(opts, :overrides, %{})

    if not is_map(overrides) do
      raise ArgumentError, ":overrides option must be a map"
    end

    # The common use-case is to clone within the same registry.
    source_registry = Keyword.fetch!(opts, :source)
    target_registry = Keyword.get(opts, :target, source_registry)

    case Genesis.Registry.fetch(source_registry, entity) do
      nil ->
        :noop

      {_entity, components} ->
        clone = entity!(metadata)

        original = Genesis.Utils.extract_properties(components)
        merged = Genesis.Utils.merge_components(original, overrides)

        case Genesis.Registry.assign(target_registry, clone, merged) do
          :ok ->
            {:ok, clone}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Returns a map of components registered in the manager.

   ## Options

    * `:index` - selects the key for the returned map (`:name` or `:type`).

  ## Examples

      iex> Genesis.Manager.components(index: :name)
      %{"health" => Health, "position" => Position}

      iex> Genesis.Manager.components(index: :type)
      %{Health => "health", Position => "position"}
  """
  def components(opts \\ []) do
    stream = Genesis.Registry.metadata(:components)

    case Keyword.get(opts, :index, :name) do
      :name ->
        Map.new(stream, fn {_entity, {name, metadata}} ->
          {name, metadata.type}
        end)

      :type ->
        Map.new(stream, fn {_entity, {name, metadata}} ->
          {metadata.type, name}
        end)

      other ->
        raise ArgumentError, "invalid :index option #{inspect(other)}"
    end
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
  def handlers, do: events_lookup_get()

  @doc """
  Returns the handlers registered for a specific event.
  """
  def handlers(event) when is_atom(event), do: events_lookup_get(event)

  @doc """
  Registers a component module with an optional custom alias.

  Alias are useful to scope components in different domains.
  If only the module is provided, a default alias is used.

      iex> Genesis.Manager.register_components([Health])
      iex> Genesis.Manager.register_components([{"prefix::health", Health}])
  """
  def register_components(components) when is_list(components) do
    registered = Enum.map(components, &register_component!/1)
    events_lookup_merge(build_events_lookup(registered))
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

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_opts) do
    registries = [:prefabs, :entities, :components]
    Enum.each(registries, &Genesis.Registry.init/1)

    {:ok, %{}}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    events_lookup_clear()

    registries = [:prefabs, :entities, :components]
    Enum.each(registries, &Genesis.Registry.clear/1)

    {:reply, :ok, state}
  end

  defp events_lookup_key, do: {__MODULE__, :events}

  defp events_lookup_merge(events) do
    updated = Map.merge(events_lookup_get(), events)
    :persistent_term.put(events_lookup_key(), updated)
  end

  defp build_events_lookup(registered) do
    Enum.reduce(registered, %{}, fn {_entity, metadata}, lookup ->
      Enum.reduce(metadata.events, lookup, fn event, lookup ->
        # Store events in the correct by concateneting the list instead of prepending
        Map.update(lookup, event, [metadata.type], &(&1 ++ [metadata.type]))
      end)
    end)
  end

  defp events_lookup_get(event), do: Map.get(events_lookup_get(), event, [])
  defp events_lookup_get, do: :persistent_term.get(events_lookup_key(), %{})
  defp events_lookup_clear, do: :persistent_term.erase(events_lookup_key())
end
