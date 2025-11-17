defmodule Genesis.ContextTest do
  use ExUnit.Case, async: true

  alias Genesis.Context

  setup context do
    table = Module.concat(__MODULE__, context.test)

    {:ok, table: Context.init(table)}
  end

  test "add/3", %{table: table} do
    assert :ok = Context.add(table, :foo, "foo")
    assert "foo" = Context.get(table, :foo)
  end

  test "get/3", %{table: table} do
    Context.add(table, :foo, "foo")

    assert "foo" = Context.get(table, :foo)
    assert Context.get(table, :bar) == nil
    assert "bar" = Context.get(table, :bar, "bar")
  end

  test "get!/2", %{table: table} do
    Context.add(table, :foo, "foo")

    assert "foo" = Context.get!(table, :foo)
    assert_raise RuntimeError, fn -> Context.get!(table, :bar) end
  end

  test "remove/2", %{table: table} do
    Context.add(table, :foo, "foo")

    assert :ok = Context.remove(table, :foo)
    assert Context.get(table, :foo) == nil
  end

  test "update/4", %{table: table} do
    Context.add(table, :bar, 0)

    assert :ok = Context.update(table, :foo, 0, &(&1 + 1))
    assert 0 = Context.get(table, :foo)

    assert :ok = Context.update(table, :bar, 0, &(&1 + 1))
    assert 1 = Context.get(table, :bar)
  end

  test "update!/3", %{table: table} do
    Context.add(table, :foo, 0)

    assert :ok = Context.update!(table, :foo, &(&1 + 1))
    assert 1 = Context.get(table, :foo)

    assert_raise RuntimeError, fn ->
      Context.update!(table, :bar, &(&1 + 1))
    end
  end

  test "all/1", %{table: table} do
    Context.add(table, :foo, "foo")
    Context.add(table, :bar, "bar")
    Context.add(table, :baz, "baz")

    list = Context.all(table)
    assert [bar: "bar", baz: "baz", foo: "foo"] = Enum.sort(list)
  end

  test "all/2", %{table: table} do
    Context.add(table, :foo, ["foo1", "foo2", "foo3"])
    Context.add(table, :bar, ["bar1", "bar2", "bar3"])

    ["foo1", "foo2", "foo3"] = Context.all(table, :foo)
    ["bar1", "bar2", "bar3"] = Context.all(table, :bar)
  end

  test "match/2", %{table: table} do
    Context.add(table, :foo, %{starts_with: "f"})
    Context.add(table, :bar, %{starts_with: "b"})
    Context.add(table, :baz, %{starts_with: "b"})

    list = Context.match(table, %{starts_with: "f"})
    assert [foo: %{starts_with: "f"}] = Enum.sort(list)
  end

  test "exists?/2", %{table: table} do
    Context.add(table, :foo, "foo")

    assert Context.exists?(table, :foo)
    refute Context.exists?(table, :bar)
  end

  test "at_least/3", %{table: table} do
    Context.add(table, :foo, %{n: 1})
    Context.add(table, :bar, %{n: 2})
    Context.add(table, :baz, %{n: 3})

    list = Context.at_least(table, :n, 2)
    assert [bar: %{n: 2}, baz: %{n: 3}] = Enum.sort(list)
  end

  test "at_most/3", %{table: table} do
    Context.add(table, :foo, %{n: 1})
    Context.add(table, :bar, %{n: 2})
    Context.add(table, :baz, %{n: 3})

    list = Context.at_most(table, :n, 2)
    assert [bar: %{n: 2}, foo: %{n: 1}] = Enum.sort(list)
  end

  test "between/4", %{table: table} do
    Context.add(table, :foo, %{n: 1})
    Context.add(table, :bar, %{n: 2})
    Context.add(table, :baz, %{n: 3})

    list = Context.between(table, :n, 2, 3)
    assert [bar: %{n: 2}, baz: %{n: 3}] = Enum.sort(list)
  end
end
