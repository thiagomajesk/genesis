defmodule Genesis.Component do
  @moduledoc """
  Provides common behavior and callbacks for components.
  Components are modular pieces of state and behavior that can be attached to entities.
  """

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
  @callback on_hook(atom(), Genesis.Entity.t(), struct()) :: any()

  @doc """
  Casts the given properties into a map of permitted values.
  This function normalizes input that can be used to create a component.
  """
  @callback cast(properties()) :: map()

  @doc """
  Attaches a component to an entity.
  If the entity belongs to a world, the attachment is performed within the world's context.

  Returns `:ok` if the component was successfully attached, `:noop` if a component with the same properties
  is already attached, or `:error` if the same component with different properties is already attached.
  """
  @callback attach(Genesis.Entity.t(), properties()) :: :ok | :noop | :error

  @doc """
  Retrieves a component from an entity.

  Returns the component struct if present or the default value.
  """
  @callback get(Genesis.Entity.t(), any()) :: struct() | any()

  @doc """
  Updates a component attached to an entity by merging the given properties.
  If the entity belongs to a world, the update is performed within the world's context.

  Will return `:noop` if the component is not present or `:error` if the component cannot be replaced.
  """
  @callback update(Genesis.Entity.t(), properties()) :: :ok | :noop | :error

  @doc """
  Updates a specific property of a component attached to the entity.
  If the entity belongs to a world, the update is performed within the world's context.

  Will return `:noop` if the component is not present or `:error` if the property does not exist.
  """
  @callback update(Genesis.Entity.t(), atom(), fun()) :: :ok | :noop | :error

  @doc """
  Removes a component from an entity.
  If the entity belongs to a world, the removal is performed within the world's context.

  Returns `:noop` if the component is not present.
  """
  @callback remove(Genesis.Entity.t()) :: :ok | :noop

  @doc """
  Handles events dispatched to this component via its parent entity.

  Given that the same event is dispatched to all components within an entity, this
  function should return a tuple with `:cont` or `:halt` to either keep processing
  the event or stop propagating the event to the remaining components in the pipeline.
  """
  @callback handle_event(atom(), Genesis.Event.t()) ::
              {:cont, Genesis.Event.t()} | {:halt, Genesis.Event.t()}

  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      @behaviour Genesis.Component

      @before_compile Genesis.Component

      @events Keyword.get(opts, :events, [])
      @name Keyword.get(opts, :name, Genesis.Utils.aliasify(__MODULE__))

      import Genesis.Value, only: [prop: 2, prop: 3]
      import Genesis.Utils, only: [is_non_empty_pairs: 1]

      Genesis.Value.__setup__(__MODULE__, __ENV__.file, __ENV__.line)

      def new(attrs \\ []), do: struct!(__MODULE__, cast(attrs))

      def on_hook(hook, entity, component) when is_atom(hook), do: :ok

      defoverridable new: 0, new: 1, on_hook: 3
    end
  end

  defmacro __before_compile__(env) do
    quote do
      defstruct Genesis.Value.__defaults__(@properties)

      def __component__(:name), do: @name
      def __component__(:events), do: @events
      def __component__(:properties), do: @properties

      def cast(attrs) when is_list(attrs) or is_non_struct_map(attrs),
        do: Genesis.Component.__cast__(attrs, @properties)

      def attach(%Genesis.Entity{} = entity),
        do: attach(entity, __MODULE__.new())

      def attach(%Genesis.Entity{} = entity, properties) when is_non_empty_pairs(properties),
        do: attach(entity, __MODULE__.new(properties))

      def attach(%Genesis.Entity{} = entity, component) when is_struct(component, __MODULE__),
        do: Genesis.Component.__attach__(__MODULE__, entity, component)

      def get(%Genesis.Entity{} = entity, default \\ nil),
        do: Genesis.Component.__get__(__MODULE__, entity, default)

      def remove(%Genesis.Entity{} = entity),
        do: Genesis.Component.__remove__(__MODULE__, entity)

      def update(%Genesis.Entity{} = entity, properties) when is_non_empty_pairs(properties),
        do: Genesis.Component.__update__(__MODULE__, entity, properties)

      def update(%Genesis.Entity{} = entity, property, fun) when is_function(fun, 1),
        do: Genesis.Component.__update__(__MODULE__, entity, property, fun)

      if not is_binary(@name) do
        raise CompileError,
          file: unquote(env.file),
          line: unquote(env.line),
          description: """
          Component #{unquote(env.module)} has an invalid name. Expected a string, got: #{inspect(@name)}
          Please specify the name as a string: `use Genesis.Component, name: "my_component"`.
          """
      end

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
  def __cast__(attrs, properties) do
    Genesis.Value.cast(attrs, properties)
  rescue
    e in ArgumentError ->
      reraise ArgumentError, "[#{inspect(__MODULE__)}] #{Exception.message(e)}", __STACKTRACE__
  end

  @doc false
  def __get__(component_type, entity, default) do
    cond do
      is_pid(entity.context) and Process.alive?(entity.context) ->
        Genesis.Context.get(entity.context, entity, component_type, default)

      true ->
        raise ArgumentError,
              "cannot get component #{inspect(component_type)} from entity #{inspect(entity)}. " <>
                "The entity's context is not available"
    end
  end

  @doc false
  def __attach__(component_type, entity, component) do
    case component_type.get(entity) do
      ^component ->
        :noop

      %{__struct__: ^component_type} ->
        :error

      nil ->
        do_attach(component_type, entity, component)
    end
  end

  @doc false
  def __remove__(component_type, entity) do
    case component_type.get(entity) do
      nil ->
        :noop

      component ->
        do_remove(component_type, entity, component)
    end
  end

  @doc false
  def __update__(component_type, entity, properties) do
    case component_type.get(entity) do
      nil ->
        :noop

      component ->
        casted = component_type.cast(properties)
        updated = Map.merge(component, casted)
        do_update(component_type, entity, updated)
    end
  end

  @doc false
  def __update__(component_type, entity, property, fun) do
    case component_type.get(entity) do
      nil ->
        :noop

      %{^property => value} = component ->
        updated = Map.put(component, property, fun.(value))
        do_update(component_type, entity, updated)

      _component ->
        :error
    end
  end

  defp do_attach(component_type, %{world: nil} = entity, component) do
    case Genesis.Context.emplace(entity.context, entity, component) do
      :ok ->
        invoke_hook(component_type, :attached, entity, component)
        :ok

      {:error, _reason} ->
        :error
    end
  end

  defp do_attach(component_type, entity, component) do
    fun = &Genesis.Context.emplace(&1, entity, component)

    case Genesis.World.context(entity.world, fun) do
      :ok ->
        invoke_hook(component_type, :attached, entity, component)
        :ok

      {:error, _reason} ->
        :error
    end
  end

  defp do_update(component_type, %{world: nil} = entity, updated) do
    case Genesis.Context.replace(entity.context, entity, updated) do
      :ok ->
        invoke_hook(component_type, :updated, entity, updated)
        :ok

      {:error, _reason} ->
        :error
    end
  end

  defp do_update(component_type, entity, updated) do
    fun = &Genesis.Context.replace(&1, entity, updated)

    case Genesis.World.context(entity.world, fun) do
      :ok ->
        invoke_hook(component_type, :updated, entity, updated)
        :ok

      {:error, _reason} ->
        :error
    end
  end

  defp do_remove(component_type, %{world: nil} = entity, component) do
    case Genesis.Context.erase(entity.context, entity, component_type) do
      :ok ->
        invoke_hook(component_type, :removed, entity, component)
        :ok

      {:error, _reason} ->
        :error
    end
  end

  defp do_remove(component_type, entity, component) do
    fun = &Genesis.Context.erase(&1, entity, component_type)

    case Genesis.World.context(entity.world, fun) do
      :ok ->
        invoke_hook(component_type, :removed, entity, component)
        :ok

      {:error, _reason} ->
        :error
    end
  end

  defp invoke_hook(component_type, hook, entity, component) do
    args = [hook, entity, component]

    Task.Supervisor.async_nolink(
      Genesis.TaskSupervisor,
      component_type,
      :on_hook,
      args
    )
  end
end
