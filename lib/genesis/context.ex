defmodule Genesis.Context do
  @moduledoc false

  def init(table) do
    :ets.new(table, [:named_table, :set, write_concurrency: true])
  end

  def drop(table) do
    :ets.delete(table) && :ok
  end

  def add(table, key, value) do
    :ets.insert(table, {key, value}) && :ok
  end

  def get(table, key, default \\ nil) do
    case :ets.lookup(table, key) do
      [] -> default
      [{_key, value}] -> value
    end
  end

  def remove(table, key) do
    :ets.delete(table, key)
  end

  def update(table, key, default, fun) when is_function(fun, 1) do
    case get(table, key) do
      nil -> add(table, key, default)
      values -> add(table, key, fun.(values))
    end
  end

  def update!(table, key, fun) when is_function(fun, 1) do
    case get(table, key) do
      nil -> raise "key #{inspect(key)} not found in #{inspect(table)}"
      values -> add(table, key, fun.(values))
    end
  end

  def all(table) do
    :ets.tab2list(table)
  end

  def all(table, key) do
    table
    |> :ets.lookup(key)
    |> Enum.flat_map(&elem(&1, 1))
  end

  def match(table, props) do
    guards =
      for {prop, value} <- props do
        {:==, {:map_get, prop, :"$2"}, value}
      end

    :ets.select(table, [
      {
        {:"$1", :"$2"},
        [{:is_map, :"$2"} | guards],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  def exists?(table, key) do
    :ets.member(table, key)
  end

  def at_least(table, prop, value) do
    :ets.select(table, [
      {
        {:"$1", :"$2"},
        [
          {:is_map, :"$2"},
          {:>=, {:map_get, prop, :"$2"}, value}
        ],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  def at_most(table, prop, value) do
    :ets.select(table, [
      {
        {:"$1", :"$2"},
        [
          {:is_map, :"$2"},
          {:"=<", {:map_get, prop, :"$2"}, value}
        ],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  def between(table, prop, min, max) do
    :ets.select(table, [
      {
        {:"$1", :"$2"},
        [
          {:is_map, :"$2"},
          {:"=<", {:map_get, prop, :"$2"}, max},
          {:>=, {:map_get, prop, :"$2"}, min}
        ],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  def stream(table) do
    Stream.resource(
      fn ->
        :ets.safe_fixtable(table, true)
        :ets.first(table)
      end,
      fn
        :"$end_of_table" ->
          {:halt, :"$end_of_table"}

        key ->
          case :ets.lookup(table, key) do
            [{^key, value}] -> {[{key, value}], :ets.next(table, key)}
            [] -> {[], :ets.next(table, key)}
          end
      end,
      fn _ ->
        :ets.safe_fixtable(table, false)
      end
    )
  end
end
