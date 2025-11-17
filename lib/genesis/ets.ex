defmodule Genesis.ETS do
  @moduledoc """
  This module provides useful helpers for working with ETS tables.
  """

  @doc """
  Creates a new ETS table with the given name and options.
  If the table already exists, returns the existing table id.
  """
  def new(table, opts) do
    with :undefined <- :ets.whereis(table) do
      :ets.new(table, opts)
    end
  end

  @doc """
  Deletes all entries from the given ETS table.
  """
  def clear(table), do: :ets.delete_all_objects(table)

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

  @doc """
  Deletes the entire ETS table.
  """
  def drop(table) do
    with true <- :ets.delete(table), do: :ok
  end

  @doc """
  Inserts or updates an entry in the table.
  """
  def put(table, key, value) do
    with true <- :ets.insert(table, {key, value}), do: :ok
  end

  @doc """
  Retrieves the value for an entry with the given key.
  Returns the default value if the entry does not exist.
  """
  def get(table, key, default \\ nil) do
    case :ets.lookup(table, key) do
      [] -> default
      [{_key, value}] -> value
    end
  end

  @doc """
  Retrieves the value for an entry with the given key.
  Raises if the entry doesn't exist.
  """
  def get!(table, key) do
    case get(table, key) do
      nil -> raise "key #{inspect(key)} not found in #{inspect(table)}"
      value -> value
    end
  end

  @doc """
  Deletes the entry with the given key from the table.
  """
  def delete(table, key) do
    with true <- :ets.delete(table, key), do: :ok
  end

  @doc """
  Updates the value for an entry with the given key using a function.
  Inserts the default value if the entry doesn't exist.
  """
  def update(table, key, default, fun) when is_function(fun, 1) do
    case get(table, key) do
      nil -> put(table, key, default)
      value -> put(table, key, fun.(value))
    end
  end

  @doc """
  Updates the value for an entry with the given key using a function.
  Raises if the entry with the given key doesn't exist.
  """
  def update!(table, key, fun) when is_function(fun, 1) do
    case get(table, key) do
      nil -> raise "key #{inspect(key)} not found in #{inspect(table)}"
      value -> put(table, key, fun.(value))
    end
  end

  @doc """
  Returns all entries in the table as a list of tuples.
  """
  def list(table), do: :ets.tab2list(table)

  @doc """
  Retrieves all values for a given entry key.
  """
  def fetch(table, key) do
    table
    |> :ets.lookup(key)
    |> Enum.flat_map(&elem(&1, 1))
  end

  @doc """
  Finds all entries where the value is a map matching the given key-value pairs.
  """
  def match(table, pairs) do
    guards =
      Enum.map(pairs, fn {key, value} ->
        {:==, {:map_get, key, :"$2"}, value}
      end)

    :ets.select(table, [
      {
        {:"$1", :"$2"},
        [{:is_map, :"$2"} | guards],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  @doc """
  Checks if an entry with the given key exists in the table.
  """
  def exists?(table, key), do: :ets.member(table, key)

  @doc """
  Finds all entries where the value is a map with the given key greater than or equal to the value.
  """
  def at_least(table, key, value) do
    :ets.select(table, [
      {
        {:"$1", :"$2"},
        [
          {:is_map, :"$2"},
          {:>=, {:map_get, key, :"$2"}, value}
        ],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  @doc """
  Finds all entries where the value is a map with the given key less than or equal to the value.
  """
  def at_most(table, key, value) do
    :ets.select(table, [
      {
        {:"$1", :"$2"},
        [
          {:is_map, :"$2"},
          {:"=<", {:map_get, key, :"$2"}, value}
        ],
        [{{:"$1", :"$2"}}]
      }
    ])
  end

  @doc """
  Finds all entries where the value is a map with the given key between min and max.
  """
  def between(table, key, min, max) do
    :ets.select(table, [
      {
        {:"$1", :"$2"},
        [
          {:is_map, :"$2"},
          {:"=<", {:map_get, key, :"$2"}, max},
          {:>=, {:map_get, key, :"$2"}, min}
        ],
        [{{:"$1", :"$2"}}]
      }
    ])
  end
end
