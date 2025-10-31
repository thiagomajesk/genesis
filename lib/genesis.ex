defmodule Genesis do
  use Application

  @impl true
  def start(_type, _args) do
    children = [Genesis.World, router(Genesis.Router)]
    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp router(name) do
    spec = Genesis.RPC.child_spec([])
    {PartitionSupervisor, child_spec: spec, name: name}
  end
end
