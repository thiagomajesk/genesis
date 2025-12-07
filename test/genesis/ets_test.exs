defmodule Genesis.ETSTest do
  use ExUnit.Case, async: true

  alias Genesis.ETS

  test "get/3" do
    table = ETS.new(:table, [:set])

    ETS.put(table, :foo, "foo")

    assert "foo" = ETS.get(table, :foo)
    assert ETS.get(table, :bar) == nil
    assert "bar" = ETS.get(table, :bar, "bar")
  end

  test "add/3" do
    table = ETS.new(:table, [:set])

    assert :ok = ETS.put(table, :foo, "foo")
    assert "foo" = ETS.get(table, :foo)
  end

  test "get!/2" do
    table = ETS.new(:table, [:set])

    ETS.put(table, :foo, "foo")

    assert "foo" = ETS.get!(table, :foo)
    assert_raise RuntimeError, fn -> ETS.get!(table, :bar) end
  end

  test "remove/2" do
    table = ETS.new(:table, [:set])

    ETS.put(table, :foo, "foo")

    assert :ok = ETS.delete(table, :foo)
    assert ETS.get(table, :foo) == nil
  end

  test "update/4" do
    table = ETS.new(:table, [:set])

    ETS.put(table, :bar, 0)

    assert :ok = ETS.update(table, :foo, 0, &(&1 + 1))
    assert 0 = ETS.get(table, :foo)

    assert :ok = ETS.update(table, :bar, 0, &(&1 + 1))
    assert 1 = ETS.get(table, :bar)
  end

  test "update!/3" do
    table = ETS.new(:table, [:set])

    ETS.put(table, :foo, 0)

    assert :ok = ETS.update!(table, :foo, &(&1 + 1))
    assert 1 = ETS.get(table, :foo)

    assert_raise RuntimeError, fn ->
      ETS.update!(table, :bar, &(&1 + 1))
    end
  end

  test "drop/1" do
    table = ETS.new(:table, [:set, :named_table])

    ETS.put(table, :foo, "foo")
    assert :ok = ETS.drop(table)
    assert :ets.whereis(table) == :undefined
  end

  test "stream/1" do
    table = ETS.new(:table, [:set])

    ETS.put(table, :foo, "foo")
    ETS.put(table, :bar, "bar")
    ETS.put(table, :baz, "baz")

    list = Enum.to_list(ETS.stream(table))
    assert [bar: "bar", baz: "baz", foo: "foo"] = Enum.sort(list)
  end
end
