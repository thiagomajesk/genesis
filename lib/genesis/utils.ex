defmodule Genesis.Utils do
  @moduledoc false

  def alias(module) do
    module
    |> Module.split()
    |> List.last()
    |> to_string()
    |> String.downcase()
  end
end
