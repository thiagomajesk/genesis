defmodule Genesis.AspectTest do
  use ExUnit.Case

  alias Genesis.World
  alias Genesis.Aspects.Health
  alias Genesis.Aspects.Moniker
  alias Genesis.Aspects.Position
  alias Genesis.Aspects.Selectable

  setup do
    pid = start_supervised!(World)

    aspects = [Health, Moniker, Position, Selectable]
    Enum.each(aspects, &World.register_aspect/1)

    {:ok, world: pid, aspects: aspects}
  end

  test "new/0" do
    assert %Health{} = Health.new()
    assert %Moniker{} = Moniker.new()
    assert %Position{} = Position.new()
    assert %Selectable{} = Selectable.new()
  end

  test "new/1" do
    assert %Health{current: 100} = Health.new(current: 100)
    assert %Moniker{name: "Object"} = Moniker.new(name: "Object")
    assert %Position{x: 10, y: 20} = Position.new(x: 10, y: 20)
    assert %Selectable{} = Selectable.new(%{})
  end

  describe "attach/1" do
    test "with a map" do
      object = World.new()

      Health.attach(object, %{current: 100})

      assert [%Health{current: 100}] = World.fetch(object)
    end

    test "with a keyword list" do
      object = World.new()

      Health.attach(object, current: 100)

      assert [%Health{current: 100}] = World.fetch(object)
    end

    test "with a struct" do
      object = World.new()

      Health.attach(object, %Health{current: 100})

      assert [%Health{current: 100}] = World.fetch(object)
    end
  end

  test "get/1" do
    object = World.new()

    Health.attach(object, current: 100)

    refute Moniker.get(object)
    assert %Health{current: 100} = Health.get(object)
  end

  test "get/2" do
    object = World.new()

    Health.attach(object, current: 100)

    assert :default = Moniker.get(object, :default)
    assert %Health{current: 100} = Health.get(object)
  end

  test "remove/1" do
    object = World.new()

    Health.attach(object, current: 100)
    Moniker.attach(object, name: "Object")
    Position.attach(object, x: 10, y: 20)

    Health.remove(object)
    refute Health.get(object)
  end

  test "update/2" do
    object = World.new()

    Health.attach(object, current: 100)

    Health.update(object, current: 50)
    assert %Health{current: 50} = Health.get(object)
    assert :noop = Moniker.update(object, name: "New Name")
  end

  test "update/3" do
    object = World.new()

    Health.attach(object, current: 100)

    Health.update(object, :current, &(&1 - 25))
    assert %Health{current: 75} = Health.get(object)
    assert :noop = Moniker.update(object, name: "New Name")
    assert :error = Health.update(object, :foo, &(&1 + 10))
  end

  test "all/1" do
    object_1 = World.new()
    object_2 = World.new()
    object_3 = World.new()

    Health.attach(object_1, current: 100)
    Health.attach(object_2, current: 100)
    Health.attach(object_3, current: 100)

    result = Enum.map(Health.all(), &elem(&1, 0))
    assert [object_1, object_2, object_3] == Enum.sort(result)
  end

  test "exists?/1" do
    object = World.new()

    Health.attach(object, current: 100)

    assert Health.exists?(object)
    assert not Moniker.exists?(object)
  end

  test "at_least/2" do
    object_1 = World.new()
    object_2 = World.new()

    Health.attach(object_1, current: 10)
    Health.attach(object_2, current: 50)

    assert [{^object_2, _}] = Health.at_least(:current, 50)
  end

  test "at_most/2" do
    object_1 = World.new()
    object_2 = World.new()

    Health.attach(object_1, current: 10)
    Health.attach(object_2, current: 50)

    assert [{^object_1, _}] = Health.at_most(:current, 10)
  end

  test "between/3" do
    object_1 = World.new()
    object_2 = World.new()

    Health.attach(object_1, current: 10)
    Health.attach(object_2, current: 50)

    assert [{^object_1, _}] = Health.between(:current, 5, 15)
    assert [{^object_2, _}] = Health.between(:current, 40, 60)
  end

  test "match/1" do
    object_1 = World.new()
    object_2 = World.new()

    Health.attach(object_1, current: 100, maximum: 100)
    Health.attach(object_2, current: 0, maximum: 100)

    assert [{^object_1, _}] = Health.match(current: 100)
    assert [{^object_2, _}] = Health.match(current: 0, maximum: 100)
  end
end
