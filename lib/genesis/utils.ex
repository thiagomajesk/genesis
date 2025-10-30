defmodule Genesis.Utils do
  @moduledoc false

  def aliasify(module) when is_atom(module) do
    module
    |> Module.split()
    |> List.last()
    |> to_string()
    |> String.downcase()
  end
end
