defmodule Genesis.World do
  @moduledoc """
  The World is a GenServer that acts as a registry and manages the lifecycle of objects and aspects.
  It is responsible for creating, cloning, and destroying objects, as well as registering aspects and prefabs.
  It also manages the event routing for objects and aspects, ensuring that events are dispatched to the correct handlers.
  """
  use GenServer

  alias Genesis.RPC
  alias Genesis.Aspect
  alias Genesis.Context
  alias Genesis.Prefab

  require Logger

  @doc """
  Starts the World process.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a new unique object ID.
  """
  def new(), do: System.unique_integer([:positive])

  @doc """
  Fetches the aspects of an object.
  """
  def fetch(object), do: Context.all(:genesis_objects, object)

  @doc """
  List all aspects registered in the world.
  """
  def list_aspects() do
    GenServer.call(__MODULE__, :list_aspects)
  end

  @doc """
  List all objects spawned in the world.
  """
  def list_objects() do
    GenServer.call(__MODULE__, :list_objects)
  end

  @doc """
  Registers an aspect module.
  """
  def register_aspect(module) do
    # We want the server to block registration calls to ensure
    # that the table is created before other process tries to access it.
    GenServer.call(__MODULE__, {:register_aspect, module})
  end

  @doc """
  Registers a new prefab.
  """
  def register_prefab(attrs) do
    # We want the server to block registration calls to ensure
    # that the table is created before other process tries to access it.
    GenServer.call(__MODULE__, {:register_prefab, attrs})
  end

  @doc """
  Creates a new object from a prefab.
  The prefab must be registered in the World before it can be used.
  """
  def create(prefab) do
    GenServer.call(__MODULE__, {:create, prefab})
  end

  @doc """
  Clones an object with all the aspects as the original object.
  """
  def clone(object) do
    GenServer.call(__MODULE__, {:clone, object})
  end

  @doc """
  Destroys an object from the world.
  """
  def destroy(object) do
    GenServer.call(__MODULE__, {:destroy, object})
  end

  @doc """
  Sends a message to an object.
  """
  def send(object, message)

  def send(object, {op, aspect}) when op in [:"$attach", :"$remove", :"$update"] do
    # When sending an event to an object about the creation or removal of an aspect,
    # we also block to ensure that the respective ETS tables get updated for further consumption.
    GenServer.call(__MODULE__, {op, object, aspect})
  end

  def send(object, message) do
    # When sending messages that objects should handle, we don't block.
    # This is by design, because aspect handlers should work independently.
    GenServer.cast(__MODULE__, {:"$event", object, message})
  end

  @impl true
  def init(opts) do
    start_router(opts)

    Context.init(:genesis_prefabs)
    Context.init(:genesis_objects)

    # Aspects modules prefix used when loading prefabs.
    # By default it is set to "Elixir" to match the default module namespace.
    # This can be overridden in the config or so prefabs can use shorter names.
    aspect_prefix = Keyword.get(opts, :aspect_prefix, "Elixir")

    state = %{
      aspects: [],
      events_lookup: %{},
      aspect_prefix: aspect_prefix
    }

    {:ok, state, {:continue, :setup}}
  end

  @impl true
  def terminate(reason, state) do
    Context.drop(:genesis_prefabs)
    Context.drop(:genesis_objects)

    Enum.each(state.aspects, &Context.drop(elem(&1, 0)))

    Logger.info("Terminating World: #{inspect(reason)}")
  end

  @impl true
  def handle_continue(:setup, state) do
    # TODO: Load entities, etc.
    {:noreply, state}
  end

  @impl true
  def handle_call(:list_aspects, _from, state) do
    {:reply, Enum.reverse(state.aspects), state}
  end

  @impl true
  def handle_call(:list_objects, _from, state) do
    {:reply, Context.all(:genesis_objects), state}
  end

  @impl true
  def handle_call({:register_aspect, module}, _from, state) do
    if not is_aspect?(module), do: raise("Invalid aspect #{inspect(module)}")

    {table, events} = module.init()

    events_lookup =
      Enum.reduce(events, state.events_lookup, fn event, lookup ->
        Map.update(lookup, event, [table], &[table | &1])
      end)

    state =
      state
      |> Map.put(:events_lookup, events_lookup)
      |> Map.update!(:aspects, &[{table, events} | &1])

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:register_prefab, attrs}, _from, state) do
    prefab = Prefab.load(attrs, state.aspect_prefix)
    Context.add(:genesis_prefabs, prefab.name, prefab)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:create, prefab}, _from, state) do
    case Context.get(:genesis_prefabs, prefab) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %Prefab{} = prefab ->
        object = new()

        Enum.each(prefab.aspects, fn aspect ->
          aspect = struct(aspect)
          upsert_object_aspect(object, aspect)
        end)

        {:reply, object, state}
    end
  end

  @impl true
  def handle_call({:clone, object}, _from, state) do
    aspects = Context.get(:genesis_objects, object)

    new_object = new()

    # We reverse the list so we can register the aspects for the clone
    # in the same order as they were registered for the original object.
    aspects
    |> Enum.reverse()
    |> Enum.each(&upsert_object_aspect(new_object, &1))

    {:reply, new_object, state}
  end

  @impl true
  def handle_call({:destroy, object}, _from, state) do
    case Context.get(:genesis_objects, object) do
      nil ->
        {:reply, :noop, state}

      aspects ->
        Context.remove(:genesis_objects, object)
        Enum.each(aspects, &Context.remove(aspect_table(&1), object))
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:"$attach", object, aspect}, _from, state) do
    upsert_object_aspect(object, aspect)

    # TODO: Notify the object about the aspect (ATTACH)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:"$update", object, aspect}, _from, state) do
    upsert_object_aspect(object, aspect)

    # TODO: Notify the object about the aspect (UPDATE)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:"$remove", object, aspect}, _from, state) do
    remove_object_aspect(object, aspect)

    # TODO: Notify the object about the aspect (REMOVE)

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:"$event", object, {event, args}}, state) do
    aspects = fetch(object)
    modules_lookup = MapSet.new(Enum.map(aspects, & &1.__struct__))
    dispatch_lookup = MapSet.new(Map.get(state.events_lookup, event, []))

    modules = MapSet.intersection(dispatch_lookup, modules_lookup)

    # We use the RPC GenServer to dispatch events to object's aspects.
    # This ensures that the World GenServer won't deadlock if aspects need to
    # perform blocking operations like calling Aspect.attach/2 or Aspect.remove/2.
    # Additionally, the Router (PartitionSupervisor) will guarantee that events are processed
    # in the correct order - Sequentially for the same object, and in parallel for different objects.
    message = {event, args, object, Enum.reverse(modules)}
    RPC.dispatch({:via, PartitionSupervisor, {Router, object}}, message)

    {:noreply, state}
  end

  defp start_router(opts) do
    # Starts the event router for the World. The Router is the name we use for the partition supervisor
    # that is responsible for correctly segmenting all object events. See `Genesis.RPC` for more details.
    partitions = Keyword.get(opts, :partitions, System.schedulers_online())
    PartitionSupervisor.start_link(child_spec: RPC, name: Router, partitions: partitions)
  end

  defp upsert_object_aspect(object, aspect) do
    update_object_aspect(object, aspect)
    Context.add(aspect_table(aspect), object, aspect)
  end

  defp remove_object_aspect(object, aspect) do
    Context.remove(aspect_table(aspect), object)
    Context.update!(:genesis_objects, object, &without_aspect(&1, aspect))
  end

  defp aspect_table(%{__struct__: module}), do: module

  defp update_object_aspect(object, new_aspect) do
    Context.update(:genesis_objects, object, [new_aspect], fn aspects ->
      # Make sure we remove any old versions of the aspect
      [new_aspect | without_aspect(aspects, new_aspect)]
    end)
  end

  defp without_aspect(aspects, aspect) do
    Enum.reject(aspects, &(&1.__struct__ == aspect.__struct__))
  end

  defp is_aspect?(module) do
    attributes = module.__info__(:attributes)
    Aspect in Access.get(attributes, :behaviour, [])
  end
end
