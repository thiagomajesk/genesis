defmodule Genesis.Scribe do
  @moduledoc false

  use ConsumerSupervisor

  require Logger

  def start_link(opts) do
    ConsumerSupervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    parent = Access.fetch!(opts, :parent)

    children = [
      %{
        id: :worker,
        start: {__MODULE__, :start_worker, [parent]},
        restart: :transient
      }
    ]

    ConsumerSupervisor.init(children, strategy: :one_for_one)
  end

  # What we receive here is not the individual event, but a batch of events for a particular
  # object that we need to process sequentially. This ensures that we can have separate "lanes"
  # for different objects that should be processed concurrently. When a worker finishes processing,
  # it notifies the Envoy that this object's "lane" is free so it sends more events to be processed.
  def start_worker(parent, {object, events}) do
    Logger.debug("Starting worker for object #{inspect(object)} with #{length(events)} events")

    # NOTE: Tasks needs to be linked otherwise ConsumerSupervisor
    # won't be able to monitor them exiting and request more demand.
    Task.start_link(fn ->
      try do
        Enum.each(events, &Genesis.Event.process/1)
      after
        send(parent, {:ack, object})
      end
    end)
  end
end
