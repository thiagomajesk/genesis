defmodule Genesis.ETS do
  @moduledoc """
  Module providing helpers for working with ETS tables in the Genesis framework.
  """

  @doc """
  Streams all entries from the given ETS table.
  """
  def stream(table) do
    Stream.resource(
      fn ->
        :ets.safe_fixtable(table, true)
        :ets.first(table)
      end,
      fn
        :"$end_of_table" ->
          {:halt, :"$end_of_table"}

        object ->
          case :ets.lookup(table, object) do
            [] -> {[], :ets.next(table, object)}
            entries -> {entries, :ets.next(table, object)}
          end
      end,
      fn _ ->
        :ets.safe_fixtable(table, false)
      end
    )
  end

  @doc """
  Groups entries in the ETS table by their keys.
  Returns a list of tuples where each tuple contains a key and a list of associated values.
  """
  def group_keys(table) do
    table
    |> Genesis.ETS.stream()
    |> Stream.transform(
      fn -> %{} end,
      fn {k, v}, acc -> {[], Map.update(acc, k, [v], &[v | &1])} end,
      fn acc -> {Enum.map(acc, fn {k, vs} -> {k, Enum.reverse(vs)} end), nil} end,
      fn _ -> nil end
    )
  end
end
