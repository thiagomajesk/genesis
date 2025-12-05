defmodule Genesis.ComponentTest do
  use ExUnit.Case, async: false

  alias Genesis.Context
  alias Genesis.Manager
  alias Genesis.Components.Health
  alias Genesis.Components.Moniker
  alias Genesis.Components.Position
  alias Genesis.Components.Selectable

  setup do
    on_exit(fn -> Manager.reset() end)

    Manager.register_components([
      Health,
      Moniker,
      Position,
      Selectable
    ])

    {:ok, context: start_supervised!(Context)}
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
    test "with a map", %{context: context} do
      entity = Context.create(context, context: context)

      Health.attach(entity, %{current: 100})

      assert %Health{current: 100} = Health.get(entity)
    end

    test "with a keyword list", %{context: context} do
      entity = Context.create(context, context: context)

      Health.attach(entity, current: 100)

      assert %Health{current: 100} = Health.get(entity)
    end

    test "with a struct", %{context: context} do
      entity = Context.create(context, context: context)

      Health.attach(entity, %Health{current: 100})

      assert %Health{current: 100} = Health.get(entity)
    end

    test "component is not attached twice", %{context: context} do
      entity = Context.create(context, context: context)

      Health.attach(entity, current: 50)

      assert :noop = Health.attach(entity, current: 50)
      assert :error = Health.attach(entity, current: 100)
      assert %Health{current: 50} = Health.get(entity)
    end
  end

  test "remove/1", %{context: context} do
    entity = Context.create(context, context: context)

    Health.attach(entity, current: 100)
    Moniker.attach(entity, name: "Entity")
    Position.attach(entity, x: 10, y: 20)

    Health.remove(entity)
    refute Health.get(entity)
  end

  test "update/2", %{context: context} do
    entity = Context.create(context, context: context)

    Health.attach(entity, current: 100)

    Health.update(entity, current: 50)

    assert %Health{current: 50} = Health.get(entity)
    assert :noop = Moniker.update(entity, name: "New Name")
  end

  test "update/3", %{context: context} do
    entity = Context.create(context, context: context)

    Health.attach(entity, current: 100)

    Health.update(entity, :current, &(&1 - 25))

    assert %Health{current: 75} = Health.get(entity)
    assert :noop = Moniker.update(entity, :name, & &1)
    assert :error = Health.update(entity, :foo, &(&1 + 10))
  end
end
