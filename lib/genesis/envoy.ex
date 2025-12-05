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
    # Grouping events by entity ensures that we can process different batches
    # concurrently while maintaining the order of events for the same entity.
    groups = Enum.group_by(events, & &1.entity)

    # Then, we check if a worker is already processing events for that entity (busy).
    # If there are none, we can emit events for processing right away. Otherwise,
    # events are queued until the worker "acks" that a batch has been processed.
    {to_emit, state} =
      Enum.reduce(groups, {[], state}, fn {entity, events}, {to_emit, state} ->
        case Map.get(state, entity) do
          nil ->
            queue = :queue.new()
            new_state = Map.put(state, entity, {:busy, queue})
            {[{entity, events} | to_emit], new_state}

          {:busy, queue} ->
            queue = :queue.in(events, queue)
            {to_emit, Map.put(state, entity, {:busy, queue})}
        end
      end)

    {:noreply, Enum.reverse(to_emit), state}
  end

  @impl true
  def handle_info({:ack, entity}, state) do
    # When a worker acknowledges that it has finished processing a batch for an entity,
    # we check if there are more events queued up for that entity. If so, we emit the next
    # batch for processing right away. Otherwise, we "free" the entity from the queue.
    case Map.pop(state, entity) do
      {nil, state} ->
        {:noreply, [], state}

      {{:busy, queue}, state} ->
        case :queue.out(queue) do
          {:empty, _queue} ->
            {:noreply, [], state}

          {{:value, events}, queue} ->
            state = Map.put(state, entity, {:busy, queue})
            {:noreply, [{entity, events}], state}
        end
    end
  end
end
