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
    |> to_string()
    |> String.downcase()
  end

  def aspect?(module) when is_atom(module) do
    attributes = module.__info__(:attributes)
    Genesis.Aspect in Access.get(attributes, :behaviour, [])
  end
end
