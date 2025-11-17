defmodule Genesis.Context do
  @moduledoc false

  def init(table) do
    with :undefined <- :ets.whereis(table) do
      :ets.new(table, [
        :set,
        :named_table,
        read_concurrency: true
      ])
    end
  end

  def drop(table) do
    with true <- :ets.delete(table), do: :ok
  end

  def add(table, object, container) do
    with true <- :ets.insert(table, {object, container}), do: :ok
  end

  def get(table, object, default \\ nil) do
    case :ets.lookup(table, object) do
      [] -> default
      [{_object, container}] -> container
    end
  end

  def get!(table, object) do
    case get(table, object) do
      nil -> raise "object #{inspect(object)} not found in #{inspect(table)}"
      container -> container
    end
  end

  def remove(table, object) do
    with true <- :ets.delete(table, object), do: :ok
  end

  def update(table, object, default, fun) when is_function(fun, 1) do
    case get(table, object) do
      nil -> add(table, object, default)
      container -> add(table, object, fun.(container))
    end
  end

  def update!(table, object, fun) when is_function(fun, 1) do
    case get(table, object) do
      nil -> raise "object #{inspect(object)} not found in #{inspect(table)}"
      container -> add(table, object, fun.(container))
    end
  end

  def all(table) do
    :ets.tab2list(table)
  end

  def all(table, object) do
    table
    |> :ets.lookup(object)
    |> Enum.flat_map(&elem(&1, 1))
  end

  def match(table, props) do
    guards =
      Enum.map(props, fn {prop, value} ->
        {:==, {:map_get, prop, :"$2"}, value}
      end)

    :ets.select(table, [
      {
        {:"$1", :"$2"},
        [{:is_map, :"$2"} | guards],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  def exists?(table, object) do
    :ets.member(table, object)
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
end
