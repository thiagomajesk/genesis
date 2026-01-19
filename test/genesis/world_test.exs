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

  describe "fetch/2" do
    test "returns nil for unknown entities", %{world: world} do
      context = World.context(world)
      entity = Genesis.Entity.new(context: context)

      assert World.fetch(world, entity) == nil
    end

    test "returns all components for a given entity", %{world: world} do
      {:ok, entity} = World.create(world)

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

  describe "list" do
    test "with components as list", %{world: world} do
      {:ok, entity} = World.create(world)

      Health.attach(entity, current: 100)
      Position.attach(entity, x: 10, y: 20)
      Moniker.attach(entity, name: "Object")

      stream = World.list(world, format_as: :list)

      assert [{^entity, components}] = Enum.to_list(stream)

      assert [
               %Health{current: 100},
               %Moniker{name: "Object"},
               %Position{x: 10, y: 20}
             ] = Enum.sort(components)
    end

    test "with components as map", %{world: world} do
      {:ok, entity} = World.create(world)

      Health.attach(entity, current: 100)
      Position.attach(entity, x: 10, y: 20)
      Moniker.attach(entity, name: "Object")

      stream = World.list(world, format_as: :map)

      assert [{^entity, components}] = Enum.to_list(stream)

      assert %{y: 20, x: 10} = components["position"]
      assert %{maximum: nil, current: 100} = components["health"]
      assert %{name: "Object", description: nil} = components["moniker"]
    end
  end

  test "create/1", %{world: world} do
    {:ok, entity} = World.create(world)

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

    {:ok, entity} = World.create(world, "Human")

    components = World.fetch(world, entity)

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
    {:ok, entity} = World.create(world, "Item", overrides)

    assert %Moniker{name: "Healing Potion"} = Moniker.get(entity)
  end

  test "clone/1", %{world: world} do
    {:ok, entity} = World.create(world)

    Health.attach(entity, current: 100)
    Position.attach(entity, x: 10, y: 20)
    Moniker.attach(entity, name: "Object")

    {:ok, clone} = World.clone(world, entity)

    assert clone != entity
    assert Health.get(clone) == Health.get(entity)
    assert Position.get(clone) == Position.get(entity)
    assert Moniker.get(clone) == Moniker.get(entity)
  end

  describe "destroy/1" do
    test "removes entity components", %{world: world} do
      {:ok, entity} = World.create(world)

      Health.attach(entity, current: 100)
      Position.attach(entity, x: 10, y: 20)
      Moniker.attach(entity, name: "Object")

      assert :ok = World.destroy(world, entity)

      refute Health.get(entity)
      refute Position.get(entity)
      refute Moniker.get(entity)

      assert nil == World.fetch(world, entity)
    end

    test "returns noop for unknown entities", %{world: world} do
      context = World.context(world)
      entity = Genesis.Entity.new(context: context)
      assert :noop = World.destroy(world, entity)
    end
  end

  describe "attach/3" do
    test "attaches a component to an entity", %{world: world} do
      {:ok, entity} = World.create(world)

      assert :ok = Health.attach(entity, current: 100)
      assert %Health{current: 100} = Health.get(entity)
    end

    test "returns error when component already attached", %{world: world} do
      {:ok, entity} = World.create(world)

      Health.attach(entity, current: 50)
      assert :error = Health.attach(entity, current: 100)
      assert %Health{current: 50} = Health.get(entity)
    end
  end

  describe "update/3" do
    test "updates a component on an entity", %{world: world} do
      {:ok, entity} = World.create(world)

      Health.attach(entity, current: 100)
      assert :ok = Health.update(entity, current: 50)
      assert %Health{current: 50} = Health.get(entity)
    end

    test "returns error when component not present", %{world: world} do
      {:ok, entity} = World.create(world)

      assert :noop = Health.update(entity, current: 50)
    end
  end

  describe "queries" do
    test "all/2", %{world: world} do
      {:ok, entity_1} = World.create(world)
      {:ok, entity_2} = World.create(world)
      {:ok, entity_3} = World.create(world)

      Health.attach(entity_1, current: 100)
      Health.attach(entity_2, current: 100)
      Health.attach(entity_3, current: 100)

      entities = Enum.map(World.all(world, Health), &elem(&1, 0))

      assert Enum.member?(entities, entity_1)
      assert Enum.member?(entities, entity_2)
      assert Enum.member?(entities, entity_3)
    end

    test "at_least/4", %{world: world} do
      {:ok, entity_1} = World.create(world)
      {:ok, entity_2} = World.create(world)

      Health.attach(entity_1, current: 10)
      Health.attach(entity_2, current: 50)

      assert [{^entity_2, _}] = World.at_least(world, Health, :current, 50)
    end

    test "at_most/4", %{world: world} do
      {:ok, entity_1} = World.create(world)
      {:ok, entity_2} = World.create(world)

      Health.attach(entity_1, current: 10)
      Health.attach(entity_2, current: 50)

      assert [{^entity_1, _}] = World.at_most(world, Health, :current, 10)
    end

    test "between/5", %{world: world} do
      {:ok, entity_1} = World.create(world)
      {:ok, entity_2} = World.create(world)

      Health.attach(entity_1, current: 10)
      Health.attach(entity_2, current: 50)

      assert [{^entity_1, _}] = World.between(world, Health, :current, 5, 15)
      assert [{^entity_2, _}] = World.between(world, Health, :current, 40, 60)
    end

    test "match/3", %{world: world} do
      {:ok, entity_1} = World.create(world)
      {:ok, entity_2} = World.create(world)

      Health.attach(entity_1, current: 100, maximum: 100)
      Health.attach(entity_2, current: 0, maximum: 100)

      assert [{^entity_1, _}] = World.match(world, Health, current: 100)
      assert [{^entity_2, _}] = World.match(world, Health, current: 0, maximum: 100)
      assert [] = World.match(world, Health, invalid: 100)
    end
  end
end
