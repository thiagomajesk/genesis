################################################################################
# Parse options
################################################################################
{opts, _} =
  OptionParser.parse!(System.argv(),
    aliases: [d: :duration, o: :objects, i: :interval],
    strict: [duration: :integer, objects: :integer, interval: :integer]
  )

duration = Keyword.get(opts, :duration)
objects_count = Keyword.get(opts, :objects)
interval = Keyword.get(opts, :interval)

################################################################################
# Test setup
################################################################################
defmodule Tag do
  use Genesis.Aspect, events: [:greet]
end

Genesis.World.register_aspect(Tag)

objects =
  Enum.map(1..objects_count, fn object ->
    with :ok <- Tag.attach(object), do: object
  end)

IO.puts("Starting resource monitoring...")
IO.puts("Duration: #{duration} seconds")
IO.puts("Objects count: #{length(objects)}")
IO.puts("Message interval: #{interval}ms")
IO.puts("Collecting benchmark data... \n\n")

# Schedule a message to stop the load test after --duration
Process.send_after(self(), :stop, :timer.seconds(duration))

process_info = fn
  pid when is_pid(pid) ->
    keys = [
      :memory,
      :parent,
      :stack_size,
      :reductions,
      :registered_name,
      :total_heap_size,
      :message_queue_len
    ]

    raw_info = Process.info(pid, keys)
    map_info = Map.new(List.wrap(raw_info))

    raw_parent_info =
      if is_pid(map_info.parent),
        do: Process.info(map_info.parent, [:registered_name])

    map_parent_info = Map.new(List.wrap(raw_parent_info))

    memory = get_in(map_info, [:memory])
    stack_size = get_in(map_info, [:stack_size])
    reductions = get_in(map_info, [:reductions])
    total_heap_size = get_in(map_info, [:total_heap_size])
    registered_name = get_in(map_info, [:registered_name])
    parent_name = get_in(map_parent_info, [:registered_name])
    message_queue_len = get_in(map_info, [:message_queue_len])

    %{
      pid: pid,
      memory: memory,
      parent: parent_name,
      name: registered_name,
      stack_size: stack_size,
      reductions: reductions,
      total_heap_size: total_heap_size,
      message_queue_len: message_queue_len
    }

  _other ->
    %{}
end

collect_data = fn ->
  processes = Process.list()

  processes
  |> Enum.map(&process_info.(&1))
  |> Enum.sort_by(& &1.reductions, :desc)
  |> Enum.filter(fn info ->
    to_string(info.parent) =~ "Genesis" or
      to_string(info.name) =~ "Genesis"
  end)
end

pretty_print_stats = fn ->
  data = collect_data.()

  Enum.each(data, fn info ->
    IO.puts("PID:\t\t\t #{inspect(info.pid)}")
    IO.puts("NAME:\t\t\t #{inspect(info.name)}")
    IO.puts("PARENT:\t\t\t #{info.parent}")
    IO.puts("MEMORY:\t\t\t #{info.memory}")
    IO.puts("STACK SIZE:\t\t #{info.stack_size}")
    IO.puts("REDUCTIONS:\t\t #{info.reductions}")
    IO.puts("TOTAL HEAP SIZE:\t #{info.total_heap_size}")
    IO.puts("QUEUE LENGTH:\t\t #{info.message_queue_len}")
    IO.puts(String.duplicate(".", 40))
  end)
end

pretty_print_beam_stats = fn ->
  memory = :erlang.memory()

  IO.puts("BEAM System Statistics\n")
  IO.puts("Total Memory:\t\t #{memory[:total]} bytes")
  IO.puts("Process Memory:\t\t #{memory[:processes]} bytes")
  IO.puts("System Memory:\t\t #{memory[:system]} bytes")
  IO.puts("Atom Memory:\t\t #{memory[:atom]} bytes")
  IO.puts("Binary Memory:\t\t #{memory[:binary]} bytes")
  IO.puts("Code Memory:\t\t #{memory[:code]} bytes")
  IO.puts("ETS Memory:\t\t #{memory[:ets]} bytes")
end

run = fn objects, self, interval ->
  receive do
    :stop ->
      pretty_print_stats.()
      pretty_print_beam_stats.()
      System.stop()
  after
    0 ->
      Enum.each(objects, &Genesis.World.send(&1, :greet))
      Process.sleep(interval)
      self.(objects, self, interval)
  end
end

# mix profile.tprof bench.exs --duration 5 --objects 20 --interval 1000
run.(objects, run, interval)
