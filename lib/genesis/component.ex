defmodule Genesis.Component do
  @moduledoc """
  Provides common behavior and callbacks for components.
  Components are modular pieces of state or behavior that can be attached to entities.
  """

  import Genesis.Utils, only: [is_handle: 1]

  @type event :: Genesis.Event.t()
  @type entity :: reference()
  @type properties :: keyword() | map()

  @optional_callbacks handle_event: 2

  @doc """
  Creates a new component by casting the given properties.
  The given properties are passed to the `cast/1` function.
  """
  @callback new(properties()) :: struct()

  @doc """
  Called when a component is `:attached`, `:removed` or `:updated` on an entity.
  Receives the hook name, the entity, and the component struct that triggered the hook.
  """
  @callback on_hook(atom(), entity(), struct()) :: any()

  @doc """
  Casts the given properties into a map of permitted values.
  This function normalizes input that can be used to create a component.
  """
  @callback cast(properties()) :: map()

  @doc """
  Attaches a component to an entity.
  Returns `:ok` if the component was successfully attached, `:noop` if a component with the same properties
  is already attached, or `:error` if the same component with different properties is already attached.
  """
  @callback attach(entity(), properties()) :: :ok | :noop | :error

  @doc """
  Updates a component attached to an entity by merging the given properties.
  Will return `:noop` if the component is not present or `:error` if the component cannot be replaced.
  """
  @callback update(entity(), properties()) :: :ok | :noop | :error

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
      @valid_properties Enum.map(@properties, &elem(&1, 0))
      @integer_properties Genesis.Component.__properties__(@properties, :integer)

      defstruct Genesis.Value.__defaults__(@properties)

      defguardp is_property(property) when is_atom(property) and property in @valid_properties

      defguardp is_integer_property(property)
                when is_property(property) and property in @integer_properties

      defguardp is_min_max(min, max) when is_integer(min) and is_integer(max) and min <= max

      defguardp is_non_empty_pairs(properties)
                when (is_list(properties) and properties != []) or
                       (is_non_struct_map(properties) and properties != %{})

      def __component__(:events), do: @events
      def __component__(:properties), do: @properties

      def cast(attrs) when is_list(attrs) or is_non_struct_map(attrs),
        do: Genesis.Component.__cast__(attrs, @properties)

      def attach(entity) when is_reference(entity),
        do: attach(entity, __MODULE__.new())

      def attach(entity, properties) when is_reference(entity) and is_non_empty_pairs(properties),
        do: attach(entity, __MODULE__.new(properties))

      def attach(entity, component)
          when is_reference(entity) and is_struct(component, __MODULE__),
          do: Genesis.Component.__attach__(:entities, __MODULE__, entity, component)

      def remove(entity) when is_reference(entity),
        do: Genesis.Component.__remove__(:entities, __MODULE__, entity)

      def update(entity, properties) when is_reference(entity) and is_non_empty_pairs(properties),
        do: Genesis.Component.__update__(:entities, __MODULE__, entity, properties)

      # We don't use a guard in this case because the return value has better semantics.
      # The query functions on the other hand need it because returning empty would have
      # two meanings: a) Invalid property that will never match b) No entity actually matched.
      def update(entity, property, fun) when is_reference(entity) and is_function(fun, 1),
        do: Genesis.Component.__update__(:entities, __MODULE__, entity, property, fun)

      @doc """
      Returns all components of the given type.
      Returns a list of tuples containing the entity and the component struct.

      ## Examples

          iex> Health.all()
          [{entity_1, %Health{current: 100}}, {entity_2, %Health{current: 50}}]
      """
      def all(), do: Genesis.Query.__all__(:entities, __MODULE__)

      @doc """
      Retrieves the component attached to an entity.
      Returns the component struct if present or default.

      ## Examples

          iex> Health.get(entity_1)
          %Health{current: 100}
      """
      def get(entity, default \\ nil) when is_reference(entity),
        do: Genesis.Query.__get__(:entities, __MODULE__, entity, default)

      @doc """
      Returns all components that match the given properties.

      ## Examples

          iex> Moniker.match(name: "Tripida")
          [{entity_1, %Moniker{name: "Tripida"}}]
      """
      def match(properties) when is_non_empty_pairs(properties),
        do: Genesis.Query.__match__(:entities, __MODULE__, properties)

      @doc """
      Returns all components that have the given property with a value greater than or equal to the given minimum.

      ## Examples

          iex> Health.at_least(:current, 50)
          [{entity_1, %Health{current: 75}}]
      """
      def at_least(property, value) when is_integer_property(property) and is_integer(value),
        do: Genesis.Query.__at_least__(:entities, __MODULE__, property, value)

      @doc """
      Returns all components that have the given property with a value less than or equal to the given maximum.

      ## Examples

          iex> Health.at_most(:current, 50)
          [{entity_1, %Health{current: 25}}]
      """
      def at_most(property, value) when is_integer_property(property) and is_integer(value),
        do: Genesis.Query.__at_most__(:entities, __MODULE__, property, value)

      @doc """
      Returns all components that have the given property with a value between the given minimum and maximum (inclusive).

      ## Examples

          iex> Health.between(:current, 50, 100)
          [{entity_1, %Health{current: 75}}]
      """
      def between(property, min, max)
          when is_integer_property(property) and is_min_max(min, max),
          do: Genesis.Query.__between__(:entities, __MODULE__, property, min, max)

      @doc """
      Checks if an entity exists in the entities registry.
      Returns `true` if found, or `false` otherwise.
      """
      def exists?(entity_or_name) when is_handle(entity_or_name),
        do: Genesis.Query.__exists__(:entities, entity_or_name)

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
  def __properties__(properties, type) do
    Enum.reduce(properties, [], fn
      {name, ^type, _opts}, acc -> [name | acc]
      {_name, _type, _opts}, acc -> acc
    end)
  end

  @doc false
  def __cast__(attrs, properties) do
    Genesis.Value.cast(attrs, properties)
  rescue
    e in ArgumentError ->
      reraise ArgumentError, "[#{inspect(__MODULE__)}] #{Exception.message(e)}", __STACKTRACE__
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
            invoke_hook(component_type, :attached, entity, component)

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
            invoke_hook(component_type, :removed, entity, component)

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
        do_update(registry, component_type, entity, updated)
    end
  end

  @doc false
  def __update__(registry, component_type, entity, property, fun) do
    case component_type.get(entity) do
      nil ->
        :noop

      %{^property => value} = component ->
        updated = Map.put(component, property, fun.(value))
        do_update(registry, component_type, entity, updated)

      _component ->
        :error
    end
  end

  defp do_update(registry, component_type, entity, updated) do
    case Genesis.Registry.replace(registry, entity, updated) do
      :ok ->
        invoke_hook(component_type, :updated, entity, updated)

      {:error, _reason} ->
        :error
    end
  end

  defp invoke_hook(component_type, hook, entity, component) do
    sup = Genesis.TaskSupervisor
    args = [hook, entity, component]
    task = Task.Supervisor.async_nolink(sup, component_type, :on_hook, args)
    with _result <- Task.await(task), do: :ok
  end
end
