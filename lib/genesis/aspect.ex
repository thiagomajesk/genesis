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

  @optional_callbacks handle_event: 1

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
  Receives the event name, the object and a map of arguments for the event.

  Given that the same event is dispatched to all aspects within an object, this
  function should return a tuple with `:cont` or `:halt` to either keep processing
  the event or stop propagating the event to the remaining aspects in the pipeline.
  """
  @callback handle_event(event()) :: {:cont, event()} | {:halt, event()}

  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      @behaviour Aspect
      @before_compile Aspect

      @table __MODULE__
      @events Keyword.get(opts, :events, [])

      Module.register_attribute(__MODULE__, :properties, accumulate: true)

      defguard is_props(term) when is_list(term) or is_non_struct_map(term)

      import Genesis.Value, only: [prop: 2, prop: 3]

      def init() do
        opts = [:set, :named_table, read_concurrency: true]
        {Genesis.ETS.new(@table, opts), @events}
      end

      def new(attrs \\ []), do: struct!(__MODULE__, cast(attrs))

      def on_hook(hook, object, aspect) when is_atom(hook), do: :ok

      def attach(object), do: attach(object, %{})

      def attach(object, properties) when is_props(properties),
        do: attach(object, __MODULE__.new(properties))

      def attach(object, %{__struct__: __MODULE__} = aspect),
        do: Manager.attach_aspect(object, aspect)

      def remove(object), do: Manager.remove_aspect(object, __MODULE__)

      def replace(object, properties) when is_props(properties),
        do: Manager.replace_aspect(object, __MODULE__, properties)

      def update(object, property, fun) when is_atom(property) and is_function(fun, 1),
        do: Manager.update_aspect(object, __MODULE__, property, fun)

      def all(), do: ETS.list(@table)

      def get(object, default \\ nil), do: ETS.get(@table, object, default)

      def exists?(object), do: ETS.exists?(@table, object)

      def at_least(property, min) when is_integer(min) do
        ensure_props!([{property, min}])
        ETS.at_least(@table, property, min)
      end

      def at_most(property, max) when is_integer(max) do
        ensure_props!([{property, max}])
        ETS.at_most(@table, property, max)
      end

      def between(property, min, max) when is_integer(min) and is_integer(max) do
        ensure_props!([{property, min}, {property, max}])
        ETS.between(@table, property, min, max)
      end

      def match(properties) when is_props(properties) do
        ensure_props!(properties)
        ETS.match(@table, properties)
      end

      defoverridable new: 0, new: 1, on_hook: 3
    end
  end

  defmacro __before_compile__(env) do
    quote do
      defstruct Genesis.Value.defaults(@properties)

      def __aspect__(:table), do: @table
      def __aspect__(:events), do: @events
      def __aspect__(:properties), do: @properties

      if @events == [] and Module.defines?(unquote(env.module), {:handle_event, 1}) do
        raise CompileError,
          file: unquote(env.file),
          line: unquote(env.line),
          description: """
          Aspect #{unquote(env.module)} defines handle_event/1 but does not specify any events.
          Please specify the events this aspect handles using `use Genesis.Aspect, events: [:event1, :event2]`.
          """
      end

      def cast(attrs), do: Genesis.Value.cast(attrs, @properties)

      defp ensure_props!(pairs) do
        valid_props = Map.new(@properties, fn {name, type, _opts} -> {name, type} end)

        Enum.each(pairs, fn {property, value} ->
          case Map.fetch(valid_props, property) do
            {:ok, type} ->
              Genesis.Value.ensure_type!(value, type)

            :error ->
              raise ArgumentError,
                    """
                    The property #{inspect(property)} does not exist in aspect #{inspect(__MODULE__)}.
                    Perhaps you meant to use one of the following instead: #{inspect(Map.keys(valid_props))}
                    """
          end
        end)
      end
    end
  end
end
