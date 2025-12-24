defmodule Genesis.Component do
  @moduledoc """
  Provides common behavior and callbacks for components.
  Components are modular pieces of state or behavior that can be attached to entities.
  """

  @type event :: Genesis.Event.t()
  @type props :: keyword() | map()
  @type entity :: reference()

  @optional_callbacks handle_event: 2

  @doc """
  Creates a new component by casting the given properties.
  The given properties are passed to the `cast/1` function.
  """
  @callback new(props()) :: struct()

  @doc """
  Called when a component is `:attached`, `:removed` or `:updated` on an entity.
  Receives the hook name, the entity, and the component struct that triggered the hook.
  """
  @callback on_hook(atom(), entity(), struct()) :: any()

  @doc """
  Casts the given properties into a map of permitted values.
  This function normalizes input that can be used to create a component.
  """
  @callback cast(props()) :: map()

  @doc """
  Attaches a component to an entity.
  Returns `:ok` if the component was successfully attached, `:noop` if a component with the same props
  is already attached, or `:error` if the same component with different props is already attached.
  """
  @callback attach(entity(), props()) :: :ok | :noop | :error

  @doc """
  Updates a component attached to an entity by merging the given properties.
  Will return `:noop` if the component is not present or `:error` if the component cannot be replaced.
  """
  @callback update(entity(), props()) :: :ok | :noop | :error

  @doc """
  Updates a specific property of a component attached to the entity.
  Will return `:noop` if the component is not present or `:error` if the property does not exist.
  """
  @callback update(entity(), atom(), fun()) :: :ok | :noop | :error

  @doc """
  Removes a component from an entity.
  Returns `:noop` if the component is not present.
  """
  @callback remove(entity()) :: :ok | :noop

  @doc """
  Handles events dispatched to this component via its parent entity.

  Given that the same event is dispatched to all components within an entity, this
  function should return a tuple with `:cont` or `:halt` to either keep processing
  the event or stop propagating the event to the remaining components in the pipeline.
  """
  @callback handle_event(atom(), event()) :: {:cont, event()} | {:halt, event()}

  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      @behaviour Genesis.Component

      @before_compile Genesis.Component

      @events Keyword.get(opts, :events, [])

      import Genesis.Value, only: [prop: 2, prop: 3]

      Genesis.Value.__setup__(__MODULE__, __ENV__.file, __ENV__.line)

      def new(attrs \\ []), do: struct!(__MODULE__, cast(attrs))

      def on_hook(hook, entity, component) when is_atom(hook), do: :ok

      defoverridable new: 0, new: 1, on_hook: 3
    end
  end

  defmacro __before_compile__(env) do
    quote do
      @valid_keys Enum.map(@properties, &elem(&1, 0))

      defstruct Genesis.Value.__defaults__(@properties)

      defguardp is_prop(prop) when is_atom(prop) and prop in @valid_keys

      defguardp is_props(props)
                when (is_list(props) and props != []) or
                       (is_non_struct_map(props) and props != %{})

      def __component__(:events), do: @events
      def __component__(:properties), do: @properties

      def cast(attrs), do: Genesis.Value.__cast__(attrs, @properties)

      def attach(entity), do: attach(entity, __MODULE__.new())

      def attach(entity, props) when is_props(props),
        do: attach(entity, __MODULE__.new(props))

      def attach(entity, %{__struct__: __MODULE__} = component),
        do: Genesis.Component.__attach__(:entities, __MODULE__, entity, component)

      def remove(entity),
        do: Genesis.Component.__remove__(:entities, __MODULE__, entity)

      def update(entity, props) when is_props(props),
        do: Genesis.Component.__update__(:entities, __MODULE__, entity, props)

      # We don't use a guard in this case because the return value has better semantics.
      # The query functions on the other hand need it because returning empty would have
      # two meanings: a) Invalid prop that will never match b) No entity actually matched.
      def update(entity, prop, fun) when is_atom(prop) and is_function(fun, 1),
        do: Genesis.Component.__update__(:entities, __MODULE__, entity, prop, fun)

      @doc """
      Returns all components of the given type.
      Returns a list of tuples containing the entity and the component struct.

      ## Examples

          iex> Health.all()
          [{1, %Health{current: 100}}, {2, %Health{current: 50}}]
      """
      def all(), do: Genesis.Query.__all__(:entities, __MODULE__)

      @doc """
      Retrieves the component attached to an entity.
      Returns the component struct if present or default.

      ## Examples

          iex> Health.get(1)
          %Health{current: 100}
      """
      def get(entity, default \\ nil),
        do: Genesis.Query.__get__(:entities, __MODULE__, entity, default)

      @doc """
      Returns all components that match the given properties.

      ## Examples

          iex> Moniker.match(name: "Tripida")
          [{1, %Moniker{name: "Tripida"}}]
      """
      def match(pairs),
        do: Genesis.Query.__match__(:entities, __MODULE__, pairs)

      @doc """
      Returns all components that have the given property with a value greater than or equal to the given minimum.

      ## Examples

          iex> Health.at_least(:current, 50)
          [{1, %Health{current: 75}}]
      """
      def at_least(prop, value) when is_prop(prop) and is_integer(value),
        do: Genesis.Query.__at_least__(:entities, __MODULE__, prop, value)

      @doc """
      Returns all components that have the given property with a value less than or equal to the given maximum.

      ## Examples

          iex> Health.at_most(:current, 50)
          [{1, %Health{current: 25}}]
      """
      def at_most(prop, value) when is_prop(prop) and is_integer(value),
        do: Genesis.Query.__at_most__(:entities, __MODULE__, prop, value)

      @doc """
      Returns all components that have the given property with a value between the given minimum and maximum (inclusive).

      ## Examples

          iex> Health.between(:current, 50, 100)
          [{1, %Health{current: 75}}]
      """
      def between(prop, min, max)
          when is_prop(prop) and is_integer(min) and is_integer(max) and min <= max,
          do: Genesis.Query.__between__(:entities, __MODULE__, prop, min, max)

      if @events == [] and Module.defines?(unquote(env.module), {:handle_event, 2}) do
        raise CompileError,
          file: unquote(env.file),
          line: unquote(env.line),
          description: """
          Component #{unquote(env.module)} defines handle_event/2 but does not specify any events.
          Please specify the events this component handles using `use Genesis.Component, events: [:event1, :event2]`.
          """
      end
    end
  end

  @doc false
  def __attach__(registry, component_type, entity, component) do
    case component_type.get(entity) do
      ^component ->
        :noop

      %{__struct__: ^component_type} ->
        :error

      nil ->
        case Genesis.Registry.emplace(registry, entity, component) do
          :ok ->
            component_type.on_hook(:attached, entity, component)
            :ok

          {:error, _reason} ->
            :error
        end
    end
  end

  @doc false
  def __remove__(registry, component_type, entity) do
    case component_type.get(entity) do
      nil ->
        :noop

      component ->
        case Genesis.Registry.erase(registry, entity, component_type) do
          :ok ->
            component_type.on_hook(:removed, entity, component)
            :ok

          {:error, _reason} ->
            :error
        end
    end
  end

  @doc false
  def __update__(registry, component_type, entity, properties) do
    case component_type.get(entity) do
      nil ->
        :noop

      component ->
        casted = component_type.cast(properties)
        updated = Map.merge(component, casted)

        case Genesis.Registry.replace(registry, entity, updated) do
          :ok ->
            component_type.on_hook(:updated, entity, updated)
            :ok

          {:error, _reason} ->
            :error
        end
    end
  end

  @doc false
  def __update__(registry, component_type, entity, property, fun) do
    case component_type.get(entity) do
      nil ->
        :noop

      %{^property => value} = component ->
        updated = Map.put(component, property, fun.(value))

        case Genesis.Registry.replace(registry, entity, updated) do
          :ok ->
            component_type.on_hook(:updated, entity, updated)
            :ok

          {:error, _reason} ->
            :error
        end

      _component ->
        :error
    end
  end
end
