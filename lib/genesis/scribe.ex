defmodule Genesis.Scribe do
  @moduledoc false

  use GenStage

  require Logger

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    herald = Access.fetch!(opts, :herald)
    partition = Access.fetch!(opts, :partition)
    max_events = Access.fetch!(opts, :max_events)

    subscribe_opts = [partition: partition, max_demand: max_events]
    {:consumer, %{}, subscribe_to: [{herald, subscribe_opts}]}
  end

  @impl true
  def handle_events(events, _from, state) do
    events
    |> Enum.group_by(& &1.object)
    |> Enum.map(&process_events_async/1)
    |> Task.await_many()

    {:noreply, [], state}
  end

  defp process_events_async({object, events}) do
    Logger.debug("Processing #{length(events)} events for object #{inspect(object)}")
    Task.async(fn -> Enum.each(events, &Genesis.Event.process_event/1) end)
  end
end
