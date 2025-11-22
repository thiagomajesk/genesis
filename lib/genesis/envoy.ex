defmodule Genesis.Envoy do
  @moduledoc false
  use GenStage
  require Logger

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl true
  def init(_opts) do
    {:producer_consumer, %{}}
  end

  @impl true
  def handle_events(events, _from, state) do
    Logger.info("Envoy events #{inspect(length(events))}")
    {:noreply, events, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, [], state}
  end
end
