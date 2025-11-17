defmodule Genesis.Event do
  @moduledoc """
  A struct representing an event that can be dispatched to objects.

  Events are the primary mechanism for triggering behavior in Genesis.
  When an event is sent to an object, it will be processed by the aspects
  attached that have been registered to handle that specific event.

  ## Fields

    * `:name` - The unique event identifier
    * `:object` - The target object this event was sent to
    * `:world` - The world where of the object was spawned in
    * `:from` - The caller that sent the event to the object
    * `:timestamp` - The event creation timestamp
    * `:args` - Additional event-specific data
    * `:handlers` - The list of modules that will handle the event
  """
  @enforce_keys [:name, :world, :object, :from, :timestamp]
  defstruct [:name, :world, :object, :from, :timestamp, args: %{}, handlers: []]

  @doc """
  Processes a list of events by invoking their respective handlers in order.
  Each handler can choose to continue processing the event or halt further processing.

  NOTE: This function is mostly used internally to process object events and calling it directly
  should be avoided unless there's a specific need to bypass the default event dispatching mechanism.
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
    if function_exported?(module, :handle_event, 1),
      do: module.handle_event(event),
      else: {:cont, event}
  end
end
