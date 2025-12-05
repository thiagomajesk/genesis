defmodule Genesis.Manager do
  @moduledoc """
  Manages the registration and lifecycle of components and prefabs.
  """

  use GenServer

  @doc """
  Clones an entity or prefab from a specified context into the target context.
  """
  def clone!(%Genesis.Entity{} = entity, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})

    if not is_map(metadata) do
      raise ArgumentError, ":metadata option must be a map"
    end

    overrides = Keyword.get(opts, :overrides, %{})

    if not is_map(overrides) do
      raise ArgumentError, ":overrides option must be a map"
    end

    # The common use-case is to clone within the same context.
    source_context = Keyword.fetch!(opts, :source)
    target_context = Keyword.get(opts, :target, source_context)

    case Genesis.Context.fetch(source_context, entity) do
      nil ->
        :noop

      {_entity, components} ->
        clone =
          Genesis.Context.create(target_context,
            name: nil,
            parent: entity.name,
            metadata: metadata,
            context: target_context
          )

        original = Genesis.Utils.extract_properties(components)
        merged = Genesis.Utils.merge_components(original, overrides)
        with :ok <- Genesis.Context.assign(target_context, clone, merged), do: {:ok, clone}
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
    stream = Genesis.Context.metadata(Genesis.Components)

    case Keyword.get(opts, :index, :name) do
      :name ->
        Map.new(stream, fn {entity, {_types, metadata}} ->
          {entity.name, metadata.type}
        end)

      :type ->
        Map.new(stream, fn {entity, {_types, metadata}} ->
          {metadata.type, entity.name}
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
    stream = Genesis.Context.entities(Genesis.Prefabs)

    Stream.map(stream, fn {entity, {_types, metadata, components}} ->
      extends = Map.get(metadata, :extends, [])
      {entity.name, %Genesis.Prefab{name: entity.name, extends: extends, components: components}}
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
  Registers component modules.

      iex> Genesis.Manager.register_components([Health, Position])
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

    case Genesis.Context.lookup(Genesis.Prefabs, name) do
      {_entity, _types, _metadata} ->
        {:error, :already_registered}

      nil ->
        metadata = %{extends: extends}

        entity =
          Genesis.Context.create(
            Genesis.Prefabs,
            name: name,
            metadata: metadata,
            context: Genesis.Prefabs
          )

        with :ok <- Genesis.Context.assign(Genesis.Prefabs, entity, components),
             do: {:ok, entity, metadata, components}
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

  defp register_component!(component_type) when is_atom(component_type) do
    if not Genesis.Utils.component?(component_type) do
      raise ArgumentError, "Invalid component type #{inspect(component_type)}"
    end

    name = component_type.__component__(:name)

    case Genesis.Context.lookup(Genesis.Components, name) do
      {entity, _types, _metadata} ->
        raise ArgumentError, "component #{inspect(entity.name)} is already registered"

      nil ->
        created_at = System.system_time()
        events = component_type.__component__(:events)
        metadata = %{created_at: created_at, events: events, type: component_type}

        entity =
          Genesis.Context.create(
            Genesis.Components,
            name: name,
            metadata: metadata,
            context: Genesis.Components
          )

        {entity, metadata}
    end
  end

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call(:reset, _from, state) do
    events_lookup_clear()

    Genesis.Context.clear(Genesis.Prefabs)
    Genesis.Context.clear(Genesis.Components)

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
        # Store events in the correct order from the start since this will be static
        Map.update(lookup, event, [metadata.type], &(&1 ++ [metadata.type]))
      end)
    end)
  end

  defp events_lookup_get(event), do: Map.get(events_lookup_get(), event, [])
  defp events_lookup_get, do: :persistent_term.get(events_lookup_key(), %{})
  defp events_lookup_clear, do: :persistent_term.erase(events_lookup_key())
end
