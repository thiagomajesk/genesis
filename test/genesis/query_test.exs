defmodule Genesis.QueryTest do
  use ExUnit.Case, async: true

  alias Genesis.Query
  alias Genesis.Registry

  alias Genesis.Components.Health
  alias Genesis.Components.Moniker
  alias Genesis.Components.Position

  @registry __MODULE__

  setup do
    :ok = Registry.init(@registry)
    on_exit(fn -> Registry.clear(@registry) end)
    {:ok, registry: @registry}
  end

  test "all_of", %{registry: registry} do
    {:ok, entity_1} = Registry.create(registry)

    Registry.emplace(registry, entity_1, %Health{current: 100})
    Registry.emplace(registry, entity_1, %Position{x: 10, y: 20})
    Registry.emplace(registry, entity_1, %Moniker{name: "Entity"})

    {:ok, entity_2} = Registry.create(registry)

    Registry.emplace(registry, entity_2, %Health{current: 100})
    Registry.emplace(registry, entity_2, %Position{x: 10, y: 20})

    assert [^entity_1] = Query.all_of(registry, [Health, Position, Moniker])
  end

  test "any_of", %{registry: registry} do
    {:ok, entity_1} = Registry.create(registry)

    Registry.emplace(registry, entity_1, %Health{current: 100})
    Registry.emplace(registry, entity_1, %Position{x: 10, y: 20})
    Registry.emplace(registry, entity_1, %Moniker{name: "Entity"})

    {:ok, entity_2} = Registry.create(registry)

    Registry.emplace(registry, entity_2, %Position{x: 5, y: 15})

    assert [^entity_1] = Query.any_of(registry, [Health, Moniker])
  end

  test "none_of", %{registry: registry} do
    {:ok, entity_1} = Registry.create(registry)

    Registry.emplace(registry, entity_1, %Moniker{name: "Entity"})

    {:ok, entity_2} = Registry.create(registry)

    Registry.emplace(registry, entity_2, %Health{current: 100})
    Registry.emplace(registry, entity_2, %Position{x: 10, y: 20})

    assert [^entity_1] = Query.none_of(registry, [Health, Position])
  end

  test "search", %{registry: registry} do
    {:ok, entity_1} = Registry.create(registry)

    Registry.emplace(registry, entity_1, %Health{current: 100})
    Registry.emplace(registry, entity_1, %Position{x: 10, y: 20})
    Registry.emplace(registry, entity_1, %Moniker{name: "Entity"})

    {:ok, entity_2} = Registry.create(registry)

    Registry.emplace(registry, entity_2, %Health{current: 100})
    Registry.emplace(registry, entity_2, %Position{x: 10, y: 20})

    {:ok, entity_3} = Registry.create(registry)

    Registry.emplace(registry, entity_3, %Health{current: 100})
    Registry.emplace(registry, entity_3, %Moniker{name: "Entity"})

    opts = [all: [Health], any: [Moniker], none: [Position]]
    assert [^entity_3] = Query.search(registry, opts)
  end
end
