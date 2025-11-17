defmodule Genesis.Manager do
  @moduledoc """
  The Manager is a GenServer responsible for coordinating changes to the game registry.
  It ensures that all changes write operations are serialized to maintain consistency,
  and provides functions to register aspects and prefabs that will be used by the game.
  """
  use GenServer

  @events_table :genesis_events
  @aspects_table :genesis_aspects
  @prefabs_table :genesis_prefabs
  @objects_table :genesis_objects

  @doc """
  Returns the ETS table name used for the given registry.
  """
  def table(:events), do: @events_table
  def table(:aspects), do: @aspects_table
  def table(:prefabs), do: @prefabs_table
  def table(:objects), do: @objects_table

  def start_link(args \\ %{}) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc """
  List all aspects registered in the game.

      iex> Genesis.Manager.list_aspects()
      [{"health", Health}, {"position", Position}]
  """
  def list_aspects() do
    :ets.select(@aspects_table, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  end

  @doc """
  Lists all prefabs registered in the game.

      iex> Genesis.Manager.list_prefabs()
      [{"Being", %Genesis.Prefab{aspects: aspects}}]
  """
  def list_prefabs() do
    :ets.select(@prefabs_table, [{{:"$1", :"$2"}, [], [{{:"$1", :"$2"}}]}])
  end

  @doc """
  Registers an aspect module with an optional custom alias.

  Alias are useful to scope aspects in different domains.
  If only the module is provided, a default alias is used.

      iex> Genesis.Manager.register_aspect(Health)
      iex> Genesis.Manager.register_aspect({"prefix::health", Health})
  """
  def register_aspect(module_or_tuple)

  def register_aspect(module) when is_atom(module) do
    register_aspect({Genesis.Utils.aliasify(module), module})
  end

  def register_aspect({as, module}) when is_atom(module) do
    GenServer.call(__MODULE__, {:register_aspect, {as, module}})
  end

  @doc """
  Registers a new prefab definition.
  Prefabs are templates for creating objects with predefined aspects and properties.

      iex> Genesis.Manager.register_prefab(%{
      ...>   name: "Being",
      ...>   aspects: %{
      ...>     "health" => %{current: 100},
      ...>     "moniker" => %{name: "Being"}
      ...>   }
      ...> })

  Prefabs can also inherit from other prefabs to create complex object hierarchies.

      iex> Genesis.Manager.register_prefab(%{
      ...>   name: "Human",
      ...>   inherits: "Being",
      ...>   aspects: %{
      ...>     "moniker" => %{name: "Human"}
      ...>   }
      ...> })

  When a prefab inherits another, it will include all aspects of the parent prefab, allowing for reusable definitions.
  When loading prefabs, the aspects defined by a child prefab have precedence over those defined in the parent.
  """
  def register_prefab(attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:register_prefab, attrs})
  end

  @doc false
  def reset(timeout \\ :infinity) do
    GenServer.call(__MODULE__, :reset, timeout)
  end

  @doc false
  def attach_aspect(object, aspect) when is_struct(aspect) do
    GenServer.call(__MODULE__, {:attach_aspect, object, aspect})
  end

  @doc false
  def remove_aspect(object, module) when is_atom(module) do
    GenServer.call(__MODULE__, {:remove_aspect, object, module})
  end

  @doc false
  def replace_aspect(object, module, properties) when is_atom(module) do
    GenServer.call(__MODULE__, {:replace_aspect, object, module, properties})
  end

  @doc false
  def update_aspect(object, module, property, fun) when is_atom(module) do
    GenServer.call(__MODULE__, {:update_aspect, object, module, property, fun})
  end

  @impl true
  def init(_args) do
    Genesis.ETS.new(@objects_table, [:bag, :named_table])
    Genesis.ETS.new(@prefabs_table, [:set, :named_table])

    Genesis.ETS.new(@events_table, [:ordered_set, :named_table])
    Genesis.ETS.new(@aspects_table, [:ordered_set, :named_table])

    {:ok, %{aspects_tables: []}}
  end

  @impl true
  def handle_call({:register_aspect, {as, module}}, _from, state) do
    {table, events} = initialize_aspect!(module)

    :ets.insert(@aspects_table, {as, module, events})

    Enum.each(events, fn event ->
      Genesis.ETS.update(@events_table, event, [{as, module}], fn handlers ->
        Enum.uniq(handlers ++ [{as, module}])
      end)
    end)

    {:reply, :ok, Map.update!(state, :aspects_tables, &[table | &1])}
  end

  @impl true
  def handle_call({:register_prefab, attrs}, _from, state) do
    prefab =
      Genesis.Prefab.load(attrs,
        registered_aspects: list_aspects(),
        registered_prefabs: list_prefabs()
      )

    Genesis.ETS.put(@prefabs_table, prefab.name, prefab)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:attach_aspect, object, aspect}, _from, state) do
    module = Map.fetch!(aspect, :__struct__)

    case module.get(object) do
      ^aspect ->
        {:reply, :noop, state}

      %{__struct__: ^module} ->
        {:reply, :error, state}

      nil ->
        Genesis.ETS.put(@objects_table, object, aspect)
        Genesis.ETS.put(aspect.__struct__, object, aspect)

        module.on_hook(:attached, object, aspect)

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:remove_aspect, object, module}, _from, state) do
    case module.get(object) do
      nil ->
        {:reply, :noop, state}

      %{__struct__: ^module} = aspect ->
        :ets.delete_object(@objects_table, {object, aspect})
        Genesis.ETS.delete(module, object)

        module.on_hook(:removed, object, aspect)

        {:reply, :ok, state}

      _other ->
        {:reply, :error, state}
    end
  end

  @impl true
  def handle_call({:replace_aspect, object, module, properties}, _from, state) do
    case module.get(object) do
      nil ->
        {:reply, :noop, state}

      %{__struct__: ^module} = aspect ->
        casted = module.cast(properties)
        updated = Map.merge(aspect, casted)
        replace_aspect!(object, updated)

        module.on_hook(:replaced, object, updated)

        {:reply, :ok, state}

      _other ->
        {:reply, :error, state}
    end
  end

  @impl true
  def handle_call({:update_aspect, object, module, property, fun}, _from, state) do
    case module.get(object) do
      nil ->
        {:reply, :noop, state}

      %{^property => value} = aspect ->
        updated = Map.put(aspect, property, fun.(value))
        replace_aspect!(object, updated)

        module.on_hook(:updated, object, updated)

        {:reply, :ok, state}

      _aspect ->
        {:reply, :error, state}
    end
  end

  @impl true
  def handle_call(:reset, _from, state) do
    Genesis.ETS.clear(@objects_table)
    Genesis.ETS.clear(@prefabs_table)
    Genesis.ETS.clear(@events_table)
    Genesis.ETS.clear(@aspects_table)

    Enum.each(state.aspects_tables, &Genesis.ETS.drop/1)

    {:reply, :ok, %{state | aspects_tables: []}}
  end

  defp initialize_aspect!(module) do
    if not Genesis.Utils.aspect?(module),
      do: raise("Invalid aspect #{inspect(module)}"),
      else: module.init()
  end

  defp replace_aspect!(object, aspect) do
    module = Map.fetch!(aspect, :__struct__)

    :ets.match_delete(@objects_table, {object, %{__struct__: module}})
    Genesis.ETS.put(@objects_table, object, aspect)
    Genesis.ETS.put(module, object, aspect)
  end
end
