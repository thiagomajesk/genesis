defmodule Genesis.WorldTest do
  use ExUnit.Case

  alias Genesis.World
  alias Genesis.Manager
  alias Genesis.Components.Health
  alias Genesis.Components.Moniker
  alias Genesis.Components.Position
  alias Genesis.Components.Selectable

  setup do
    on_exit(fn -> Manager.reset() end)

    components = [Health, Moniker, Position, Selectable]
    Manager.register_components(components)

    {:ok, world: start_link_supervised!(World)}
  end

  describe "fetch/1" do
    test "returns empty when no components were registered", %{world: world} do
      entity = World.create(world)

      assert [] = World.fetch(entity)
    end

    test "returns all components for a given entity", %{world: world} do
      entity = World.create(world)

      Health.attach(entity, current: 100)
      Position.attach(entity, x: 10, y: 20)
      Moniker.attach(entity, name: "Object")

      components = World.fetch(entity)

      assert [
               %Health{current: 100},
               %Moniker{name: "Object"},
               %Position{y: 20, x: 10}
             ] = Enum.sort(components)
    end
  end

  describe "fetch/2" do
    test "returns nil for unknown entities", %{world: world} do
      entity = make_ref()

      assert World.fetch(world, entity) == nil
    end

    test "returns all components for a given entity", %{world: world} do
      entity = World.create(world)

      Health.attach(entity, current: 100)
      Position.attach(entity, x: 10, y: 20)
      Moniker.attach(entity, name: "Object")

      components = World.fetch(world, entity)

      assert [
               %Health{current: 100},
               %Moniker{name: "Object"},
               %Position{y: 20, x: 10}
             ] = Enum.sort(components)
    end
  end

  describe "list_entities" do
    test "with components as list", %{world: world} do
      entity = World.create(world)

      Health.attach(entity, current: 100)
      Position.attach(entity, x: 10, y: 20)
      Moniker.attach(entity, name: "Object")

      stream = World.list_entities(format_as: :list)

      assert [{^entity, components}] = Enum.to_list(stream)

      assert [
               %Health{current: 100},
               %Moniker{name: "Object"},
               %Position{x: 10, y: 20}
             ] = Enum.sort(components)
    end

    test "with components as map", %{world: world} do
      entity = World.create(world)

      Health.attach(entity, current: 100)
      Position.attach(entity, x: 10, y: 20)
      Moniker.attach(entity, name: "Object")

      stream = World.list_entities(format_as: :map)

      assert [{^entity, components}] = Enum.to_list(stream)

      assert %{y: 20, x: 10} = components["position"]
      assert %{maximum: nil, current: 100} = components["health"]
      assert %{name: "Object", description: nil} = components["moniker"]
    end
  end

  test "create/1", %{world: world} do
    entity = World.create(world)

    Health.attach(entity, current: 100)
    Position.attach(entity, x: 10, y: 20)
    Moniker.attach(entity, name: "Object")

    components = World.fetch(world, entity)

    assert [
             %Health{current: 100},
             %Moniker{name: "Object"},
             %Position{x: 10, y: 20}
           ] = Enum.sort(components)
  end

  test "create/2", %{world: world} do
    Manager.register_prefab(%{
      name: "Being",
      components: %{
        "health" => %{current: 100, maximum: 100},
        "moniker" => %{name: "Being"},
        "position" => %{x: 10, y: 20},
        "selectable" => %{}
      }
    })

    Manager.register_prefab(%{
      name: "Human",
      extends: ["Being"],
      components: %{
        "health" => %{current: 50},
        "moniker" => %{name: "John Doe"},
        "position" => %{x: 100, y: 200}
      }
    })

    entity = World.create(world, "Human")

    components = World.fetch(entity)

    assert [
             %Selectable{},
             %Health{current: 50, maximum: 100},
             %Moniker{name: "John Doe"},
             %Position{x: 100, y: 200}
           ] = Enum.sort(components)
  end

  test "create/3", %{world: world} do
    Manager.register_prefab(%{
      name: "Item",
      components: %{
        "moniker" => %{name: "Potion"}
      }
    })

    overrides = %{"moniker" => %{name: "Healing Potion"}}
    entity = World.create(world, "Item", overrides)

    assert %Moniker{name: "Healing Potion"} = Moniker.get(entity)
  end

  test "clone/1", %{world: world} do
    entity = World.create(world)

    Health.attach(entity, current: 100)
    Position.attach(entity, x: 10, y: 20)
    Moniker.attach(entity, name: "Object")

    clone = World.clone(world, entity)

    assert clone != entity
    assert Health.get(clone) == Health.get(entity)
    assert Position.get(clone) == Position.get(entity)
    assert Moniker.get(clone) == Moniker.get(entity)
  end

  describe "destroy/1" do
    test "removes entity components", %{world: world} do
      entity = World.create(world)

      Health.attach(entity, current: 100)
      Position.attach(entity, x: 10, y: 20)
      Moniker.attach(entity, name: "Object")

      assert :ok = World.destroy(world, entity)

      refute Health.get(entity)
      refute Position.get(entity)
      refute Moniker.get(entity)

      assert [] = World.fetch(entity)
    end

    test "returns noop for unknown entities", %{world: world} do
      entity = make_ref()
      assert :noop = World.destroy(world, entity)
    end
  end
end
