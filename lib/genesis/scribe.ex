defmodule Genesis.Scribe do
  @moduledoc false

  use ConsumerSupervisor

  require Logger

  def start_link(opts) do
    ConsumerSupervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(_opts) do
    children = [
      %{
        id: :worker,
        start: {__MODULE__, :start_worker, []},
        restart: :transient
      }
    ]

    ConsumerSupervisor.init(children, strategy: :one_for_one)
  end

  def start_worker(batch) do
    # Differently from the Envoy, what we receive here is not the invidiual event,
    # but a batch of events for a particular object that needs to be processed sequentially.
    Task.start_link(Genesis.Event, :process, [batch])
  end
end
