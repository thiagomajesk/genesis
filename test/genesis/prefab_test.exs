defmodule Genesis.PrefabTest do
  use ExUnit.Case

  alias Genesis.Prefab
  alias Genesis.Manager
  alias Genesis.Aspects.Health
  alias Genesis.Aspects.Moniker
  alias Genesis.Aspects.Position

  setup do
    on_exit(fn -> Manager.reset() end)

    Manager.register_aspect(Health)
    Manager.register_aspect(Moniker)
    Manager.register_aspect(Position)

    {:ok, %{aspects: [Health, Moniker, Position]}}
  end

  test "load/2" do
    Manager.register_prefab(prefab_fixture(:being))

    registered_aspects = Manager.list_aspects()
    registered_prefabs = Manager.list_prefabs()

    prefab =
      Prefab.load(
        prefab_fixture(:human),
        registered_aspects: registered_aspects,
        registered_prefabs: registered_prefabs
      )

    assert %Prefab{name: "Human", extends: ["Being"], aspects: aspects} = prefab

    assert [
             %Health{current: 80, maximum: 100},
             %Moniker{name: "Human"},
             %Position{x: 0, y: 0}
           ] = Enum.sort(aspects)
  end

  defp prefab_fixture(:being) do
    %{
      name: "Being",
      aspects: %{
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
      aspects: %{
        "health" => %{current: 80},
        "moniker" => %{name: "Human"}
      }
    }
  end
end
