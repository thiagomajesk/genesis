defmodule Genesis.Naming do
  @moduledoc false
  # This module provides utility functions for the naming conventions used in Genesis.
  # In the future we want to use `ProcessTree` to create distinct names for ETS tables.
  # Which would allow us to run tests asynchronously and possibly remove some flaky tests.

  def alias(module) do
    module
    |> Module.split()
    |> List.last()
    |> to_string()
    |> String.downcase()
  end
end
