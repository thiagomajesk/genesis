defmodule Genesis.Aspect do
  @moduledoc """
  Provides common behavior and callbacks for aspects.
  Aspects are modular pieces of state or behavior that can be attached to objects.
  """
  alias __MODULE__
  alias Genesis.World
  alias Genesis.Context
  alias Genesis.Naming

  require Logger

  @type object :: integer() | atom() | binary()
  @type props :: Enumerable.t()

  @doc """
  Initializes the aspect ETS table.
  Should return an atom with the name of the table and a list of events.
  """
  @callback init() :: {atom() | list(atom())}

  @doc """
  Creates a new aspect by casting the given properties.
  The given properties are passed to the `cast/1` function.
  """
  @callback new(props()) :: struct()

  @doc """
  Casts the given properties into a map of permitted values.
  This function normalizes input that can be used to create an aspect.
  """
  @callback cast(props()) :: map()

  @doc """
  Attaches an aspect to an object.
  """
  @callback attach(object(), props()) :: :ok

  @doc """
  Updates an aspect attached to an object.
  Will return `:noop` if the aspect is not present.
  """
  @callback update(object(), props()) :: :ok | :noop

  @doc """
  Removes an aspect from an object.
  Returns `:noop`  if the aspect is not present.
  """
  @callback remove(object()) :: :ok | :noop

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
  Returns all aspects of the given type.
  Returns a list of tuples containing the object and the aspect struct.

  ## Examples

      iex> Health.all()
      [{1, %Health{current: 100}}, {2, %Health{current: 50}}]
  """
  @callback all() :: list({object(), struct()})

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
  Returns all aspects that have the given property with a value between the given minimum and maximum.

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
  @callback handle_event(atom(), object(), map()) ::
              {:cont, map()} | {:halt, map()}

  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      @behaviour Aspect
      @before_compile Aspect

      @events Keyword.get(opts, :events, [])

      import Genesis.Value

      Module.register_attribute(__MODULE__, :properties, accumulate: true)

      def init() do
        table = Naming.table(__MODULE__)
        {Context.init(table), @events}
      end

      def new(attrs \\ []), do: struct!(__MODULE__, cast(attrs))

      def attach(object), do: attach(object, %{})

      def attach(object, properties) when is_props(properties),
        do: attach(object, __MODULE__.new(properties))

      def attach(object, %{__struct__: __MODULE__} = aspect),
        do: World.send(object, :"$attach", aspect)

      def remove(object) do
        table = Naming.table(__MODULE__)

        case Context.get(table, object) do
          nil -> :noop
          aspect -> World.send(object, :"$remove", aspect)
        end
      end

      def update(object, properties) when is_props(properties) do
        permitted = cast(properties)

        table = Naming.table(__MODULE__)

        case Context.get(table, object) do
          nil -> :noop
          aspect -> World.send(object, :"$update", Map.merge(aspect, permitted))
        end
      end

      def get(object, default \\ nil) do
        table = Naming.table(__MODULE__)
        Context.get(table, object, default)
      end

      def all(), do: Context.all(Naming.table(__MODULE__))

      def exists?(object) do
        table = Naming.table(__MODULE__)
        Context.exists?(table, object)
      end

      def at_least(property, min) do
        table = Naming.table(__MODULE__)
        Context.at_least(table, property, min)
      end

      def at_most(property, max) do
        table = Naming.table(__MODULE__)
        Context.at_most(table, property, max)
      end

      def between(property, min, max) do
        table = Naming.table(__MODULE__)
        Context.between(table, property, min, max)
      end

      def match(properties) when is_props(properties) do
        table = Naming.table(__MODULE__)
        Context.match(table, properties)
      end

      def handle_event(event, _object, args), do: {:cont, args}

      defoverridable handle_event: 3, new: 0, new: 1
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      defstruct to_fields(@properties)

      def cast(attrs), do: cast(attrs, @properties)
    end
  end
end
