defmodule Genesis.Event do
  @moduledoc """
  A struct representing an event that can be dispatched to entities.

  Events are the primary mechanism for triggering behavior in Genesis.
  When an event is sent to an entity, it will be processed by the components
  attached that have been registered to handle that specific event.

  ## Fields

    * `:name` - The unique event identifier
    * `:entity` - The target entity this event was sent to
    * `:world` - The world that dispatched the event
    * `:timestamp` - The event creation timestamp
    * `:args` - Additional event-specific data
    * `:handlers` - The list of modules that will handle the event
  """
  @derive {Inspect, only: [:name, :args]}
  @enforce_keys [:name, :world, :entity, :timestamp]
  defstruct [:name, :world, :entity, :timestamp, args: %{}, handlers: []]

  @type t :: %__MODULE__{
          name: atom(),
          world: pid(),
          entity: Genesis.Entity.t(),
          timestamp: integer(),
          args: map(),
          handlers: list(module())
        }

  @doc false
  def new(name, opts) do
    world = Keyword.fetch!(opts, :world)
    entity = Keyword.fetch!(opts, :entity)

    args = Keyword.get(opts, :args, %{})
    handlers = Keyword.get(opts, :handlers, [])

    %__MODULE__{
      args: args,
      name: name,
      world: world,
      entity: entity,
      handlers: handlers,
      timestamp: :erlang.system_time()
    }
  end

  @doc """
  Processes a list of events by invoking their respective handlers in order.
  Each handler can choose to continue processing the event or halt further processing.

  NOTE: This function is mostly used internally to process entity events. Calling it directly
  should be avoided unless you need to bypass the default event dispatching mechanism.
  """
  def process(event) when is_struct(event, __MODULE__) do
    checksum = checksum(event)

    Enum.reduce_while(event.handlers, event, fn module, event ->
      case maybe_handle_event(module, event) do
        {resp, event} when resp in [:cont, :halt] ->
          {resp, verify_checksum(event, checksum)}

        other ->
          raise "Invalid response #{inspect(other)} from #{inspect(module)}"
      end
    end)
  end

  defp maybe_handle_event(module, event) do
    if function_exported?(module, :handle_event, 2),
      do: module.handle_event(event.name, event),
      else: {:cont, event}
  end

  defp checksum(event) do
    # Only changes to args are allowed
    event = Map.delete(event, :args)
    :crypto.hash(:sha256, :erlang.term_to_binary(event))
  end

  defp verify_checksum(event, checksum) do
    if checksum(event) == checksum,
      do: event,
      else: raise("Event drifted during processing!")
  end
end
