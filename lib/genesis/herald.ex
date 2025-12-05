defmodule Genesis.Herald do
  @moduledoc false
  use GenStage

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  def notify(server, event) do
    GenStage.cast(server, {:notify, event})
  end

  @impl true
  def init(opts) do
    partitions = Access.fetch!(opts, :partitions)

    hash = &{&1, :erlang.phash2(&1.entity.hash, partitions)}

    {:producer, {:queue.new(), 0},
     dispatcher: {GenStage.PartitionDispatcher, partitions: partitions, hash: hash}}
  end

  @impl true
  def handle_cast({:notify, event}, {queue, pending_demand}) do
    queue = :queue.in(event, queue)
    dispatch_events(queue, pending_demand, [])
  end

  @impl true
  def handle_demand(incoming_demand, {queue, pending_demand}) do
    dispatch_events(queue, incoming_demand + pending_demand, [])
  end

  defp dispatch_events(queue, 0, events) do
    {:noreply, Enum.reverse(events), {queue, 0}}
  end

  defp dispatch_events(queue, demand, events) do
    case :queue.out(queue) do
      {{:value, event}, queue} ->
        dispatch_events(queue, demand - 1, [event | events])

      {:empty, queue} ->
        {:noreply, Enum.reverse(events), {queue, demand}}
    end
  end
end
