defmodule Genesis do
  use Application

  @impl true
  def start(_type, _args) do
    children = [Genesis.Manager]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
