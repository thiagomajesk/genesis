defmodule Genesis.ManagerTest do
  use ExUnit.Case, async: true

  alias Genesis.Manager
  alias Genesis.Prefab
  alias Genesis.Aspects.Health
  alias Genesis.Aspects.Moniker
  alias Genesis.Aspects.Position
  alias Genesis.Aspects.Selectable

  setup do
    on_exit(fn -> Manager.reset() end)
  end

  describe "register_aspect" do
    test "with default alias" do
      Manager.register_aspect(Health)
      Manager.register_aspect(Moniker)
      Manager.register_aspect(Position)
      Manager.register_aspect(Selectable)

      assert [
               {"health", Health},
               {"moniker", Moniker},
               {"position", Position},
               {"selectable", Selectable}
             ] =
               Manager.list_aspects()
    end

    test "with custom alias" do
      Manager.register_aspect({"prefix::health", Health})
      Manager.register_aspect({"prefix::moniker", Moniker})
      Manager.register_aspect({"prefix::position", Position})
      Manager.register_aspect({"prefix::selectable", Selectable})

      assert [
               {"prefix::health", Health},
               {"prefix::moniker", Moniker},
               {"prefix::position", Position},
               {"prefix::selectable", Selectable}
             ] =
               Manager.list_aspects()
    end
  end

  test "attach_aspect/2" do
    Manager.register_aspect(Health)
    Manager.register_aspect(Moniker)
    Manager.register_aspect(Position)
    Manager.register_aspect(Selectable)

    object = make_ref()

    health = %Health{current: 100}
    moniker = %Moniker{name: "Foo"}
    position = %Position{x: 0, y: 0}
    selectable = %Selectable{}

    Manager.attach_aspect(object, health)
    Manager.attach_aspect(object, moniker)
    Manager.attach_aspect(object, position)
    Manager.attach_aspect(object, selectable)

    assert ^health = Health.get(object)
    assert ^moniker = Moniker.get(object)
    assert ^position = Position.get(object)
    assert ^selectable = Selectable.get(object)
  end

  test "remove_aspect/2" do
    Manager.register_aspect(Health)
    Manager.register_aspect(Moniker)
    Manager.register_aspect(Position)
    Manager.register_aspect(Selectable)

    object = make_ref()

    health = %Health{current: 100}
    moniker = %Moniker{name: "Foo"}
    position = %Position{x: 0, y: 0}
    selectable = %Selectable{}

    Manager.attach_aspect(object, health)
    Manager.attach_aspect(object, moniker)
    Manager.attach_aspect(object, position)
    Manager.attach_aspect(object, selectable)

    Manager.remove_aspect(object, Selectable)

    refute Selectable.get(object)
    assert ^health = Health.get(object)
    assert ^moniker = Moniker.get(object)
    assert ^position = Position.get(object)
  end

  test "replace_aspect/3" do
    Manager.register_aspect(Health)
    Manager.register_aspect(Moniker)
    Manager.register_aspect(Position)
    Manager.register_aspect(Selectable)

    object = make_ref()

    health = %Health{current: 100}
    moniker = %Moniker{name: "Foo"}
    position = %Position{x: 0, y: 0}

    Manager.attach_aspect(object, health)
    Manager.attach_aspect(object, moniker)
    Manager.attach_aspect(object, position)

    Manager.replace_aspect(object, Health, %{current: 50})
    Manager.replace_aspect(object, Moniker, %{name: "Bar"})
    Manager.replace_aspect(object, Position, %{x: 10, y: 10})

    assert %Health{current: 50} = Health.get(object)
    assert %Moniker{name: "Bar"} = Moniker.get(object)
    assert %Position{x: 10, y: 10} = Position.get(object)
  end

  test "update_aspect/4" do
    Manager.register_aspect(Health)
    Manager.register_aspect(Moniker)
    Manager.register_aspect(Position)
    Manager.register_aspect(Selectable)

    object = make_ref()

    health = %Health{current: 100}
    moniker = %Moniker{name: "Foo"}
    position = %Position{x: 0, y: 0}

    Manager.attach_aspect(object, health)
    Manager.attach_aspect(object, moniker)
    Manager.attach_aspect(object, position)

    Manager.update_aspect(object, Health, :current, &(&1 - 50))
    Manager.update_aspect(object, Moniker, :name, fn _name -> "Baz" end)
    Manager.update_aspect(object, Position, :x, &(&1 + 10))
    Manager.update_aspect(object, Position, :y, &(&1 + 10))

    assert %Health{current: 50} = Health.get(object)
    assert %Moniker{name: "Baz"} = Moniker.get(object)
    assert %Position{x: 10, y: 10} = Position.get(object)
  end

  describe "prefabs" do
    test "create prefab with map and default alias" do
      Manager.register_aspect(Health)
      Manager.register_aspect(Moniker)
      Manager.register_aspect(Position)
      Manager.register_aspect(Selectable)

      Manager.register_prefab(%{
        name: "Being",
        aspects: %{
          "health" => %{current: 100},
          "moniker" => %{name: "Being"},
          "position" => %{x: 10, y: 20},
          "selectable" => %{}
        }
      })

      assert [{"Being", %Prefab{inherit: [], aspects: aspects}}] = Manager.list_prefabs()

      assert [
               %Selectable{},
               %Health{current: 100},
               %Moniker{name: "Being"},
               %Position{y: 20, x: 10}
             ] = Enum.sort(aspects)
    end

    test "create prefab with list and custom alias" do
      Manager.register_aspect({"prefix::health", Health})
      Manager.register_aspect({"prefix::moniker", Moniker})
      Manager.register_aspect({"prefix::position", Position})
      Manager.register_aspect({"prefix::selectable", Selectable})

      Manager.register_prefab(%{
        name: "Being",
        aspects: [
          {"prefix::health", %{current: 100}},
          {"prefix::moniker", %{name: "Being"}},
          {"prefix::position", %{x: 10, y: 20}},
          {"prefix::selectable", %{}}
        ]
      })

      assert [{"Being", %Prefab{inherit: [], aspects: aspects}}] = Manager.list_prefabs()

      assert [
               %Selectable{},
               %Health{current: 100},
               %Moniker{name: "Being"},
               %Position{y: 20, x: 10}
             ] = Enum.sort(aspects)
    end

    test "create prefab with keyword list" do
      Manager.register_aspect({:health, Health})
      Manager.register_aspect({:moniker, Moniker})
      Manager.register_aspect({:position, Position})
      Manager.register_aspect({:selectable, Selectable})

      Manager.register_prefab(%{
        name: "Being",
        aspects: [
          health: %{current: 100},
          moniker: %{name: "Being"},
          position: %{x: 10, y: 20},
          selectable: %{}
        ]
      })

      assert [{"Being", %Prefab{inherit: [], aspects: aspects}}] = Manager.list_prefabs()

      assert [
               %Selectable{},
               %Health{current: 100},
               %Moniker{name: "Being"},
               %Position{y: 20, x: 10}
             ] = Enum.sort(aspects)
    end
  end
end
