defmodule Genesis.GenesisTest do
  use ExUnit.Case, async: false

  alias Genesis.World
  alias Genesis.Manager

  defmodule Ping do
    use Genesis.Aspect, events: [:ping, :check]

    def handle_event(event) do
      Process.sleep(Map.get(event.args, :delay, 0))
      send(event.from, {__MODULE__, event.object, DateTime.utc_now()})
      {:cont, event}
    end
  end

  defmodule Pong do
    use Genesis.Aspect, events: [:pong, :check]

    def handle_event(event) do
      Process.sleep(Map.get(event.args, :delay, 0))
      send(event.from, {__MODULE__, event.object, DateTime.utc_now()})
      {:cont, event}
    end
  end

  setup_all do
    on_exit(fn -> Manager.reset() end)

    world = start_link_supervised!(World)
    aspects = Enum.map([Ping, Pong], &Manager.register_aspect/1)

    {:ok, %{world: world, aspects: aspects}}
  end

  test "events are handled in registration order", %{world: world} do
    object = World.create(world)

    # Attach in reverse to prove the order of registration is the
    # one that really matters when dispatching events to objects
    Pong.attach(object)
    Ping.attach(object)

    # Aspects handling the same event will process the event
    # repsecting the registration order (i.e: Ping -> Pong)
    World.send(world, object, :check)

    assert_receive {Ping, ^object, ping_time}
    assert_receive {Pong, ^object, pong_time}

    # Ensure that Ping was processed before Pong
    assert DateTime.before?(ping_time, pong_time),
           "Expected Ping to be processed before Pong (respecting registration order)"
  end

  test "events dispatched to the same object are handled sequentially", %{world: world} do
    object = World.create(world)

    Ping.attach(object)
    Pong.attach(object)

    # Simulate latency for Ping to prove that aspects will
    # always be processed sequentially for the same object
    World.send(world, object, :ping, %{delay: 50})
    World.send(world, object, :pong)

    assert_receive {Ping, ^object, ping_time}
    assert_receive {Pong, ^object, pong_time}

    # Ensure that Ping was processed before Pong (Ping -> Pong)
    assert DateTime.before?(ping_time, pong_time),
           "Expected Ping to be processed before Pong (objects aspects are sequential): #{inspect(ping_time)} | #{inspect(pong_time)}"
  end

  test "events dispatched to different objects are handled concurrently", %{world: world} do
    object1 = World.create(world)
    object2 = World.create(world)

    Ping.attach(object1)
    Pong.attach(object1)

    Ping.attach(object2)
    Pong.attach(object2)

    # Simulate latency to prove that aspects for different objects
    # are always processed concurrently and not waiting on each other
    World.send(world, object1, :check, %{delay: :infinity})
    World.send(world, object2, :check)

    # Sanity check, to ensure that events are really blocked
    refute_receive {Ping, ^object1, _object1_ping_time}
    refute_receive {Pong, ^object1, _object1_pong_time}

    assert_receive {Ping, ^object2, _object2_ping_time}
    assert_receive {Pong, ^object2, _object2_pong_time}
  end
end
