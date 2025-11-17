defmodule Genesis.Envoy do
  @moduledoc false

  use GenStage

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl true
  def init(_opts) do
    {:producer_consumer, %{}}
  end

  @impl true
  def handle_events(events, _from, state) do
    # Grouping events by object ensures that we can process different batches
    # concurrently while maintaining the order of events for the same object.
    groups = Enum.group_by(events, & &1.object)

    # Then, we check if a worker is already processing events for that object (busy).
    # If there are none, we can emit events for processing right away. Otherwise,
    # events are queued until the worker "acks" that a batch has been processed.
    {to_emit, state} =
      Enum.reduce(groups, {[], state}, fn {object, events}, {to_emit, state} ->
        case Map.get(state, object) do
          nil ->
            queue = :queue.new()
            new_state = Map.put(state, object, {:busy, queue})
            {[{object, events} | to_emit], new_state}

          {:busy, queue} ->
            queue = :queue.in(events, queue)
            {to_emit, Map.put(state, object, {:busy, queue})}
        end
      end)

    {:noreply, Enum.reverse(to_emit), state}
  end

  @impl true
  def handle_info({:ack, object}, state) do
    # When a worker acknowledges that it has finished processing a batch for an object,
    # we check if there are more events queued up for that object. If so, we emit the next
    # batch for processing right away. Otherwise, we "free" the object from the queue.
    case Map.pop(state, object) do
      {nil, state} ->
        {:noreply, [], state}

      {{:busy, queue}, state} ->
        case :queue.out(queue) do
          {:empty, _queue} ->
            {:noreply, [], state}

          {{:value, events}, queue} ->
            state = Map.put(state, object, {:busy, queue})
            {:noreply, [{object, events}], state}
        end
    end
  end
end
