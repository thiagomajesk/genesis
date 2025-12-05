defmodule Genesis do
  @moduledoc """
  Genesis is a framework for building ECS-based games in Elixir.
  It provides a flexible way to manage game entities, components, and event-driven game logic.

  # What is ECS?

  Entity Component System (ECS) is an architectural pattern commonly used in game development that promotes
  composition over inheritance and separates data from behavior. At its core, an ECS consists of:

  - **Entities**: Unique identifiers that represent game objects (a player, an enemy, a tree, etc.)
  - **Components**: Plain data containers that define aspects of an entity (position, health, inventory)
  - **Systems**: Logic that operates on entities with specific sets of components

  ## Entities and Components

  In Genesis, entities are unique references that can have components attached to them. Each entity acts as a container
  of components, which together define the entity behavior and state. Components on the other hand are the modular pieces of state or behavior
  that can be attached to game entities. They encapsulate specific functionality, allowing for great granularity when modeling behaviors.
  By composing entities from different components, you can create complex behaviors from simple, reusable building blocks.

  ## The S is silent

  Most ECS implementations heavily rely on "Systems" to run game logic in tight loops while Genesis focus on the core building blocks and embraces
  an **event-driven architecture** inspired by the design philosophies of [Caves of Qud](https://www.cavesofqud.com/) and [ADOM (Ancient Domains of Mystery)](https://www.adom.de/).

  This event-driven approach is particularly powerful for turn-based games, roguelikes, simulation games, and any scenario where game logic is better expressed
  as reactions to discrete events rather than a tight loop. Altough Genesis uses events as the main communication mechanism, it doesn't dictate how your main game loop should work

  ## Events

  Events are messages that are sent to entities to trigger behavior in their components.
  When an event is sent to an entity, it's dispatched to all components registered to handle that event.
  The events are then processed sequentially in the order they were registered within the Genesis.Manager.

  Events sent to the same entity are guaranteed to be processed in order, while events sent to
  different entities are processed concurrently. This ensures consistency in entity state while maximizing performance.

  Each game world runs a GenStage pipeline to handle event dispatching and processing efficiently.
  This pipeline is composed of three core components:

  **Herald (Producer)** - Receives events from the world and distributes them across multiple partitions
  using consistent hashing based on the target entity. This ensures all events for the same entity
  always go to the same partition, enabling ordered processing.

  **Envoy (Producer-Consumer)** - One per partition. Maintains separate queues for each entity within
  its partition. When events arrive for an entity, they are queued. The Envoy batches events
  for the same entity together and emits them as a single GenStage event payload to ensure only one
  worker processes a given entity at a time, preventing race conditions.

  **Scribe (Consumer)** - Supervises worker processes that execute the actual event processing. Each worker
  receives a batch of events for a single entity, processes them sequentially, then notifies the
  Envoy when finished so more events can be dispatched for that entity.

  The topology looks like the following (with 2 partitions):

                              ┌──> [Envoy P0] ---> [Scribe] -----> [Worker]
        [World] ──> [Herald] ─┤
                              └──> [Envoy P1] ---> [Scribe] ──┬──> [Worker]
                                                              └──> [Worker]

  Here's how events flow through the system (using 2 partitions as an example):

    1) Events arrive at the World and are dispatched to the Herald

            entity 1 :attack  ──┐
            entity 1 :move    ──┤
            entity 2 :heal    ──┼─> [World] ---(notifies)---> [Herald]
            entity 3 :move    ──┤
            entity 3 :attack  ──┘

    2) The Herald routes them to partitions by hashing the entity:

            Envoy P0 - [{1, :move}, {1, :attack}]
            Envoy P1 - [{2, :heal}, {3, :attack}, {3, :move}]

    3) Each Envoy groups events per entity in separate "lanes" (queues):

            Envoy P0 - %{"1" => [:move, :attack]}
            Envoy P1 - %{"2" => [:heal], "3" => [:attack, :move]}

    4) Scribe assigns each entity's batch to a worker for sequential processing:

            Worker A - {1, [:move, :attack]}
            Worker B - {2, [:heal]}
            Worker C - {3, [:attack, :move]}

  This architecture provides:
  - **Concurrency**: Events for different entities are processed in parallel across partitions
  - **Consistency**: Events for the same entity are always processed in order
  - **Scalability**: The number of partitions can be configured based on workload
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      Genesis.Manager,
      {Task.Supervisor, name: Genesis.TaskSupervisor},
      {Registry, keys: :unique, name: Genesis.Registry},
      {Genesis.Context, name: Genesis.Prefabs, restart: :permanent},
      {Genesis.Context, name: Genesis.Components, restart: :permanent}
    ]

    Supervisor.start_link(children, strategy: :one_for_all, name: Genesis.Supervisor)
  end
end
