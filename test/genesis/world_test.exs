defmodule Genesis.WorldTest do
  use ExUnit.Case

  alias Genesis.World
  alias Genesis.Manager
  alias Genesis.Aspects.Health
  alias Genesis.Aspects.Moniker
  alias Genesis.Aspects.Position
  alias Genesis.Aspects.Selectable

  setup do
    on_exit(fn -> Manager.reset() end)

    aspects = [Health, Moniker, Position, Selectable]
    Enum.each(aspects, &Manager.register_aspect/1)

    world = start_link_supervised!(World)

    {:ok, world: world, aspects: aspects}
  end

  describe "fetch/1" do
    test "returns empty when no aspects were registered", %{world: world} do
      object = World.create(world)

      assert [] = World.fetch(object)
    end

    test "returns all aspects for a given object", %{world: world} do
      object = World.create(world)

      Health.attach(object, current: 100)
      Position.attach(object, x: 10, y: 20)
      Moniker.attach(object, name: "Object")

      aspects = World.fetch(object)

      assert [
               %Health{current: 100},
               %Moniker{name: "Object"},
               %Position{y: 20, x: 10}
             ] = Enum.sort(aspects)
    end
  end

  describe "fetch/2" do
    test "returns nil for unkown objects", %{world: world} do
      object = make_ref()

      assert World.fetch(world, object) == nil
    end

    test "returns all aspects for a given object", %{world: world} do
      object = World.create(world)

      Health.attach(object, current: 100)
      Position.attach(object, x: 10, y: 20)
      Moniker.attach(object, name: "Object")

      aspects = World.fetch(world, object)

      assert [
               %Health{current: 100},
               %Moniker{name: "Object"},
               %Position{y: 20, x: 10}
             ] = Enum.sort(aspects)
    end
  end

  describe "list_objects" do
    test "with aspects as list", %{world: world} do
      object = World.create(world)

      Health.attach(object, current: 100)
      Position.attach(object, x: 10, y: 20)
      Moniker.attach(object, name: "Object")

      stream = World.list_objects(aspects_as: :list)

      assert [{^object, aspects}] = Enum.to_list(stream)

      assert [
               %Health{current: 100},
               %Moniker{name: "Object"},
               %Position{x: 10, y: 20}
             ] = Enum.sort(aspects)
    end

    test "with aspects as map", %{world: world} do
      object = World.create(world)

      Health.attach(object, current: 100)
      Position.attach(object, x: 10, y: 20)
      Moniker.attach(object, name: "Object")

      stream = World.list_objects(aspects_as: :map)

      assert [{^object, aspects}] = Enum.to_list(stream)

      assert %{y: 20, x: 10} = aspects["position"]
      assert %{maximum: nil, current: 100} = aspects["health"]
      assert %{name: "Object", description: nil} = aspects["moniker"]
    end
  end

  test "create/1", %{world: world} do
    object = World.create(world)

    Health.attach(object, current: 100)
    Position.attach(object, x: 10, y: 20)
    Moniker.attach(object, name: "Object")

    aspects = World.fetch(world, object)

    assert [
             %Health{current: 100},
             %Moniker{name: "Object"},
             %Position{x: 10, y: 20}
           ] = Enum.sort(aspects)
  end

  test "create/2", %{world: world} do
    Manager.register_prefab(%{
      name: "Being",
      aspects: %{
        "health" => %{current: 100, maximum: 100},
        "moniker" => %{name: "Being"},
        "position" => %{x: 10, y: 20},
        "selectable" => %{}
      }
    })

    Manager.register_prefab(%{
      name: "Human",
      inherits: ["Being"],
      aspects: %{
        "health" => %{current: 50},
        "moniker" => %{name: "John Doe"},
        "position" => %{x: 100, y: 200}
      }
    })

    object = World.create(world, "Human")

    aspects = World.fetch(object)

    assert [
             %Selectable{},
             %Health{current: 50, maximum: 100},
             %Moniker{name: "John Doe"},
             %Position{x: 100, y: 200}
           ] = Enum.sort(aspects)
  end

  test "clone/1", %{world: world} do
    object = World.create(world)

    Health.attach(object, current: 100)
    Position.attach(object, x: 10, y: 20)
    Moniker.attach(object, name: "Object")

    clone = World.clone(world, object)

    assert clone != object
    assert Health.get(clone) == Health.get(object)
    assert Position.get(clone) == Position.get(object)
    assert Moniker.get(clone) == Moniker.get(object)
    assert World.fetch(clone) == World.fetch(object)
  end

  describe "destroy/1" do
    test "removes object and its aspects", %{world: world} do
      object = World.create(world)

      Health.attach(object, current: 100)
      Position.attach(object, x: 10, y: 20)
      Moniker.attach(object, name: "Object")

      assert :ok = World.destroy(world, object)

      refute Health.get(object)
      refute Position.get(object)
      refute Moniker.get(object)

      assert [] = World.fetch(object)
    end

    test "returns noop for unkown objects", %{world: world} do
      object = make_ref()
      assert :noop = World.destroy(world, object)
    end
  end
end
