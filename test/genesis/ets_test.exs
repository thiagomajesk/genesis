defmodule Genesis.ETSTest do
  use ExUnit.Case, async: true

  alias Genesis.ETS
  alias Genesis.Context

  setup context do
    table = Module.concat(__MODULE__, context.test)

    {:ok, table: Context.init(table)}
  end

  test "stream/1", %{table: table} do
    Context.add(table, :foo, "foo")
    Context.add(table, :bar, "bar")
    Context.add(table, :baz, "baz")

    list = Enum.to_list(ETS.stream(table))
    assert [bar: "bar", baz: "baz", foo: "foo"] = Enum.sort(list)
  end
end
