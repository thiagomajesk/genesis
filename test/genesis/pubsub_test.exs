defmodule Genesis.PubSubTest do
  use ExUnit.Case, async: false

  alias Genesis.World
  alias Genesis.Manager
  alias Genesis.Components.Moniker
  alias Genesis.Components.Health

  setup_all do
    on_exit(fn -> Manager.reset() end)
    Manager.register_components([Moniker, Health])
    {:ok, world: start_link_supervised!(World)}
  end

  test "registration", %{world: world} do
    pid_1 =
      spawn_link(fn ->
        Manager.watch(world)
        Manager.watch(world)
        Process.sleep(:infinity)
      end)

    pid_2 =
      spawn_link(fn ->
        Manager.watch(world)
        Manager.watch(world)
        Process.sleep(:infinity)
      end)

    # Give a little time for registration
    # to happen inside the spawned processes
    Process.sleep(100)

    # Ensure both pids are correctly registered
    assert [{first_registration, _}, {second_registration, _}] =
             Registry.lookup(Genesis.PubSub, {world, :attached})

    assert first_registration in [pid_1, pid_2]
    assert second_registration in [pid_1, pid_2]
  end

  test "hook notifications", %{world: world} do
    {:ok, entity_1} = World.create(world)
    {:ok, entity_2} = World.create(world)

    Manager.watch(world)

    :ok = Health.attach(entity_1, current: 100)
    :ok = Health.update(entity_1, current: 50)
    :ok = Health.update(entity_1, :current, &(&1 - 10))
    :ok = Health.remove(entity_1)

    :noop = Health.update(entity_2, current: 80)
    :noop = Health.update(entity_2, :current, &(&1 - 20))
    :noop = Health.remove(entity_2)

    assert_receive {:attached, Health, ^entity_1}
    assert_receive {:updated, Health, ^entity_1}
    assert_receive {:updated, Health, ^entity_1}
    assert_receive {:removed, Health, ^entity_1}

    # No notifications are being sent for entity_2
    refute_receive {:updated, Health, ^entity_1}
    refute_receive {:updated, Health, ^entity_1}
    refute_receive {:removed, Health, ^entity_1}
  end

  test "component filter", %{world: world} do
    {:ok, entity} = World.create(world)

    Manager.watch(world, components: [Moniker])

    Health.attach(entity, current: 100)
    Moniker.attach(entity, name: "Hero")

    refute_receive {:attached, Health, ^entity}
    assert_receive {:attached, Moniker, ^entity}
  end

  test "hook filter", %{world: world} do
    {:ok, entity} = World.create(world)

    Manager.watch(world, hooks: [:attached])

    Health.attach(entity, current: 100)
    Health.update(entity, current: 50)
    Health.remove(entity)

    assert_receive {:attached, Health, ^entity}
    refute_receive {:updated, Health, ^entity}
    refute_receive {:removed, Health, ^entity}
  end
end
