defmodule Genesis.Utils do
  @moduledoc false

  case Application.compile_env(:genesis, :object_ids, :integer) do
    :reference -> def object_id(), do: make_ref()
    :integer -> def object_id(), do: System.unique_integer([:positive, :monotonic])
    other -> raise "Invalid option given to :object_ids: #{inspect(other)}"
  end

  def aliasify(module) when is_atom(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  def component?(module) when is_atom(module) do
    attributes = module.__info__(:attributes)
    # NOTE: For some reason, we get two keys for :behaviour
    behaviours = Keyword.get_values(attributes, :behaviour)
    Genesis.Component in List.flatten(behaviours)
  end
end
