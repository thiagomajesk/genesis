defmodule Genesis.Aspect do
  @moduledoc """
  Provides common behavior and callbacks for aspects.
  Aspects are modular pieces of state or behavior that can be attached to objects.
  """
  alias __MODULE__
  alias Genesis.ETS
  alias Genesis.Manager

  @type event :: Genesis.Event.t()
  @type props :: keyword() | map()
  @type object :: integer() | atom() | binary()

  @optional_callbacks handle_event: 2

  @doc """
  Initializes the aspect ETS table.
  Should return an atom with the name of the table and a list of events.
  """
  @callback init() :: {:ets.tid(), list(atom())}

  @doc """
  Creates a new aspect by casting the given properties.
  The given properties are passed to the `cast/1` function.
  """
  @callback new(props()) :: struct()

  @doc """
  Called when an aspect is attached, removed, replaced, or updated on an object.
  Receives the hook name, the object, and the aspect struct that triggered the hook.
  """
  @callback on_hook(atom(), object(), struct()) :: any()

  @doc """
  Casts the given properties into a map of permitted values.
  This function normalizes input that can be used to create an aspect.
  """
  @callback cast(props()) :: map()

  @doc """
  Attaches an aspect to an object.
  Returns `:ok` if the aspect was successfully attached, `:noop` if an aspect with the same props
  is already attached, or `:error` if the same aspect with different props is already attached.
  """
  @callback attach(object(), props()) :: :ok | :noop | :error

  @doc """
  Replaces an aspect attached to an object.
  Will return `:noop` if the aspect is not present.
  """
  @callback replace(object(), props()) :: :ok | :noop

  @doc """
  Updates a specific property of an aspect attached to the object.
  Will return `:noop` if the aspect is not present or `:error` if the property does not exist.
  """
  @callback update(object(), atom(), fun()) :: :ok | :noop | :error

  @doc """
  Removes an aspect from an object.
  Returns `:noop`  if the aspect is not present.
  """
  @callback remove(object()) :: :ok | :noop

  @doc """
  Returns all aspects of the given type.
  Returns a list of tuples containing the object and the aspect struct.

  ## Examples

      iex> Health.all()
      [{1, %Health{current: 100}}, {2, %Health{current: 50}}]
  """
  @callback all() :: list({object(), struct()})

  @doc """
  Retrieves the aspect attached to an object.
  Returns the aspect struct if present or `nil`.

  ## Examples

      iex> Health.get(1)
      %Health{current: 100}
  """
  @callback get(object()) :: struct() | nil

  @doc """
  Same as `get/1`, but returns a default value if the aspect is not present.
  """
  @callback get(object(), any()) :: struct() | any()

  @doc """
  Returns true if the aspect is attached to the given object.
  """
  @callback exists?(object()) :: boolean()

  @doc """
  Returns all aspects that have the given property with a value greater than or equal to the given minimum.

  ## Examples

      iex> Health.at_least(:current, 50)
      [{1, %Health{current: 75}}]
  """
  @callback at_least(atom(), integer()) :: list({object(), struct()})

  @doc """
  Returns all aspects that have the given property with a value less than or equal to the given maximum.

  ## Examples

      iex> Health.at_most(:current, 50)
      [{1, %Health{current: 25}}]
  """
  @callback at_most(atom(), integer()) :: list({object(), struct()})

  @doc """
  Returns all aspects that have the given property with a value between the given minimum and maximum (inclusive).

  ## Examples

      iex> Health.between(:current, 50, 100)
      [{1, %Health{current: 75}}]
  """
  @callback between(atom(), integer(), integer()) :: list({object(), struct()})

  @doc """
  Returns all aspects that match the given properties.

  ## Examples

      iex> Moniker.match(name: "Tripida")
      [{1, %Moniker{name: "Tripida"}}]
  """
  @callback match(props()) :: list({object(), struct()})

  @doc """
  Handles events dispatched to this aspect via its parent object.

  Given that the same event is dispatched to all aspects within an object, this
  function should return a tuple with `:cont` or `:halt` to either keep processing
  the event or stop propagating the event to the remaining aspects in the pipeline.
  """
  @callback handle_event(atom(), event()) :: {:cont, event()} | {:halt, event()}

  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      @behaviour Aspect
      @before_compile Aspect

      @table __MODULE__
      @events Keyword.get(opts, :events, [])

      import Genesis.Value, only: [prop: 2, prop: 3]

      Genesis.Value.__setup__(__MODULE__, __ENV__.file, __ENV__.line)

      def init() do
        opts = [:set, :named_table, read_concurrency: true]
        {Genesis.ETS.new(@table, opts), @events}
      end

      def new(attrs \\ []), do: struct!(__MODULE__, cast(attrs))

      def on_hook(hook, object, aspect) when is_atom(hook), do: :ok

      defoverridable new: 0, new: 1, on_hook: 3
    end
  end

  defmacro __before_compile__(env) do
    quote do
      @valid_keys Enum.map(@properties, &elem(&1, 0))

      defguardp is_prop(prop) when is_atom(prop) and prop in @valid_keys

      defguardp is_props(props)
                when (is_list(props) and props != []) or
                       (is_non_struct_map(props) and props != %{})

      defstruct Genesis.Value.__defaults__(@properties)

      def __aspect__(:table), do: @table
      def __aspect__(:events), do: @events
      def __aspect__(:properties), do: @properties

      def cast(attrs), do: Genesis.Value.__cast__(attrs, @properties)

      def attach(object), do: attach(object, __MODULE__.new())

      def attach(object, props) when is_props(props),
        do: attach(object, __MODULE__.new(props))

      def attach(object, %{__struct__: __MODULE__} = aspect),
        do: Manager.attach_aspect(object, aspect)

      def remove(object), do: Manager.remove_aspect(object, __MODULE__)

      def replace(object, props) when is_props(props),
        do: Manager.replace_aspect(object, __MODULE__, props)

      # We don't use a guard in this case because the return value has better semantics.
      # The query functions on the other hand need it because returning empty would have
      # two meanings: a) Invalid prop that will never match b) No object actually matched.
      def update(object, prop, fun) when is_atom(prop) and is_function(fun, 1),
        do: Manager.update_aspect(object, __MODULE__, prop, fun)

      def all(), do: :ets.tab2list(@table)

      def exists?(object), do: :ets.member(@table, object)

      def get(object, default \\ nil), do: ETS.get(@table, object, default)

      def match(prop) when is_props(prop), do: Aspect.__match__(@table, prop)

      def at_least(prop, min) when is_prop(prop) and is_integer(min),
        do: Aspect.__at_least__(@table, prop, min)

      def at_most(prop, max) when is_prop(prop) and is_integer(max),
        do: Aspect.__at_most__(@table, prop, max)

      def between(prop, min, max)
          when is_prop(prop) and is_integer(min) and is_integer(max) and min <= max,
          do: Aspect.__between__(@table, prop, min, max)

      if @events == [] and Module.defines?(unquote(env.module), {:handle_event, 2}) do
        raise CompileError,
          file: unquote(env.file),
          line: unquote(env.line),
          description: """
          Aspect #{unquote(env.module)} defines handle_event/2 but does not specify any events.
          Please specify the events this aspect handles using `use Genesis.Aspect, events: [:event1, :event2]`.
          """
      end
    end
  end

  @doc false
  def __match__(table, pairs) do
    guards =
      Enum.map(pairs, fn {key, value} ->
        {:==, {:map_get, key, :"$2"}, value}
      end)

    :ets.select(table, [
      {
        {:"$1", :"$2"},
        [{:is_map, :"$2"} | guards],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  @doc false
  def __at_least__(table, key, value) do
    :ets.select(table, [
      {
        {:"$1", :"$2"},
        [
          {:is_map, :"$2"},
          {:>=, {:map_get, key, :"$2"}, value}
        ],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  @doc false
  def __at_most__(table, key, value) do
    :ets.select(table, [
      {
        {:"$1", :"$2"},
        [
          {:is_map, :"$2"},
          {:"=<", {:map_get, key, :"$2"}, value}
        ],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  @doc false
  def __between__(table, key, min, max) do
    :ets.select(table, [
      {
        {:"$1", :"$2"},
        [
          {:is_map, :"$2"},
          {:"=<", {:map_get, key, :"$2"}, max},
          {:>=, {:map_get, key, :"$2"}, min}
        ],
        [{{:"$1", :"$2"}}]
      }
    ])
  end
end
