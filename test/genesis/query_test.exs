defmodule Genesis.QueryTest do
  use ExUnit.Case

  alias Genesis.World
  alias Genesis.Query
  alias Genesis.Aspects.Health
  alias Genesis.Aspects.Moniker
  alias Genesis.Aspects.Position

  setup do
    pid = start_supervised!(World)

    aspects = [Health, Moniker, Position]
    Enum.each(aspects, &World.register_aspect/1)

    {:ok, world: pid, aspects: aspects}
  end

  test "all_of/1" do
    object_1 = World.new()
    Health.attach(object_1, current: 100)
    Position.attach(object_1, x: 10, y: 20)
    Moniker.attach(object_1, name: "Object")

    object_2 = World.new()
    Health.attach(object_2, current: 50)
    Position.attach(object_2, x: 5, y: 15)

    assert [{^object_1, _}] = Query.all_of([Health, Position, Moniker])
  end

  test "any_of/1" do
    object_1 = World.new()
    Health.attach(object_1, current: 100)
    Position.attach(object_1, x: 10, y: 20)
    Moniker.attach(object_1, name: "Object")

    object_2 = World.new()
    Position.attach(object_2, x: 5, y: 15)

    assert [{^object_1, _}] = Query.any_of([Health, Moniker])
  end

  test "none_of/1" do
    object_1 = World.new()
    Moniker.attach(object_1, name: "Object")

    object_2 = World.new()
    Health.attach(object_2, current: 100)
    Position.attach(object_2, x: 10, y: 20)

    assert [{^object_1, _}] = Query.none_of([Health, Position])
  end

  test "query/1" do
    object_1 = World.new()
    Health.attach(object_1, current: 100)
    Position.attach(object_1, x: 10, y: 20)
    Moniker.attach(object_1, name: "Object")

    object_2 = World.new()
    Health.attach(object_2, current: 50)
    Position.attach(object_2, x: 5, y: 15)

    object_3 = World.new()
    Health.attach(object_3, current: 10)
    Moniker.attach(object_3, name: "Object")

    assert [{^object_3, _}] =
             Query.query(
               all: [Health],
               any: [Moniker],
               none: [Position]
             )
  end
end
