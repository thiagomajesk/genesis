################################################################################
# Dependencies
################################################################################

Mix.install([
  {:genesis, path: File.cwd!()},
  {:phoenix_playground, "~> 0.1.8"},
  {:phoenix_live_dashboard, "~> 0.7"}
])

################################################################################
# Setup
################################################################################

defmodule Evolution do
  @evolutions %{
    "🐛" => "🦋",
    "🦋" => "💀",
    "🐸" => "🐊",
    "🦆" => "🦢",
    "🐟" => "🦈",
    "🐕" => "🐺",
    "🐑" => "🐏",
    "🐄" => "🐃",
    "🐍" => "🐉",
    "🦎" => "🦖",
    "🐀" => "🐿️",
    "🐘" => "🦣",
    "💀" => "👻"
  }

  def initial, do: Map.keys(@evolutions)
  def next(emoji), do: Map.get(@evolutions, emoji)

  def name("🐛"), do: "Caterpillar"
  def name("🦋"), do: "Butterfly"
  def name("💀"), do: "Skull"
  def name("🐸"), do: "Frog"
  def name("🐊"), do: "Crocodile"
  def name("🦆"), do: "Duck"
  def name("🦢"), do: "Swan"
  def name("🐟"), do: "Fish"
  def name("🦈"), do: "Shark"
  def name("🐕"), do: "Dog"
  def name("🐺"), do: "Wolf"
  def name("🐑"), do: "Sheep"
  def name("🐏"), do: "Ram"
  def name("🐄"), do: "Cow"
  def name("🐃"), do: "Water Buffalo"
  def name("🐍"), do: "Snake"
  def name("🐉"), do: "Dragon"
  def name("🦎"), do: "Lizard"
  def name("🦖"), do: "T-Rex"
  def name("🐀"), do: "Rat"
  def name("🐿️"), do: "Squirrel"
  def name("🐘"), do: "Elephant"
  def name("🦣"), do: "Mammoth"
end

defmodule Sprite do
  use Genesis.Aspect, events: [:morph]

  prop :emoji, :binary

  def handle_event(:morph, object, args) do
    %{emoji: emoji} = Sprite.get(object)

    if not is_nil(emoji) and :rand.uniform() <= 0.1 do
      Genesis.World.send(object, :greet)
      Sprite.update(object, :emoji, &Evolution.next/1)
    end

    {:cont, args}
  end
end

defmodule Moniker do
  use Genesis.Aspect, events: [:greet]

  prop :name, :binary

  def handle_event(:greet, object, args) do
    %{name: name} = Moniker.get(object)
    IO.puts("#{name} is evolving!")
    {:cont, args}
  end
end

Genesis.World.register_aspect(Sprite)
Genesis.World.register_aspect(Moniker)

################################################################################
# LiveView
################################################################################
defmodule DemoLive do
  use Phoenix.LiveView

  def render(assigns) do
    ~H"""
    <section>
      <header>
        <span>
          <strong>Max objects</strong>
          <small>{@max_objects}</small>
        </span>
        <span>
          <strong>Tick rate</strong>
          <small>{@tick_rate}</small></span>
        <span>
          <strong>Tick count</strong>
          <small>{@tick_count}</small></span>
        <span>
          <strong>Tick timer</strong>
          <small>{inspect(@tick_timer)}</small></span>
      </header>
      <div style="display: flex; flex-wrap: wrap; margin-top: 1rem; gap: 0.2rem">
        <span :for={object <- Enum.take(@objects, 1000)} style="display: flex; flex-direction: column; align-items: center; width: 2.5rem; height: 2.5rem; border: 1px solid gray">
          <small>{object}</small>
          {Sprite.get(object).emoji}
        </span>
      </div>
    </section>
    """
  end

  def mount(_params, _session, socket) do
    if connected?(socket), do: send(self(), :init)

    {:ok,
     socket
     |> assign(:objects, [])
     |> assign(:tick_rate, 20)
     |> assign(:tick_count, 0)
     |> assign(:tick_timer, nil)
     |> assign(:max_objects, 1000)}
  end

  def handle_info(:init, socket) do
    stream = Stream.repeatedly(&Genesis.World.new/0)

    objects =
      stream
      |> Stream.map(&attach_aspects/1)
      |> Enum.take(socket.assigns.max_objects)

    {:noreply,
     socket
     |> schedule_next_tick()
     |> assign(:objects, objects)}
  end

  def handle_info(:tick, socket) do
    objects = socket.assigns.objects
    Enum.each(objects, &Genesis.World.send(&1, :morph))

    # Trigger a re-render by sorting the objects
    sorted = Enum.sort_by(objects, &Sprite.get/1, :desc)

    {:noreply,
     socket
     |> schedule_next_tick()
     |> assign(:objects, sorted)
     |> update(:tick_count, &(&1 + 1))}
  end

  defp attach_aspects(object) do
    emoji = Enum.random(Evolution.initial())
    adjective = Enum.random(["Angry", "Happy", "Sleepy", "Curious", "Brave"])
    name = "#{adjective} #{Evolution.name(emoji)}"

    with :ok <- Sprite.attach(object, emoji: emoji),
         :ok <- Moniker.attach(object, name: name),
         do: object
  end

  defp schedule_next_tick(socket) do
    time = div(:timer.seconds(1), socket.assigns.tick_rate)
    timer = Process.send_after(self(), :tick, time)
    assign(socket, tick_timer: timer)
  end
end

################################################################################
# Router
################################################################################

defmodule DemoRouter do
  use Phoenix.Router
  import Phoenix.LiveView.Router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:put_root_layout, html: {PhoenixPlayground.Layout, :root})
    plug(:put_secure_browser_headers)
  end

  scope "/" do
    pipe_through(:browser)

    live("/", DemoLive)
    live_dashboard("/dashboard")
  end
end

PhoenixPlayground.start(plug: DemoRouter, open_browser: false)
