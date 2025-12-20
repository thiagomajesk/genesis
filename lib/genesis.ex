defmodule Genesis do
  @moduledoc """
  Genesis is a framework for building ECS-based games in Elixir.
  It provides a flexible and efficient way to manage game entities, their components, and the events that drive game logic.

  ## Entities
  Entities are unique references that can have components attached to them, which define their behavior and state.

  ## Components
  Components are modular pieces of state or behavior that can be attached to game entities. They encapsulate specific functionality,
  allowing for great granularity when modeling behaviors like health, position, inventory, etc.

  ## Prefabs
  Prefabs are templates for creating game entities with predefined sets of components and properties.
  They allow for rapid instantiation of complex entities that have shared information with their parents.

  ## Events
  Events are messages that are sent to entities to trigger behavior in their components.

  ### Event routing

  Events sent to the same entity are guaranteed to be processed in order, while events sent to
  different entities are processed concurrently. This ensures consistency in entity state while maximizing performance.

  Each game world runs a GenStage pipeline to handle event dispatching and processing efficiently.
  This pipeline is composed of three core components:

  **Herald (Producer)** - Receives Genesis Events from the world and distributes them across multiple partitions
  using consistent hashing based on the target entity. This ensures all events for the same entity
  always go to the same partition, enabling ordered processing.

  **Envoy (Producer-Consumer)** - One per partition. Maintains separate queues for each entity within
  its partition. When Genesis Events arrive for an entity, they are queued. The Envoy batches Genesis Events
  for the same entity together and emits them as a single GenStage event payload to ensure only one
  worker processes a given entity at a time, preventing race conditions.

  **Scribe (Consumer)** - Supervises worker processes that execute the actual event processing. Each worker
  receives a batch of Genesis Events for a single entity, processes them sequentially, then notifies the
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
    :ok = Genesis.Manager.init()
    Supervisor.start_link([], strategy: :one_for_one, name: Genesis.Supervisor)
  end
end
