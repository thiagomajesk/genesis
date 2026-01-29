defmodule Genesis.ManagerTest do
  use ExUnit.Case, async: false

  alias Genesis.Manager
  alias Genesis.Prefab
  alias Genesis.Components.Health
  alias Genesis.Components.Container
  alias Genesis.Components.Moniker
  alias Genesis.Components.MetaInfo
  alias Genesis.Components.Position
  alias Genesis.Components.Selectable

  setup do
    on_exit(fn -> Manager.reset() end)
  end

  test "components" do
    Manager.register_components([
      Health,
      Moniker,
      Position,
      Selectable
    ])

    components = Manager.components()

    assert %{
             "health" => Health,
             "moniker" => Moniker,
             "position" => Position,
             "selectable" => Selectable
           } = components
  end

  test "handlers" do
    Manager.register_components([Health, Moniker])

    assert {:damage, [Health]} in Manager.handlers()
    assert {:describe, [Moniker]} in Manager.handlers()
  end

  describe "prefabs" do
    test "create prefab with map and default alias" do
      now = Date.utc_today()

      Manager.register_components([
        Health,
        Moniker,
        Position,
        Selectable,
        MetaInfo
      ])

      Manager.register_prefab(%{
        name: "Being",
        components: %{
          "health" => %{current: 100},
          "moniker" => %{name: "Being"},
          "meta_info" => %{creation_date: now},
          "position" => %{x: 10, y: 20},
          "selectable" => %{}
        }
      })

      assert [{"Being", %Prefab{extends: [], components: components}}] =
               Enum.to_list(Manager.prefabs())

      assert [
               %Selectable{},
               %MetaInfo{creation_date: ^now},
               %Health{current: 100},
               %Moniker{name: "Being"},
               %Position{y: 20, x: 10}
             ] = Enum.sort(components)
    end

    test "create prefab with props as string keys" do
      Manager.register_components([Container])

      Manager.register_prefab(%{
        name: "Crate",
        components: %{
          "container" => %{
            "capacity" => 10,
            "name" => "Crate"
          }
        }
      })

      assert [{"Crate", %Prefab{components: components}}] =
               Enum.to_list(Manager.prefabs())

      assert [%Container{capacity: 10, name: "Crate"}] =
               Enum.filter(components, &match?(%Container{}, &1))
    end
  end
end
