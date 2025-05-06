defmodule Genesis.WorldTest do
  use ExUnit.Case

  alias Genesis.World
  alias Genesis.Aspects.Health
  alias Genesis.Aspects.Moniker
  alias Genesis.Aspects.Position
  alias Genesis.Aspects.Selectable

  setup do
    opts = [aspect_prefix: "Genesis.Aspects"]
    {:ok, world: start_supervised!({World, opts})}
  end

  test "new/0" do
    objects = Enum.map(1..999, fn _ -> World.new() end)
    refute length(Enum.uniq(objects)) != length(objects)
  end

  describe "fetch/1" do
    test "returns empty when no aspects were registered" do
      object = World.new()

      assert [] = World.fetch(object)
    end

    test "returns all aspects for a given object" do
      modules = [Health, Moniker, Position]
      Enum.each(modules, &World.register_aspect/1)

      object = World.new()

      Health.attach(object, current: 100)
      Position.attach(object, x: 10, y: 20)
      Moniker.attach(object, name: "Object")

      aspects = [
        %Moniker{name: "Object"},
        %Position{y: 20, x: 10},
        %Health{current: 100}
      ]

      assert ^aspects = World.fetch(object)
    end
  end

  test "register_aspect/1" do
    assert :ok = World.register_aspect(Health)
    assert :ok = World.register_aspect(Moniker)
    assert :ok = World.register_aspect(Position)
  end

  describe "list_aspects/0" do
    test "returns empty when no aspects were registered" do
      assert [] = World.list_aspects()
    end

    test "returns all registered aspects" do
      modules = [Health, Moniker, Position]
      Enum.each(modules, &World.register_aspect/1)

      # Map the aspect definitions to their module names.
      # Ensure aspects are returned in the registration order.
      assert ^modules = Enum.map(World.list_aspects(), &elem(&1, 0))
    end
  end

  test "list_objects/0" do
    modules = [Health, Moniker, Position]
    Enum.each(modules, &World.register_aspect/1)

    object = World.new()

    Health.attach(object, current: 100)
    Position.attach(object, x: 10, y: 20)
    Moniker.attach(object, name: "Object")

    assert [{^object, _}] = World.list_objects()
  end

  test "clone/1" do
    modules = [Health, Moniker, Position]
    Enum.each(modules, &World.register_aspect/1)

    object = World.new()

    Health.attach(object, current: 100)
    Position.attach(object, x: 10, y: 20)
    Moniker.attach(object, name: "Object")

    clone = World.clone(object)

    assert clone != object
    assert Health.get(clone) == Health.get(object)
    assert Position.get(clone) == Position.get(object)
    assert Moniker.get(clone) == Moniker.get(object)
    assert World.fetch(clone) == World.fetch(object)
  end

  test "destroy/1" do
    modules = [Health, Moniker, Position]
    Enum.each(modules, &World.register_aspect/1)

    object = World.new()

    Health.attach(object, current: 100)
    Position.attach(object, x: 10, y: 20)
    Moniker.attach(object, name: "Object")

    World.destroy(object)

    refute Health.get(object)
    refute Position.get(object)
    refute Moniker.get(object)

    assert [] = World.fetch(object)
  end

  test "send/1" do
    modules = [Health, Moniker, Position]
    Enum.each(modules, &World.register_aspect/1)

    object = World.new()

    Health.attach(object, current: 100)
    Position.attach(object, x: 10, y: 20)
    Moniker.attach(object, name: "Object")

    events = [:move, :damage, :describe]

    Enum.each(events, &World.send(object, &1))

    flushed = Enum.map(events, &{&1, object})

    assert ^flushed = World.flush()
  end

  describe "prefabs" do
    test "create prefab" do
      modules = [Health, Moniker, Position, Selectable]
      Enum.each(modules, &World.register_aspect/1)

      prefab = %{
        name: "Being",
        aspects: [
          %{type: "Health", props: %{current: 50}},
          %{type: "Moniker", props: %{name: "Being"}},
          %{type: "Position", props: %{x: 10, y: 20}},
          %{type: "Selectable"}
        ]
      }

      World.register_prefab(prefab)

      object = World.create("Being")

      aspects = [
        %Selectable{},
        %Health{current: 50},
        %Position{y: 20, x: 10},
        %Moniker{name: "Being"}
      ]

      assert ^aspects = World.fetch(object)
    end

    test "registers children prefab" do
      modules = [Health, Moniker, Position, Selectable]
      Enum.each(modules, &World.register_aspect/1)

      prefab1 = %{
        name: "Being",
        aspects: [
          %{type: "Health", props: %{current: 50}},
          %{type: "Moniker", props: %{name: "Being"}},
          %{type: "Position", props: %{x: 10, y: 20}},
          %{type: "Selectable"}
        ]
      }

      prefab2 = %{
        name: "Human",
        inherits: ["Being"],
        aspects: [
          %{type: "Health", props: %{current: 100}},
          %{type: "Moniker", props: %{name: "John Doe"}, on_conflict: :replace},
          %{type: "Position", props: %{x: 100}, on_conflict: :merge}
        ]
      }

      World.register_prefab(prefab1)
      World.register_prefab(prefab2)

      object = World.create("Human")

      aspects = [
        %Selectable{},
        %Health{current: 100},
        %Position{x: 100, y: 20},
        %Moniker{name: "John Doe"}
      ]

      assert ^aspects = World.fetch(object)
    end
  end
end
