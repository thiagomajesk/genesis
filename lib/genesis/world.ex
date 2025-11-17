defmodule Genesis.World do
  @moduledoc """
  World is a GenServer that manages the lifecycle of objects in the game.
  It is responsible for creating, cloning, and destroying objects. It also manages the event
  routing logic for object's aspects, ensuring that events are dispatched and handled correctly.
  """
  use GenServer

  @doc """
  Starts the World process.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Sends a message to an object.

  The event will be dispatched to all aspects currently attached to the object that
  should handle the event which will be processed in order of registration.
  """
  def send(world, object, event, args \\ %{})

  def send(world, object, event, args) when is_atom(event) do
    GenServer.call(world, {:send, object, {event, args}})
  end

  @doc """
  Creates a new object in the world.
  """
  def create(world) do
    GenServer.call(world, :create)
  end

  @doc """
  Creates a new object from a prefab.
  The prefab must be registered before it can be used.
  """
  def create(world, name) do
    GenServer.call(world, {:create, name})
  end

  @doc """
  Fetches the aspects of an object.
  """
  def fetch(object) do
    table = Genesis.Manager.table(:objects)
    :ets.select(table, [{{object, :"$1"}, [], [:"$1"]}])
  end

  @doc """
  Fetches the aspects of an object in the world.
  """
  def fetch(world, object) do
    GenServer.call(world, {:fetch, object})
  end

  @doc """
  Clones an object with all its aspects.
  The clone object will be created in the current world.
  """
  def clone(world, object) do
    GenServer.call(world, {:clone, object})
  end

  @doc """
  Destroys an object from the world.
  Returns `:ok` if the object was successfully destroyed, or `:noop` if the object doesn't exist.
  """
  def destroy(world, object) do
    GenServer.call(world, {:destroy, object})
  end

  @doc """
  List all objects with their respective aspects.

  ## Options

    * `:aspects_as` - Specifies how to represent the aspects of each object.
      Can be `:list` (default) to return a list of aspect structs, or `:map` to return
      a map where keys are aspect aliases and values are aspect structs.

  ## Examples

      iex> Genesis.World.list_objects(aspects_as: :list)
      [{1, [%Health{current: 100}]}]

      iex> Genesis.World.list_objects(aspects_as: :map)
      [{1, %{"health" => %Health{current: 100}}}]
  """
  def list_objects(opts \\ []) do
    table = Genesis.Manager.table(:objects)

    case Keyword.get(opts, :aspects_as, :list) do
      :list ->
        Genesis.ETS.group_keys(table)

      :map ->
        stream = Genesis.ETS.group_keys(table)

        aspects_lookup =
          Map.new(
            Genesis.Manager.list_aspects(),
            fn {as, module} -> {module, as} end
          )

        Stream.map(stream, fn {object, aspects} ->
          {object,
           Map.new(aspects, fn aspect ->
             {module, map} = Map.pop!(aspect, :__struct__)
             {Map.fetch!(aspects_lookup, module), map}
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

    {:ok, %{herald: herald, objects: MapSet.new()}}
  end

  @impl true
  def handle_call({:send, object, {event, args}}, {pid, _tag}, state) do
    case lookup_handlers(object, event) do
      [] ->
        {:reply, :noop, state}

      modules ->
        event = %Genesis.Event{
          name: event,
          from: pid,
          args: args,
          world: self(),
          object: object,
          handlers: Enum.reverse(modules),
          timestamp: :erlang.system_time()
        }

        Genesis.Herald.notify(state.herald, event)

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:create, _from, state) do
    object = Genesis.Utils.object_id()
    objects = MapSet.put(state.objects, object)
    {:reply, object, %{state | objects: objects}}
  end

  @impl true
  def handle_call({:create, name}, _from, state) do
    table = Genesis.Manager.table(:prefabs)

    case Genesis.ETS.get(table, name, nil) do
      nil ->
        {:reply, :noop, state}

      %{aspects: aspects} ->
        object = Genesis.Utils.object_id()

        Enum.each(aspects, fn aspect ->
          Genesis.Manager.attach_aspect(object, aspect)
        end)

        objects = MapSet.put(state.objects, object)
        {:reply, object, %{state | objects: objects}}
    end
  end

  @impl true
  def handle_call({:fetch, object}, _from, state) do
    if MapSet.member?(state.objects, object),
      do: {:reply, fetch(object), state},
      else: {:reply, nil, state}
  end

  @impl true
  def handle_call({:clone, object}, _from, state) do
    aspects = fetch(object)

    clone = Genesis.Utils.object_id()

    Enum.each(aspects, fn aspect ->
      Genesis.Manager.attach_aspect(clone, aspect)
    end)

    objects = MapSet.put(state.objects, clone)
    {:reply, clone, %{state | objects: objects}}
  end

  @impl true
  def handle_call({:destroy, object}, _from, state) do
    can_destroy? = MapSet.member?(state.objects, object)

    case {can_destroy?, fetch(object)} do
      {false, _aspects} ->
        {:reply, :noop, state}

      {true, aspects} ->
        Enum.each(aspects, fn %{__struct__: module} ->
          Genesis.Manager.remove_aspect(object, module)
        end)

        objects = MapSet.delete(state.objects, object)
        {:reply, :ok, %{state | objects: objects}}
    end
  end

  defp lookup_handlers(object, event) do
    aspects = fetch(object)
    modules = MapSet.new(aspects, & &1.__struct__)

    table = Genesis.Manager.table(:events)

    case Genesis.ETS.get(table, event, nil) do
      nil ->
        []

      handlers ->
        Enum.reduce(handlers, [], fn {_as, module}, acc ->
          if MapSet.member?(modules, module),
            do: [module | acc],
            else: acc
        end)
    end
  end
end
