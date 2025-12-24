defmodule Genesis.World do
  @moduledoc """
  World is a GenServer that manages the lifecycle of entities in the game.
  It is responsible for creating, cloning, and destroying entities. It also manages the event
  routing logic for entity components, ensuring that events are dispatched and handled correctly.
  """
  use GenServer

  @doc """
  Starts the World process.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Sends a message to an entity.

  The event will be dispatched to all components currently attached to the entity that
  should handle the event which will be processed in order of registration.
  """
  def send(world, entity, event, args \\ %{})

  def send(world, entity, event, args) when is_atom(event) do
    GenServer.call(world, {:send, entity, {event, args}})
  end

  @doc """
  Creates a new entity in the world.
  """
  def create(world) do
    GenServer.call(world, :create)
  end

  @doc """
  Creates a new entity from a prefab.
  The prefab must be registered before it can be used.
  """
  def create(world, name) do
    GenServer.call(world, {:create, name})
  end

  @doc """
  Fetches the components of an entity.
  """
  def fetch(entity) do
    case Genesis.Registry.fetch(:entities, entity) do
      nil -> []
      {_entity, components} -> components
    end
  end

  @doc """
  Fetches the components of an entity in the world.
  """
  def fetch(world, entity) do
    GenServer.call(world, {:fetch, entity})
  end

  @doc """
  Clones an entity with all its components.
  The clone entity will be created in the current world.
  """
  def clone(world, entity) do
    GenServer.call(world, {:clone, entity})
  end

  @doc """
  Destroys an entity from the world.
  Returns `:ok` if the entity was successfully destroyed, or `:noop` if the entity doesn't exist.
  """
  def destroy(world, entity) do
    GenServer.call(world, {:destroy, entity})
  end

  @doc """
  List all entities with their respective components.

  ## Options

    * `:format_as` - Specifies how to represent the components of each entity.
      Can be `:list` (default) to return a list of component structs, or `:map` to return
      a map where keys are component aliases and values are component structs.

  ## Examples

      iex> Genesis.World.list_entities(format_as: :list)
      [{entity, [%Health{current: 100}]}]

      iex> Genesis.World.list_entities(format_as: :map)
      [{entity, %{"health" => %Health{current: 100}}}]
  """
  def list_entities(opts \\ []) do
    stream = Genesis.Registry.entities(:entities)

    case Keyword.get(opts, :format_as, :list) do
      :list ->
        Stream.map(stream, fn {entity, components} ->
          {entity, Enum.map(components, fn {_type, component} -> component end)}
        end)

      :map ->
        components = Genesis.Manager.components()

        components_lookup =
          Map.new(components, fn {as, component_type} -> {component_type, as} end)

        Stream.map(stream, fn {entity, components} ->
          {entity,
           Map.new(components, fn {component_type, component} ->
             properties = Map.from_struct(component)
             {Map.fetch!(components_lookup, component_type), properties}
           end)}
        end)
    end
  end

  @impl true
  def init(opts) do
    max_events = Access.get(opts, :max_events, 1000)
    partitions = Access.get(opts, :partitions, System.schedulers_online())

    {:ok, supervisor} = Supervisor.start_link([], strategy: :one_for_one)

    {:ok, herald} = Supervisor.start_child(supervisor, {Genesis.Herald, partitions: partitions})

    Enum.each(0..(partitions - 1), fn partition ->
      envoy_child_spec =
        Supervisor.child_spec({Genesis.Envoy, parent: herald}, id: {:envoy, partition})

      {:ok, envoy} = Supervisor.start_child(supervisor, envoy_child_spec)

      GenStage.async_subscribe(envoy, to: herald, partition: partition)

      scribe_child_spec =
        Supervisor.child_spec({Genesis.Scribe, parent: envoy}, id: {:scribe, partition})

      {:ok, scribe} = Supervisor.start_child(supervisor, scribe_child_spec)

      GenStage.async_subscribe(scribe, to: envoy, max_demand: max_events)
    end)

    {:ok, %{herald: herald, entities: MapSet.new()}}
  end

  @impl true
  def handle_call({:send, entity, {event, args}}, {pid, _tag}, state) do
    case lookup_handlers(entity, event) do
      [] ->
        {:reply, :noop, state}

      handlers ->
        Genesis.Herald.notify(state.herald, %Genesis.Event{
          name: event,
          from: pid,
          args: args,
          world: self(),
          entity: entity,
          handlers: handlers,
          timestamp: :erlang.system_time()
        })

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:create, _from, state) do
    entity = Genesis.Manager.entity!(%{world: self()})
    entities = MapSet.put(state.entities, entity)
    {:reply, entity, %{state | entities: entities}}
  end

  @impl true
  def handle_call({:create, name}, _from, state) do
    case Genesis.Registry.lookup(:prefabs, name) do
      nil ->
        {:reply, :noop, state}

      {prefab, _name, _metadata} ->
        entity = Genesis.Manager.entity!(%{world: self()})

        case Genesis.Registry.fetch(:prefabs, prefab) do
          nil ->
            {:reply, :noop, state}

          {_entity, components} ->
            case Genesis.Registry.assign(:entities, entity, components) do
              :ok ->
                entities = MapSet.put(state.entities, entity)
                {:reply, entity, %{state | entities: entities}}

              {:error, reason} ->
                {:reply, {:error, reason}, state}
            end
        end
    end
  end

  @impl true
  def handle_call({:fetch, entity}, _from, state) do
    if MapSet.member?(state.entities, entity),
      do: {:reply, fetch(entity), state},
      else: {:reply, nil, state}
  end

  @impl true
  def handle_call({:clone, entity}, _from, state) do
    components = fetch(entity)

    clone = Genesis.Manager.entity!(%{world: self()})

    case Genesis.Registry.assign(:entities, clone, components) do
      :ok ->
        entities = MapSet.put(state.entities, clone)
        {:reply, clone, %{state | entities: entities}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:destroy, entity}, _from, state) do
    if MapSet.member?(state.entities, entity) do
      case Genesis.Registry.erase(:entities, entity) do
        :ok ->
          entities = MapSet.delete(state.entities, entity)
          {:reply, :ok, %{state | entities: entities}}

        {:error, _reason} ->
          {:reply, :noop, state}
      end
    else
      {:reply, :noop, state}
    end
  end

  defp lookup_handlers(entity, event) do
    components = fetch(entity)
    component_types = MapSet.new(components, & &1.__struct__)

    event
    |> Genesis.Manager.handlers()
    |> Enum.filter(&MapSet.member?(component_types, &1))
  end
end
