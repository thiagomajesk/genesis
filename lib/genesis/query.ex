defmodule Genesis.Query do
  @moduledoc """
  Provides helper functions to query objects in the registry.
  """

  alias Genesis.Context
  alias Genesis.Naming

  @doc """
  Returns a list of objects that have all the aspects specified in the list.

  ## Examples

      iex> Query.all_of([Aspect1, Aspect2])
      [{1, [Aspect1, Aspect2]}, {2, [Aspect1, Aspect2]}]
  """
  def all_of(modules) when is_list(modules) do
    modules_lookup = MapSet.new(modules)

    :objects
    |> Naming.table()
    |> Context.stream()
    |> apply_filter(:all, modules_lookup)
    |> Enum.to_list()
  end

  @doc """
  Returns a list of objects that have at least one of the aspects specified in the list.

  ## Examples

      iex> Query.any_of([Aspect1, Aspect2])
      [{1, [Aspect1]}, {2, [Aspect2]}, {3, [Aspect1, Aspect2]}]
  """
  def any_of(modules) when is_list(modules) do
    modules_lookup = MapSet.new(modules)

    :objects
    |> Naming.table()
    |> Context.stream()
    |> apply_filter(:any, modules_lookup)
    |> Enum.to_list()
  end

  @doc """
  Returns a list of objects that do not have any of the aspects specified in the list.

  ## Examples

      iex> Query.none_of([Aspect1, Aspect2])
      [{3, [Aspect3, Aspect4]}, {4, [Aspect4, Aspect5]}]
  """
  def none_of(modules) when is_list(modules) do
    modules_lookup = MapSet.new(modules)

    :objects
    |> Naming.table()
    |> Context.stream()
    |> apply_filter(:none, modules_lookup)
    |> Enum.to_list()
  end

  @doc """
  Returns a list of objects that match the specified criteria.
  The function allows grouping the behavior of `all_of/1`, `any_of/1`, and `none_of/1`.

  ## Examples

      iex> Query.query(all: [Aspect1], any: [Aspect2], none: [Aspect3])
      [{1, [Aspect1, Aspect2]}, {2, [Aspect1]}]
  """
  def query(opts \\ []) do
    all = Keyword.get(opts, :all)
    any = Keyword.get(opts, :any)
    none = Keyword.get(opts, :none)

    all_lookup = all && MapSet.new(all)
    any_lookup = any && MapSet.new(any)
    none_lookup = none && MapSet.new(none)

    :objects
    |> Naming.table()
    |> Context.stream()
    |> apply_filter(:all, all_lookup)
    |> apply_filter(:any, any_lookup)
    |> apply_filter(:none, none_lookup)
    |> Enum.to_list()
  end

  defp apply_filter(stream, _filter, nil), do: stream

  defp apply_filter(stream, :all, lookup) do
    Stream.filter(stream, fn {_object, aspects} ->
      aspects_lookup = MapSet.new(Enum.map(aspects, & &1.__struct__))
      MapSet.subset?(lookup, aspects_lookup)
    end)
  end

  defp apply_filter(stream, :any, lookup) do
    Stream.filter(stream, fn {_object, aspects} ->
      aspects_lookup = MapSet.new(Enum.map(aspects, & &1.__struct__))
      not MapSet.disjoint?(lookup, aspects_lookup)
    end)
  end

  defp apply_filter(stream, :none, lookup) do
    Stream.filter(stream, fn {_object, aspects} ->
      aspects_lookup = MapSet.new(Enum.map(aspects, & &1.__struct__))
      MapSet.disjoint?(lookup, aspects_lookup)
    end)
  end
end
