defmodule Genesis.Event do
  @moduledoc """
  Defines the structure and processing of events within the Genesis framework.
  Events represent actions affecting objects in the system and contain information about
  their origin, target object, and associated data which can be processed by handlers.
  """
  @enforce_keys [:name, :world, :object, :from, :timestamp]
  defstruct [:name, :world, :object, :from, :timestamp, args: %{}, handlers: []]

  alias __MODULE__

  def process_event(%Event{} = event) do
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
