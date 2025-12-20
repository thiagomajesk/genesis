defmodule Genesis.GenesisTest do
  use ExUnit.Case, async: false

  alias Genesis.World
  alias Genesis.Manager

  defmodule Ping do
    use Genesis.Component, events: [:ping, :check]

    def handle_event(_name, event) do
      Process.sleep(Map.get(event.args, :delay, 0))
      send(event.from, {__MODULE__, event.entity, DateTime.utc_now()})
      {:cont, event}
    end
  end

  defmodule Pong do
    use Genesis.Component, events: [:pong, :check]

    def handle_event(_name, event) do
      Process.sleep(Map.get(event.args, :delay, 0))
      send(event.from, {__MODULE__, event.entity, DateTime.utc_now()})
      {:cont, event}
    end
  end

  setup_all do
    on_exit(fn -> Manager.reset() end)
    Manager.register_components([Ping, Pong])

    {:ok, %{world: start_link_supervised!(World)}}
  end

  test "events are handled in registration order", %{world: world} do
    entity = World.create(world)

    # Attach in reverse to prove the order of registration is the
    # one that really matters when dispatching events to entities
    Pong.attach(entity)
    Ping.attach(entity)

    # Components handling the same event will process the event
    # respecting the registration order (i.e: Ping -> Pong)
    World.send(world, entity, :check)

    assert_receive {Ping, ^entity, ping_time}
    assert_receive {Pong, ^entity, pong_time}

    # Ensure that Ping was processed before Pong
    assert DateTime.before?(ping_time, pong_time),
           "Expected Ping to be processed before Pong (respecting registration order)"
  end

  test "events dispatched to the same entity are handled sequentially", %{world: world} do
    entity = World.create(world)

    Ping.attach(entity)
    Pong.attach(entity)

    # Simulate latency for Ping to prove that components will
    # always be processed sequentially for the same entity
    World.send(world, entity, :ping, %{delay: 50})
    World.send(world, entity, :pong)

    assert_receive {Ping, ^entity, ping_time}
    assert_receive {Pong, ^entity, pong_time}

    # Ensure that Ping was processed before Pong (Ping -> Pong)
    assert DateTime.before?(ping_time, pong_time),
           "Expected Ping to be processed before Pong (entity components are sequential): #{inspect(ping_time)} | #{inspect(pong_time)}"
  end

  test "events dispatched to different entities are handled concurrently", %{world: world} do
    entity1 = World.create(world)
    entity2 = World.create(world)

    Ping.attach(entity1)
    Pong.attach(entity1)

    Ping.attach(entity2)
    Pong.attach(entity2)

    # Simulate latency to prove that components for different entities
    # are always processed concurrently and not waiting on each other
    World.send(world, entity1, :check, %{delay: :infinity})
    World.send(world, entity2, :check)

    # Sanity check, to ensure that events are really blocked
    refute_receive {Ping, ^entity1, _entity1_ping_time}
    refute_receive {Pong, ^entity1, _entity1_pong_time}

    assert_receive {Ping, ^entity2, _entity2_ping_time}
    assert_receive {Pong, ^entity2, _entity2_pong_time}
  end
end
