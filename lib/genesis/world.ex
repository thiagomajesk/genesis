defmodule Genesis.World do
  @moduledoc """
  The World is a GenServer that acts as a registry and manages the lifecycle of objects.
  It is responsible for creating, cloning, and destroying objects. It also manages the event
  routing for object's aspects, ensuring that events are dispatched and handled correctly.
  """
  use GenServer

  require Logger

  @doc """
  Starts the World process.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Sends a message to an object.
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
  """
  def destroy(world, object) do
    GenServer.call(world, {:destroy, object})
  end

  @doc """
  List all objects with their respective aspects.
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
    {:ok, herald} = Genesis.Herald.start_link(opts)
    {:ok, %{herald: herald, objects: MapSet.new()}}
  end

  @impl true
  def handle_call({:send, object, {event, args}}, {pid, _tag}, state) do
    case lookup_handlers(object, event) do
      [] ->
        {:reply, :noop, state}

      modules ->
        # Ensure registration order
        handlers = Enum.reverse(modules)

        event = %Genesis.Event{
          name: event,
          world: self(),
          object: object,
          from: pid,
          args: args,
          handlers: handlers
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

    case :ets.lookup(table, name) do
      [] ->
        {:reply, :noop, state}

      [{^name, %{aspects: aspects}}] ->
        object = Genesis.Utils.object_id()

        Enum.each(aspects, fn aspect ->
          # We use Genesis.Manager to attach the aspect directly,
          # to avoid triggering the attach event for this object.
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
      # We use Genesis.Manager to attach the aspect directly,
      # to avoid triggering the attach event for this object.
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
        Enum.each(aspects, fn aspect ->
          # We use Genesis.Manager to remove the aspect directly,
          # to avoid triggering the remove event for this object.
          Genesis.Manager.remove_aspect(object, aspect)
        end)

        objects = MapSet.delete(state.objects, object)
        {:reply, :ok, %{state | objects: objects}}
    end
  end

  defp lookup_handlers(object, event) do
    aspects = fetch(object)
    modules = MapSet.new(aspects, & &1.__struct__)

    table = Genesis.Manager.table(:events)

    case :ets.lookup(table, event) do
      [] ->
        []

      [{^event, handlers}] ->
        Enum.reduce(handlers, [], fn {_as, module}, acc ->
          if MapSet.member?(modules, module),
            do: [module | acc],
            else: acc
        end)
    end
  end
end
