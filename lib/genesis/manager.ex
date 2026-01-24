defmodule Genesis.Manager do
  @moduledoc """
  Manages the registration and lifecycle of components and prefabs.

  ## Components

  Genesis components are also entities with the exception they don't belong to a specific world.
  They are registered globally and are available through a named context called `Genesis.Components`.
  You can see all the registered components by calling `components/0`.

  Components can be registered with the `register_components/1` function which accepts a list of modules that implement
  the `Genesis.Component` behaviour. When components are registered, their order and some additional information is stored
  in a [`persistent_term`](https://www.erlang.org/doc/apps/erts/persistent_term.html) for efficient lookup during event dispatching.
  This means that this function is expensive and should not be called frequently - ideally once during application startup.

      Genesis.Manager.register_components([
        MyApp.Components.Health,
        MyApp.Components.Position,
        MyApp.Components.Velocity
      ])

  > #### The order of registration matters {: .info }
  > The order of registration also defines the order in which event are handled by components.
  This means that if both `Health` and `Position` components handle the `:damage` event,
  `Health` will always handle that event before `Position` and so on.

  ## Prefabs

  Prefabs are reusable entity templates that define a set of components with default properties.
  They allow you to quickly spawn entities with predefined characteristics. Like components, prefabs are also
  represented internally as entities and they also have a dedicated global named context called `Genesis.Prefabs`.
  Prefab registration can be done with the `register_prefab/1` function. This function accepts a map with the prefab
  definition including its name and components with their default properties.

      Genesis.Manager.register_prefab(%{
        name: "Spaceship",
        components: %{
          "health" => %{current: 100, maximum: 100},
          "velocity" => %{acceleration: 10, max_speed: 50}
        }
      })

  See the dedicated documentation for `Genesis.Prefab` for more details on prefab definitions.
  """

  use GenServer

  @doc """
  Clones an entity or prefab into the target context.

  ## Options

    * `:target` - the target context (defaults to `entity.context`)
    * `:overrides` - a map of component / properties to override in the cloned entity

  See `Genesis.Context.create/2` for additional options.

  ## Examples

      # Clone an entity within the same context
      Genesis.Manager.clone(entity)
      #=> {:ok, cloned}

      # Clone with property overrides
      overrides = %{"health" => %{current: 50}}
      Genesis.Manager.clone(entity, overrides: overrides)
      #=> {:ok, cloned}

      # Clone to a different context
      Genesis.Manager.clone(entity, target: context2)
      #=> {:ok, cloned}
  """
  def clone(%Genesis.Entity{} = entity, opts \\ []) do
    {overrides, opts} = Keyword.pop(opts, :overrides, %{})

    # The common use-case is to clone within the same context.
    {target_context, opts} = Keyword.pop(opts, :target, entity.context)

    case Genesis.Context.fetch(entity.context, entity) do
      nil ->
        {:error, :entity_not_found}

      {_entity, components} ->
        create_opts = Keyword.put(opts, :parent, entity)

        with {:ok, clone} <- Genesis.Context.create(target_context, create_opts),
             original = Genesis.Utils.extract_properties(components),
             merged = Genesis.Utils.merge_components(original, overrides),
             :ok <- Genesis.Context.assign(target_context, clone, merged) do
          {:ok, clone}
        end
    end
  end

  @doc """
  Returns a map of components registered in the manager.

   ## Options

    * `:index` - selects the key for the returned map (`:name` or `:type`).

  ## Examples

      Genesis.Manager.register_components([Health, Position])
      #=> :ok

      # Index by component name (default)
      Genesis.Manager.components()
      #=> %{"health" => Health, "position" => Position}

      Genesis.Manager.components(index: :name)
      #=> %{"health" => Health, "position" => Position}

      # Index by component type
      Genesis.Manager.components(index: :type)
      #=> %{Health => "health", Position => "position"}
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

  ## Examples

      Genesis.Manager.register_prefab(%{name: "X-Wing", components: ...})
      #=> {:ok, entity, [...]}

      Genesis.Manager.prefabs() |> Enum.to_list()
      #=> [{"X-Wing", %Genesis.Prefab{name: "X-Wing", components: [...]}}]
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

  ## Examples

      Genesis.Manager.register_components([Health, Position])
      #=> :ok

      Genesis.Manager.handlers()
      #=> [damage: [Health], move: [Position], heal: [Health]]
  """
  def handlers, do: events_lookup_get()

  @doc """
  Returns the handlers registered for a specific event.
  Same as `handlers/0` but filters by the specified event.
  """
  def handlers(event) when is_atom(event), do: events_lookup_get(event)

  @doc """
  Registers component modules.
  Components must implement the `Genesis.Component` behaviour.

  ## Examples

      Genesis.Manager.register_components([Health, Position, Velocity])
      #=> :ok
  """
  def register_components(components) when is_list(components) do
    registered = Enum.map(components, &register_component!/1)
    events_lookup_merge(build_events_lookup(registered))
  end

  @doc """
  Registers a new prefab definition.
  Prefabs are templates for creating entities with predefined components and properties.

  ## Examples

      Genesis.Manager.register_prefab(%{name: "Spaceship", components: ...})
      #=> {:ok, entity, [%Health{current: 50, maximum: 100}]}

      Genesis.Manager.register_prefab(%{name: "Spaceship", components: ...})
      #=> {:error, :already_registered}
  """
  def register_prefab(attrs) when is_map(attrs) do
    %{name: name, extends: extends, components: components} = Genesis.Prefab.load(attrs)

    case Genesis.Context.lookup(Genesis.Prefabs, name) do
      {_entity, _types, _metadata} ->
        {:error, :already_registered}

      nil ->
        create_opts = [name: name, metadata: %{extends: extends}]

        with {:ok, entity} <- Genesis.Context.create(Genesis.Prefabs, create_opts),
             :ok <- Genesis.Context.assign(Genesis.Prefabs, entity, components),
             do: {:ok, entity, components}
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
    events = component_type.__component__(:events)

    metadata = %{events: events, type: component_type}

    create_opts = [name: name, metadata: metadata]

    case Genesis.Context.create(Genesis.Components, create_opts) do
      {:ok, entity} ->
        {entity, component_type, events}

      {:error, :already_registered} ->
        raise ArgumentError, "component #{inspect(name)} is already registered"
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
    Enum.reduce(registered, %{}, fn {_entity, type, events}, lookup ->
      Enum.reduce(events, lookup, fn event, lookup ->
        # Store events in the correct order from the start since this will be static
        Map.update(lookup, event, [type], &(&1 ++ [type]))
      end)
    end)
  end

  defp events_lookup_get(event), do: Map.get(events_lookup_get(), event, [])
  defp events_lookup_get, do: :persistent_term.get(events_lookup_key(), %{})
  defp events_lookup_clear, do: :persistent_term.erase(events_lookup_key())
end
