defmodule Genesis.Scribe do
  @moduledoc false

  use GenStage

  require Logger

  def start_link(args) do
    GenStage.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    herald = Access.get(args, :herald)
    partition = Access.get(args, :partition)

    {:consumer, %{}, subscribe_to: [{herald, partition: partition}]}
  end

  @impl true
  def handle_events(events, _from, state) do
    events
    |> Enum.group_by(& &1.object)
    |> Enum.each(&process_object_events/1)

    {:noreply, [], state}
  end

  defp process_object_events({object, events}) do
    Logger.debug("Processing #{length(events)} events for object #{inspect(object)}")
    Task.start(fn -> Enum.each(events, &Genesis.Event.process_event/1) end)
  end
end
