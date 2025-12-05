defmodule Genesis.ETS do
  @moduledoc """
  This module provides useful helpers for working with ETS tables.
  """

  @doc """
  Streams all entries from the given ETS table.
  """
  def stream(table, transform \\ & &1) do
    start_fun = fn ->
      :ets.safe_fixtable(table, true)
      :ets.first(table)
    end

    next_fun = fn
      :"$end_of_table" ->
        {:halt, :"$end_of_table"}

      entity ->
        case :ets.lookup(table, entity) do
          [] ->
            {[], :ets.next(table, entity)}

          objects ->
            entries = Enum.map(objects, transform)
            {entries, :ets.next(table, entity)}
        end
    end

    after_fun = fn _ ->
      :ets.safe_fixtable(table, false)
    end

    Stream.resource(start_fun, next_fun, after_fun)
  end

  @doc """
  Groups entries in the ETS table by their keys.
  Returns a stream of tuples containing the key and all values.
  """
  def group_keys(table) do
    table
    |> stream()
    |> Stream.transform(
      fn -> %{} end,
      fn {k, v}, acc -> {[], Map.update(acc, k, [v], &[v | &1])} end,
      fn acc -> {Enum.map(acc, fn {k, vs} -> {k, Enum.reverse(vs)} end), nil} end,
      fn _ -> nil end
    )
  end
end
