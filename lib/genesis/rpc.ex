defmodule Genesis.RPC do
  @moduledoc false
  # This module is responsible for dispatching events to object's aspects.
  # It uses a GenServer to handle the dispatching of events, ensuring that events
  # are processed sequentially for the same object (usually the registration order).
  # This module is mainly used by the World GenServer to offload work and avoid deadlocks
  # when aspects also need to send events to other objects after handling events themselves.

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, hibernate_after: 5_000)
  end

  def flush(server, timeout \\ :infinity) do
    GenServer.call(server, :"$flush", timeout)
  end

  # Dispatches an event to an object and its aspects.
  # The message is expected to be a tuple of 4 elements containing
  # the event name, arguments, the object, and a list of modules for
  # the aspects that are registered to handle the event being dispatched.
  def dispatch(server, {event, args, object, modules}) do
    GenServer.cast(server, {event, args, object, modules})
  end

  @impl true
  def init(_args), do: {:ok, %{events: []}}

  @impl true
  def handle_call(:"$flush", _from, state) do
    {:reply, Enum.reverse(state.events), %{state | events: []}}
  end

  @impl true
  def handle_cast({event, args, object, modules}, state) do
    Enum.reduce_while(modules, args, fn module, args ->
      case maybe_handle_event(module, event, object, args) do
        {resp, args} when resp in [:cont, :halt] -> {resp, args}
        other -> raise "Invalid response #{inspect(other)} from #{inspect(module)}"
      end
    end)

    {:noreply, Map.update!(state, :events, &[{event, object} | &1])}
  end

  defp maybe_handle_event(module, event, object, args) do
    if function_exported?(module, :handle_event, 3),
      do: module.handle_event(event, object, args),
      else: {:cont, args}
  end
end
