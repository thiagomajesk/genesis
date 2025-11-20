defmodule Genesis.GenesisTest do
  use ExUnit.Case, async: false

  alias Genesis.World
  alias Genesis.Manager

  defmodule Ping do
    use Genesis.Aspect, events: [:check, :ping]

    def handle_event(event) do
      Process.sleep(Map.get(event.args, :delay, 0))
      send(event.from, {__MODULE__, event.object, DateTime.utc_now()})
      {:cont, event}
    end
  end

  defmodule Pong do
    use Genesis.Aspect, events: [:check, :pong]

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

    World.send(world, object, :check)
    World.send(world, object, :check)

    assert_receive {Ping, ^object, ping_time}
    assert_receive {Pong, ^object, pong_time}

    # Ensure that Ping was processed before Pong
    assert DateTime.before?(ping_time, pong_time),
           "Expected Ping to be processed before Pong, but it was not."
  end

  describe "events dispatched to the same object" do
    test "are handled sequentially", %{world: world} do
      object = World.create(world)

      Ping.attach(object)
      Pong.attach(object)

      # Simulate latency for Ping to prove that aspects will
      # always be processed sequentially for the same object
      World.send(world, object, :check, %{delay: 50})
      World.send(world, object, :check)

      assert_receive {Ping, ^object, ping_time}
      assert_receive {Pong, ^object, pong_time}

      # Ensure that Ping was processed before Pong
      assert DateTime.before?(ping_time, pong_time),
             "Expected Ping to be processed before Pong, but it was not."
    end
  end

  describe "events dispatched to different objects" do
    test "are handled concurrently", %{world: world} do
      object1 = World.create(world)
      object2 = World.create(world)

      Ping.attach(object1)
      Pong.attach(object1)

      Ping.attach(object2)
      Pong.attach(object2)

      World.send(world, object1, :check, %{delay: 50})
      World.send(world, object2, :check, %{delay: 50})

      assert_receive {Ping, ^object1, object1_ping_time}
      assert_receive {Pong, ^object1, object1_pong_time}

      assert_receive {Ping, ^object2, object2_ping_time}
      assert_receive {Pong, ^object2, object2_pong_time}

      refute DateTime.before?(object1_pong_time, object2_ping_time),
             "Expected overlap but #{inspect(object1)} finished before #{inspect(object2)} started"

      refute DateTime.before?(object2_pong_time, object1_ping_time),
             "Expected overlap but #{inspect(object2)} finished before #{inspect(object1)} started"
    end
  end
end
