defmodule Genesis.World do
  @moduledoc """
  World is a GenServer that manages the lifecycle of entities at runtime.
  A world is responsible for creating, cloning, and destroying entities from its own context.
  It also manages the event routing logic for the components an entity has, ensuring that events are dispatched and handled correctly.
  """
  use GenServer
  require Logger

  @doc """
  Starts the world process.
  Same as `GenServer.start_link/3`.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Sends an event to an entity.

  ## Examples

      Genesis.World.send(world, entity, :move, %{direction: :north})
      #=> :ok

      Genesis.World.send(world, entity, :damage, %{amount: 10})
      #=> :ok

  """
  def send(world, entity, event, args \\ %{})

  def send(world, %Genesis.Entity{} = entity, event, args) when is_atom(event) do
    GenServer.call(world, {:send, entity, {event, args}})
  end

  @doc """
  Returns the underlying world context.

  Since both writes and reads in a world are always synchronous, this function
  creates an escape hatch so users can execute operations using the underlying context.
  All read operations executed directly in the context should be considered dirty by default.

  ## Example

      context = World.context(world)
      Genesis.Context.search(context, ...)
  """
  def context(world) do
    GenServer.call(world, :context)
  end

  @doc """
  Executes a function with the world context synchronously.

  Differently from `context/1`, this allows for safe context operations
  since it's executed synchronously within the world server itself. The function
  must return a value that will be replied back to the caller.

  ## Example

      World.context(world, fn ctx ->
        Genesis.Context.emplace(ctx, entity, component)
      end)
  """
  def context(world, fun) when is_function(fun, 1) do
    GenServer.call(world, {:context, fun})
  end

  @doc """
  Creates a new entity in the world.

  ## Examples

      Genesis.World.create(world)
      #=> {:ok, entity}

  """
  def create(world) do
    GenServer.call(world, :create)
  end

  @doc """
  Creates a new entity from a prefab.
  The prefab must be registered before it can be used.
  Optionally, you can provide overrides to modify component properties.

  ## Examples

      # Using a prefab name
      Genesis.World.create(world, "Player")
      #=> {:ok, entity}

      # Or using a prefab entity directly
      Genesis.World.create(world, prefab)
      #=> {:ok, entity}

      Genesis.World.create(world, "Player", %{"health" => %{current: 50}})
      #=> {:ok, entity}
  """
  def create(world, name_or_prefab, overrides \\ %{})

  def create(world, name_or_prefab, overrides) do
    GenServer.call(world, {:create, name_or_prefab, overrides})
  end

  @doc """
  Same as `Genesis.World.fetch/2` but scoped to the world.
  """
  def fetch(world, entity) do
    GenServer.call(world, {:fetch, entity})
  end

  @doc """
  Same as `Genesis.Context.all/2` but scoped to the world.
  """
  def all(world, component_type) do
    GenServer.call(world, {:all, component_type})
  end

  @doc """
  Same as `Genesis.Context.match/3` but scoped to the world.
  """
  def match(world, component_type, properties) do
    GenServer.call(world, {:match, component_type, properties})
  end

  @doc """
  Same as `Genesis.Context.at_least/4` but scoped to the world.
  """
  def at_least(world, component_type, property, value) do
    GenServer.call(world, {:at_least, component_type, property, value})
  end

  @doc """
  Same as `Genesis.Context.at_most/4` but scoped to the world.
  """
  def at_most(world, component_type, property, value) do
    GenServer.call(world, {:at_most, component_type, property, value})
  end

  @doc """
  Same as `Genesis.Context.between/5` but scoped to the world.
  """
  def between(world, component_type, property, min, max) do
    GenServer.call(world, {:between, component_type, property, min, max})
  end

  @doc """
  Same as `Genesis.Context.exists?/2` but scoped to the world.
  """
  def exists?(world, entity) do
    GenServer.call(world, {:exists?, entity})
  end

  @doc """
  Clones an entity with all its components.
  See `Genesis.Manager.clone/2` for more details.
  """
  def clone(world, entity, opts \\ []) do
    GenServer.call(world, {:clone, entity, opts})
  end

  @doc """
  Destroys an entity from the world.
  Returns `:ok` if the entity was successfully destroyed, or `:noop` if the entity doesn't exist.
  See `Genesis.Context.destroy/2` for more details.
  """
  def destroy(world, entity) do
    GenServer.call(world, {:destroy, entity})
  end

  @doc """
  List all entities in the world with their respective components.

  ## Options

    * `:format_as` - Specifies how to represent the components of each entity.
      Can be `:list` (default) to return a list of component structs, or `:map` to return
      a map where keys are component aliases and values are component structs.

  ## Examples

      Genesis.World.list(world, format_as: :list)
      #=> [{entity, [%Health{current: 100}]}]

      Genesis.World.list(world, format_as: :map)
      #=> [{entity, %{"health" => %Health{current: 100}}}]
  """
  def list(world, opts \\ []) do
    GenServer.call(world, {:list, opts})
  end

  @impl true
  def init(opts) do
    max_events = Access.get(opts, :max_events, 1000)
    partitions = Access.get(opts, :partitions, System.schedulers_online())

    {:ok, context} = Genesis.Context.start_link()
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

    {:ok, %{herald: herald, context: context}}
  end

  @impl true
  def handle_call(:context, _from, state) do
    {:reply, state.context, state}
  end

  @impl true
  def handle_call({:context, fun}, _from, state) do
    {:reply, fun.(state.context), state}
  end

  @impl true
  def handle_call({:send, entity, {event, args}}, _from, state) do
    case lookup_handlers(entity, state, event) do
      [] ->
        {:reply, :noop, state}

      handlers ->
        Genesis.Herald.notify(state.herald, %Genesis.Event{
          name: event,
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
    opts = [context: state.context, world: self()]
    {:reply, Genesis.Context.create(state.context, opts), state}
  end

  @impl true
  def handle_call({:create, name, overrides}, _from, state) when is_binary(name) do
    clone_opts = [target: state.context, overrides: overrides]

    case Genesis.Context.lookup(Genesis.Prefabs, name) do
      nil ->
        {:reply, :noop, state}

      {prefab, _types, _metadata} ->
        {:reply, Genesis.Manager.clone(prefab, clone_opts), state}
    end
  end

  @impl true
  def handle_call({:create, %Genesis.Entity{} = prefab, overrides}, _from, state) do
    clone_opts = [target: state.context, overrides: overrides]

    if Genesis.Entity.prefab?(prefab),
      do: {:reply, Genesis.Manager.clone(prefab, clone_opts), state},
      else: {:reply, :noop, state}
  end

  @impl true
  def handle_call({:fetch, entity}, _from, state) do
    case Genesis.Context.fetch(state.context, entity) do
      nil ->
        {:reply, nil, state}

      {_entity, components} ->
        {:reply, components, state}
    end
  end

  @impl true
  def handle_call({:all, component_type}, _from, state) do
    {:reply, Genesis.Context.all(state.context, component_type), state}
  end

  @impl true
  def handle_call({:match, component_type, properties}, _from, state) do
    {:reply, Genesis.Context.match(state.context, component_type, properties), state}
  end

  @impl true
  def handle_call({:at_least, component_type, property, value}, _from, state) do
    {:reply, Genesis.Context.at_least(state.context, component_type, property, value), state}
  end

  @impl true
  def handle_call({:at_most, component_type, property, value}, _from, state) do
    {:reply, Genesis.Context.at_most(state.context, component_type, property, value), state}
  end

  @impl true
  def handle_call({:between, component_type, property, min, max}, _from, state) do
    {:reply, Genesis.Context.between(state.context, component_type, property, min, max), state}
  end

  @impl true
  def handle_call({:exists?, entity}, _from, state) do
    {:reply, Genesis.Context.exists?(state.context, entity), state}
  end

  @impl true
  def handle_call({:clone, entity, opts}, _from, state) do
    {:reply, Genesis.Manager.clone(entity, opts), state}
  end

  @impl true
  def handle_call({:destroy, entity}, _from, state) do
    case Genesis.Context.destroy(state.context, entity) do
      :ok ->
        {:reply, :ok, state}

      {:error, _reason} ->
        {:reply, :noop, state}
    end
  end

  @impl true
  def handle_call({:list, opts}, _from, state) do
    stream = Genesis.Context.entities(state.context)

    result =
      case Keyword.get(opts, :format_as, :list) do
        :list ->
          Stream.map(stream, fn {entity, {_, _, components}} ->
            {entity, components}
          end)

        :map ->
          Stream.map(stream, fn {entity, {_, _, components}} ->
            aliased_components =
              Map.new(components, fn component ->
                {component_type, properties} = Map.pop(component, :__struct__)
                {component_type.__component__(:name), properties}
              end)

            {entity, aliased_components}
          end)
      end

    {:reply, result, state}
  end

  defp lookup_handlers(entity, state, event) do
    case Genesis.Context.fetch(state.context, entity) do
      nil ->
        []

      {^entity, components} ->
        component_types = MapSet.new(components, & &1.__struct__)

        event
        |> Genesis.Manager.handlers()
        |> Enum.filter(&MapSet.member?(component_types, &1))
    end
  end
end
