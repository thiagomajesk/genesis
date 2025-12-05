defmodule Genesis.Event do
  @moduledoc """
  A struct representing an event that can be dispatched to entities.

  Events are the primary mechanism for triggering behavior in Genesis.
  When an event is sent to an entity, it will be processed by the components
  attached that have been registered to handle that specific event.

  ## Fields

    * `:name` - The unique event identifier
    * `:entity` - The target entity this event was sent to
    * `:world` - The world where the entity was spawned in
    * `:from` - The caller that sent the event to the entity
    * `:timestamp` - The event creation timestamp
    * `:args` - Additional event-specific data
    * `:handlers` - The list of modules that will handle the event
  """
  @enforce_keys [:name, :world, :entity, :from, :timestamp]
  defstruct [:name, :world, :entity, :from, :timestamp, args: %{}, handlers: []]

  @type t :: %__MODULE__{
          name: atom(),
          world: pid(),
          entity: Genesis.Entity.t(),
          from: pid(),
          timestamp: integer(),
          args: map(),
          handlers: list(module())
        }

  @doc """
  Processes a list of events by invoking their respective handlers in order.
  Each handler can choose to continue processing the event or halt further processing.

  NOTE: This function is mostly used internally to process entity events. Calling it directly
  should be avoided unless you need to bypass the default event dispatching mechanism.
  """
  def process(event) when is_struct(event, __MODULE__) do
    Enum.reduce_while(event.handlers, event, fn module, event ->
      case maybe_handle_event(module, event) do
        {resp, event} when resp in [:cont, :halt] -> {resp, event}
        other -> raise "Invalid response #{inspect(other)} from #{inspect(module)}"
      end
    end)
  end

  defp maybe_handle_event(module, event) do
    if function_exported?(module, :handle_event, 2),
      do: module.handle_event(event.name, event),
      else: {:cont, event}
  end
end
