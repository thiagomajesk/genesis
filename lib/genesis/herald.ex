defmodule Genesis.Herald do
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

    # Use same hashing strategy as PartitionSupervisor, so the same object is always
    # processed by the same partition (Scribe). The only difference from the default
    # `GenStage.PartitionDispatcher` implementation is that in our case the object is
    # the significant part of the event, so that's what we care about when hashing.
    hash = fn event ->
      if is_integer(event.object),
        do: {event, rem(abs(event.object), partitions)},
        else: {event, :erlang.phash2(event.object, partitions)}
    end

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
