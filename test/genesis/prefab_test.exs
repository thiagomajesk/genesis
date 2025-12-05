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
           } = Prefab.load(human_attrs)

    assert [
             %Health{current: 80, maximum: 100},
             %Moniker{name: "Human"},
             %Position{x: 0, y: 0}
           ] = Enum.sort(components)
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
