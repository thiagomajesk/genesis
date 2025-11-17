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

    Manager.remove_aspect(object, selectable)

    refute Selectable.get(object)
    assert ^health = Health.get(object)
    assert ^moniker = Moniker.get(object)
    assert ^position = Position.get(object)
  end

  test "replace_aspect/2" do
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

    updated_health = %Health{current: 50}
    updated_moniker = %Moniker{name: "Bar"}
    updated_position = %Position{x: 10, y: 10}
    updated_selectable = %Selectable{}

    Manager.replace_aspect(object, updated_health)
    Manager.replace_aspect(object, updated_moniker)
    Manager.replace_aspect(object, updated_position)
    Manager.replace_aspect(object, updated_selectable)

    assert ^updated_health = Health.get(object)
    assert ^updated_moniker = Moniker.get(object)
    assert ^updated_position = Position.get(object)
    assert ^updated_selectable = Selectable.get(object)
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
