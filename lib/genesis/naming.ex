defmodule Genesis.Naming do
  @moduledoc false
  # This module provides utility functions for the naming conventions used in Genesis.
  # In the future we want to use `ProcessTree` to create distinct names for ETS tables.
  # Which would allow us to run tests asynchronously and possibly remove some flaky tests.

  def server(module), do: module

  def table(:prefabs), do: :genesis_prefabs
  def table(:objects), do: :genesis_objects
  def table(%{__struct__: module}), do: module
  def table(other), do: other

  def alias(module) do
    module
    |> Module.split()
    |> List.last()
    |> to_string()
    |> String.downcase()
  end
end
