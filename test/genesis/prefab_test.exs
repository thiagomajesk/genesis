defmodule Genesis.PrefabTest do
  use ExUnit.Case

  alias Genesis.Prefab
  alias Genesis.Manager
  alias Genesis.Components.Health
  alias Genesis.Components.Moniker
  alias Genesis.Components.Position

  setup do
    on_exit(fn -> Manager.reset() end)

    components = [Health, Moniker, Position]
    Manager.register_components(components)

    {:ok, %{components: components}}
  end

  test "load/2" do
    being_attrs = prefab_fixture(:being)
    human_attrs = prefab_fixture(:human)

    Manager.register_prefab(being_attrs)

    assert %Prefab{
             name: "Human",
             extends: ["Being"],
             components: components
           } =
             Prefab.load(human_attrs,
               prefabs: Manager.prefabs(),
               components: Manager.components()
             )

    assert [
             %Health{current: 80, maximum: 100},
             %Moniker{name: "Human"},
             %Position{x: 0, y: 0}
           ] = Enum.sort(components)
  end

  describe "queries" do
    test "get/1" do
      being_attrs = prefab_fixture(:being)
      {:ok, {being, _, _}} = Manager.register_prefab(being_attrs)

      assert %Health{current: 100} = Prefab.get(Health, being)
    end

    test "get/2" do
      being_attrs = prefab_fixture(:being)
      {:ok, {being, _, _}} = Manager.register_prefab(being_attrs)

      assert :default = Prefab.get(NonExistent, being, :default)
      assert %Health{current: 100} = Prefab.get(Health, being)
    end

    test "all/0" do
      being_attrs = prefab_fixture(:being)
      human_attrs = prefab_fixture(:human)

      {:ok, {human, _, _}} = Manager.register_prefab(being_attrs)
      {:ok, {being, _, _}} = Manager.register_prefab(human_attrs)

      entities = Enum.map(Prefab.all(Health), &elem(&1, 0))

      assert Enum.member?(entities, being)
      assert Enum.member?(entities, human)
    end

    test "match/1" do
      being_attrs = prefab_fixture(:being)
      human_attrs = prefab_fixture(:human)

      {:ok, {being, _, _}} = Manager.register_prefab(being_attrs)
      {:ok, {human, _, _}} = Manager.register_prefab(human_attrs)

      assert [] = Prefab.match(Moniker, name: "NonExistent")
      assert [{^being, _}] = Prefab.match(Moniker, name: "Being")
      assert [{^human, _}] = Prefab.match(Moniker, name: "Human")
    end

    test "at_least/2" do
      being_attrs = prefab_fixture(:being)
      human_attrs = prefab_fixture(:human)

      {:ok, {being, _, _}} = Manager.register_prefab(being_attrs)
      {:ok, {_human, _, _}} = Manager.register_prefab(human_attrs)

      assert [{^being, _}] = Prefab.at_least(Health, :current, 100)
    end

    test "at_most/2" do
      being_attrs = prefab_fixture(:being)
      human_attrs = prefab_fixture(:human)

      {:ok, {_being, _, _}} = Manager.register_prefab(being_attrs)
      {:ok, {human, _, _}} = Manager.register_prefab(human_attrs)

      assert [{^human, _}] = Prefab.at_most(Health, :current, 80)
    end

    test "between/3" do
      being_attrs = prefab_fixture(:being)
      human_attrs = prefab_fixture(:human)

      {:ok, {being, _, _}} = Manager.register_prefab(being_attrs)
      {:ok, {human, _, _}} = Manager.register_prefab(human_attrs)

      result = Prefab.between(Health, :current, 80, 100)
      entities = Enum.map(result, &elem(&1, 0))

      assert Enum.member?(entities, being)
      assert Enum.member?(entities, human)
    end
  end

  defp prefab_fixture(:being) do
    %{
      name: "Being",
      components: %{
        "health" => %{current: 100, maximum: 100},
        "moniker" => %{name: "Being"},
        "position" => %{x: 0, y: 0}
      }
    }
  end

  defp prefab_fixture(:human) do
    %{
      name: "Human",
      extends: ["Being"],
      components: %{
        "health" => %{current: 80},
        "moniker" => %{name: "Human"}
      }
    }
  end
end
