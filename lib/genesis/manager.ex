defmodule Genesis.Manager do
  use GenServer

  @events_table :genesis_events
  @aspects_table :genesis_aspects
  @prefabs_table :genesis_prefabs
  @objects_table :genesis_objects

  def table(:events), do: @events_table
  def table(:aspects), do: @aspects_table
  def table(:prefabs), do: @prefabs_table
  def table(:objects), do: @objects_table

  def start_link(args \\ %{}) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc """
  List all aspects registered with their respective aliases in order of registration.
  """
  def list_aspects() do
    :ets.select(@aspects_table, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  end

  def list_prefabs() do
    :ets.select(@prefabs_table, [{{:"$1", :"$2"}, [], [{{:"$1", :"$2"}}]}])
  end

  @doc """
  Registers an aspect module.
  """
  def register_aspect(module_or_tuple)

  def register_aspect(module) when is_atom(module) do
    register_aspect({Genesis.Utils.aliasify(module), module})
  end

  def register_aspect({as, module}) do
    GenServer.call(__MODULE__, {:register_aspect, {as, module}})
  end

  @doc """
  Registers a new prefab.
  """
  def register_prefab(attrs) do
    GenServer.call(__MODULE__, {:register_prefab, attrs})
  end

  @doc false
  def reset(timeout \\ :infinity) do
    GenServer.call(__MODULE__, :reset, timeout)
  end

  @doc false
  def attach_aspect(object, aspect) do
    GenServer.call(__MODULE__, {:attach_aspect, object, aspect})
  end

  @doc false
  def remove_aspect(object, aspect) do
    GenServer.call(__MODULE__, {:remove_aspect, object, aspect})
  end

  @doc false
  def replace_aspect(object, aspect) do
    GenServer.call(__MODULE__, {:replace_aspect, object, aspect})
  end

  @impl true
  def init(_args) do
    :ets.new(@objects_table, [:bag, :named_table])
    :ets.new(@prefabs_table, [:set, :named_table])

    :ets.new(@events_table, [:ordered_set, :named_table])
    :ets.new(@aspects_table, [:ordered_set, :named_table])

    {:ok, %{aspects_tables: []}}
  end

  @impl true
  def handle_call({:register_aspect, {as, module}}, _from, state) do
    {table, events} = initialize_aspect!(module)

    :ets.insert(@aspects_table, {as, module, events})
    Enum.each(events, &push_event_handler(&1, {as, module}))

    {:reply, :ok, Map.update!(state, :aspects_tables, &[table | &1])}
  end

  @impl true
  def handle_call({:register_prefab, attrs}, _from, state) do
    prefab =
      Genesis.Prefab.load(attrs,
        registered_aspects: list_aspects(),
        registered_prefabs: list_prefabs()
      )

    :ets.insert(@prefabs_table, {prefab.name, prefab})

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:attach_aspect, object, aspect}, _from, state) do
    :ets.insert(@objects_table, {object, aspect})
    Genesis.Context.add(aspect.__struct__, object, aspect)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:remove_aspect, object, aspect}, _from, state) do
    :ets.delete_object(@objects_table, {object, aspect})
    Genesis.Context.remove(aspect.__struct__, object)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:replace_aspect, object, aspect}, _from, state) do
    :ets.match_delete(@objects_table, {object, %{__struct__: aspect.__struct__}})
    :ets.insert(@objects_table, {object, aspect})
    Genesis.Context.add(aspect.__struct__, object, aspect)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(@objects_table)
    :ets.delete_all_objects(@prefabs_table)
    :ets.delete_all_objects(@events_table)
    :ets.delete_all_objects(@aspects_table)

    Enum.each(state.aspects_tables, &Genesis.Context.drop/1)

    {:reply, :ok, %{state | aspects_tables: []}}
  end

  defp initialize_aspect!(module) do
    if not Genesis.Utils.aspect?(module),
      do: raise("Invalid aspect #{inspect(module)}"),
      else: module.init()
  end

  defp push_event_handler(event, {as, module}) do
    case :ets.lookup(@events_table, event) do
      [] ->
        :ets.insert(@events_table, {event, [{as, module}]})

      [{^event, handlers}] ->
        updated = handlers ++ [{as, module}]
        :ets.insert(@events_table, {event, updated})
    end
  end
end
