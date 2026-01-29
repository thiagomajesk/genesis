defmodule Genesis.Manager do
  @moduledoc """
  Manages the registration and lifecycle of components and prefabs.

  ## Components

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

  @events_key {__MODULE__, :events}
  @components_key {__MODULE__, :components}

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
  def handlers, do: :persistent_term.get(@events_key, %{})

  @doc """
  Returns a map of components registered in the manager.

  ## Examples

      Genesis.Manager.register_components([Health, Position])
      #=> :ok

      Genesis.Manager.components()
      #=> %{"health" => Health, "position" => Position}
  """
  def components(), do: :persistent_term.get(@components_key, %{})

  @doc """
  Registers component modules.
  Components must implement the `Genesis.Component` behaviour.

  ## Examples

      Genesis.Manager.register_components([Health, Position, Velocity])
      #=> :ok
  """
  def register_components(components) when is_list(components) do
    registered = Enum.map(components, &ensure_component!/1)

    Enum.each(registered, fn {component_type, name, events} ->
      components = :persistent_term.get(@components_key, %{})
      updated_components = Map.put(components, name, component_type)
      :persistent_term.put(@components_key, updated_components)

      Enum.each(events, fn event ->
        events = :persistent_term.get(@events_key, %{})
        # Store events in the correct order from the start since this will be static
        updated_events = Map.update(events, event, [component_type], &(&1 ++ [component_type]))
        :persistent_term.put(@events_key, updated_events)
      end)
    end)
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
  def reset do
    with true <- :persistent_term.erase(@events_key),
         true <- :persistent_term.erase(@components_key),
         :ok <- Genesis.Context.clear(Genesis.Prefabs),
         do: :ok
  end

  defp ensure_component!(component_type) when is_atom(component_type) do
    if not Genesis.Utils.component?(component_type) do
      raise ArgumentError, "Invalid component type #{inspect(component_type)}"
    end

    name = component_type.__component__(:name)
    events = component_type.__component__(:events)

    components = :persistent_term.get(@components_key, %{})

    # Duplicate registrations are not a big deal, but it can be annoying if we allow silent
    # overwrites. This can lead to subtle bugs that are hard to track down after the fact.
    case Map.fetch(components, name) do
      :error ->
        {component_type, name, events}

      {:ok, component_type} ->
        raise ArgumentError,
              "The component #{inspect(component_type)} is already registered as #{inspect(name)}"
    end
  end
end
