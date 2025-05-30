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
  alias Genesis.Naming

  require Logger

  @doc """
  Starts the World process.
  """
  def start_link(opts \\ []) do
    server = Naming.server(__MODULE__)
    GenServer.start_link(__MODULE__, opts, name: server)
  end

  @doc """
  Creates a new unique object ID.
  """
  def new(), do: System.unique_integer([:positive])

  @doc """
  Fetches the aspects of an object.
  """
  def fetch(object), do: Context.all(Naming.table(:objects), object)

  @doc """
  List all aspects registered in the world.
  """
  def list_aspects() do
    server = Naming.server(__MODULE__)
    GenServer.call(server, :list_aspects)
  end

  @doc """
  List all objects spawned in the world.
  """
  def list_objects() do
    server = Naming.server(__MODULE__)
    GenServer.call(server, :list_objects)
  end

  @doc """
  Registers an aspect module.
  """
  def register_aspect(module_or_tuple)

  def register_aspect(module) when is_atom(module) do
    register_aspect({Naming.alias(module), module})
  end

  def register_aspect({as, module}) do
    # We want the server to block registration calls to ensure
    # that the table is created before other process tries to access it.
    server = Naming.server(__MODULE__)
    GenServer.call(server, {:register_aspect, {as, module}})
  end

  @doc """
  Registers a new prefab.
  """
  def register_prefab(attrs) do
    # We want the server to block registration calls to ensure
    # that the table is created before other process tries to access it.
    server = Naming.server(__MODULE__)
    GenServer.call(server, {:register_prefab, attrs})
  end

  @doc """
  Creates a new object from a prefab.
  The prefab must be registered in the World before it can be used.
  """
  def create(prefab) do
    server = Naming.server(__MODULE__)
    GenServer.call(server, {:create, prefab})
  end

  @doc """
  Clones an object with all the aspects as the original object.
  """
  def clone(object) do
    server = Naming.server(__MODULE__)
    GenServer.call(server, {:clone, object})
  end

  @doc """
  Destroys an object from the world.
  """
  def destroy(object) do
    server = Naming.server(__MODULE__)
    GenServer.call(server, {:destroy, object})
  end

  @doc """
  Waits for all object events to be processed.
  Returns a list of the events processed so far.
  """
  def flush(timeout \\ :infinity) do
    server = Naming.server(__MODULE__)
    GenServer.call(server, :"$flush", timeout)
  end

  @doc """
  Sends a message to an object.
  """
  def send(object, event, args \\ %{})

  def send(object, event, aspect) when event in [:"$attach", :"$remove", :"$update"] do
    # When sending an event to an object about the creation or removal of an aspect,
    # we also block to ensure that the respective ETS tables get updated for further consumption.
    server = Naming.server(__MODULE__)
    GenServer.call(server, {event, object, aspect})
  end

  def send(object, event, args) when is_atom(event) do
    # When sending messages that objects should handle, we don't block.
    # This is by design, because aspect handlers should work independently.
    server = Naming.server(__MODULE__)
    GenServer.cast(server, {:"$event", object, {event, args}})
  end

  @impl true
  def init(opts) do
    start_router(opts)

    Context.init(Naming.table(:objects))
    Context.init(Naming.table(:prefabs))

    state = %{
      aspects: [],
      events_lookup: %{}
    }

    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    Context.drop(Naming.table(:objects))
    Context.drop(Naming.table(:prefabs))

    Enum.each(state.aspects, &Context.drop(elem(&1, 2)))

    Logger.info("Terminating World: #{inspect(reason)}")
  end

  @impl true
  def handle_call(:list_aspects, _from, state) do
    {:reply, Enum.reverse(state.aspects), state}
  end

  @impl true
  def handle_call(:list_objects, _from, state) do
    {:reply, Context.all(Naming.table(:objects)), state}
  end

  @impl true
  def handle_call({:register_aspect, {as, module}}, _from, state) do
    if not is_aspect?(module), do: raise("Invalid aspect #{inspect(module)}")

    # The table name here is mostly used for debugging purposes.
    # We use the `Naming.table(module) to get the proper table name.
    {table, events} = module.init()

    events_lookup =
      Enum.reduce(events, state.events_lookup, fn event, lookup ->
        Map.update(lookup, event, [module], &[module | &1])
      end)

    state =
      state
      |> Map.put(:events_lookup, events_lookup)
      |> Map.update!(:aspects, &[{module, as, table, events} | &1])

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:register_prefab, attrs}, _from, state) do
    prefab = Prefab.load(attrs, state.aspects)

    Context.add(Naming.table(:prefabs), prefab.name, prefab)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:create, prefab}, _from, state) do
    case Context.get(Naming.table(:prefabs), prefab) do
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
    aspects = Context.get(Naming.table(:objects), object)

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
    case Context.get(Naming.table(:objects), object) do
      nil ->
        {:reply, :noop, state}

      aspects ->
        Context.remove(Naming.table(:objects), object)
        Enum.each(aspects, &Context.remove(Naming.table(&1), object))
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:"$flush", _from, state) do
    pids =
      Genesis.Router
      |> PartitionSupervisor.which_children()
      |> Enum.map(fn {_, pid, _type, _} -> pid end)

    Logger.debug("Flushing partitions: #{inspect(pids)}")

    {:reply, Enum.flat_map(pids, &RPC.flush/1), state}
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
    RPC.dispatch({:via, PartitionSupervisor, {Genesis.Router, object}}, message)

    {:noreply, state}
  end

  defp start_router(opts) do
    # Router is the name we use for the partition supervisor that is responsible
    # for correctly segmenting all object events. See `Genesis.RPC` for more details.
    partitions = Keyword.get(opts, :partitions, System.schedulers_online())

    spec = Supervisor.child_spec(Genesis.RPC, shutdown: :brutal_kill)
    PartitionSupervisor.start_link(child_spec: spec, name: Genesis.Router, partitions: partitions)
  end

  defp upsert_object_aspect(object, aspect) do
    update_object_aspect(object, aspect)
    Context.add(Naming.table(aspect), object, aspect)
  end

  defp remove_object_aspect(object, aspect) do
    Context.remove(Naming.table(aspect), object)
    Context.update!(Naming.table(:objects), object, &without_aspect(&1, aspect))
  end

  defp update_object_aspect(object, new_aspect) do
    Context.update(Naming.table(:objects), object, [new_aspect], fn aspects ->
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
