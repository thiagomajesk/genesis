defmodule Genesis.ComponentTest do
  use ExUnit.Case, async: false

  alias Genesis.Registry
  alias Genesis.Manager
  alias Genesis.Components.Health
  alias Genesis.Components.Moniker
  alias Genesis.Components.Position
  alias Genesis.Components.Selectable

  setup do
    :ok = Manager.init()
    on_exit(fn -> Manager.reset() end)
  end

  test "new/0" do
    assert %Health{} = Health.new()
    assert %Moniker{} = Moniker.new()
    assert %Position{} = Position.new()
    assert %Selectable{} = Selectable.new()
  end

  test "new/1" do
    assert %Health{current: 100} = Health.new(current: 100)
    assert %Moniker{name: "Entity"} = Moniker.new(name: "Entity")
    assert %Position{x: 10, y: 20} = Position.new(x: 10, y: 20)
    assert %Selectable{} = Selectable.new(%{})
  end

  describe "attach/2" do
    test "with a map" do
      entity = Manager.entity!()

      Health.attach(entity, %{current: 100})

      assert {^entity, [%Health{current: 100}]} =
               Registry.fetch(:entities, entity)
    end

    test "with a keyword list" do
      entity = Manager.entity!()

      Health.attach(entity, current: 100)

      assert {^entity, [%Health{current: 100}]} =
               Registry.fetch(:entities, entity)
    end

    test "with a struct" do
      entity = Manager.entity!()

      Health.attach(entity, %Health{current: 100})

      assert {^entity, [%Health{current: 100}]} =
               Registry.fetch(:entities, entity)
    end

    test "component is not attached twice" do
      entity = Manager.entity!()

      Health.attach(entity, current: 50)

      assert :noop = Health.attach(entity, current: 50)
      assert :error = Health.attach(entity, current: 100)
      assert %Health{current: 50} = Health.get(entity)
    end
  end

  test "remove/1" do
    entity = Manager.entity!()

    Health.attach(entity, current: 100)
    Moniker.attach(entity, name: "Entity")
    Position.attach(entity, x: 10, y: 20)

    Health.remove(entity)
    refute Health.get(entity)
  end

  test "update/2" do
    entity = Manager.entity!()

    Health.attach(entity, current: 100)

    Health.update(entity, current: 50)

    assert %Health{current: 50} = Health.get(entity)
    assert :noop = Moniker.update(entity, name: "New Name")
  end

  test "update/3" do
    entity = Manager.entity!()

    Health.attach(entity, current: 100)

    Health.update(entity, :current, &(&1 - 25))

    assert %Health{current: 75} = Health.get(entity)
    assert :noop = Moniker.update(entity, :name, & &1)
    assert :error = Health.update(entity, :foo, &(&1 + 10))
  end

  describe "queries" do
    test "get/1" do
      entity = Manager.entity!()

      Health.attach(entity, current: 100)

      refute Moniker.get(entity)
      assert %Health{current: 100} = Health.get(entity)
    end

    test "get/2" do
      entity = Manager.entity!()

      Health.attach(entity, current: 100)

      assert :default = Moniker.get(entity, :default)
      assert %Health{current: 100} = Health.get(entity)
    end

    test "all/0" do
      entity_1 = Manager.entity!()
      entity_2 = Manager.entity!()
      entity_3 = Manager.entity!()

      Health.attach(entity_1, current: 100)
      Health.attach(entity_2, current: 100)
      Health.attach(entity_3, current: 100)

      entities = Enum.map(Health.all(), &elem(&1, 0))

      assert Enum.member?(entities, entity_1)
      assert Enum.member?(entities, entity_2)
      assert Enum.member?(entities, entity_3)
    end

    test "at_least/2" do
      entity_1 = Manager.entity!()
      entity_2 = Manager.entity!()

      Health.attach(entity_1, current: 10)
      Health.attach(entity_2, current: 50)

      assert [{^entity_2, _}] = Health.at_least(:current, 50)
      assert_raise FunctionClauseError, fn -> Health.at_least(:invalid, 50) end
    end

    test "at_most/2" do
      entity_1 = Manager.entity!()
      entity_2 = Manager.entity!()

      Health.attach(entity_1, current: 10)
      Health.attach(entity_2, current: 50)

      assert [{^entity_1, _}] = Health.at_most(:current, 10)
      assert_raise FunctionClauseError, fn -> Health.at_most(:invalid, 10) end
    end

    test "between/3" do
      entity_1 = Manager.entity!()
      entity_2 = Manager.entity!()

      Health.attach(entity_1, current: 10)
      Health.attach(entity_2, current: 50)

      assert [{^entity_1, _}] = Health.between(:current, 5, 15)
      assert [{^entity_2, _}] = Health.between(:current, 40, 60)
      assert_raise FunctionClauseError, fn -> Health.between(:invalid, 5, 15) end
    end

    test "match/1" do
      entity_1 = Manager.entity!()
      entity_2 = Manager.entity!()

      Health.attach(entity_1, current: 100, maximum: 100)
      Health.attach(entity_2, current: 0, maximum: 100)

      assert [{^entity_1, _}] = Health.match(current: 100)
      assert [{^entity_2, _}] = Health.match(current: 0, maximum: 100)
      assert [] = Health.match(invalid: 100)
    end
  end
end
