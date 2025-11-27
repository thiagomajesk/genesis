defmodule Genesis do
  @moduledoc """
  Genesis is a framework for building entity-component-system (ECS) based games in Elixir.
  It provides a flexible and efficient way to manage game objects, their aspects (components),
  and the events that drive game logic.

  ## Objects
  Objects are the core entities in the game world. They are identified by unique IDs and can
  have multiple aspects attached to them, which define their behavior and state.

  ## Aspects
  Aspects are modular pieces of state or behavior that can be attached to game objects. They encapsulate specific functionality,
  allowing for great granularity when modeling behaviors like health, position, inventory, etc.

  ## Prefabs
  Prefabs are templates for creating game objects with predefined sets of aspects and properties.
  They allow for rapid instantiation of complex objects that have shared information with their parents.

  ## Events
  Events are messages that are sent to objects to trigger behavior in their aspects.

  ### Event routing

  Events sent to the same object are guaranteed to be processed in order, while events sent to
  different objects are processed concurrently. This ensures consistency in object state while maximizing performance.

  Each game world runs a GenStage pipeline to handle event dispatching and processing efficiently.
  This pipeline is composed of three core components:

  **Herald (Producer)** - Receives Genesis Events from the world and distributes them across multiple partitions
  using consistent hashing based on the target object ID. This ensures all events for the same object
  always go to the same partition, enabling ordered processing.

  **Envoy (Producer-Consumer)** - One per partition. Maintains separate queues for each object within
  its partition. When Genesis Events arrive for an object, they are queued. The Envoy batches Genesis Events
  for the same object together and emits them as a single GenStage event payload to ensure only one
  worker processes a given object at a time, preventing race conditions.

  **Scribe (Consumer)** - Supervises worker processes that execute the actual event processing. Each worker
  receives a batch of Genesis Events for a single object, processes them sequentially, then notifies the
  Envoy when finished so more events can be dispatched for that object.

  The topology looks like the following:

        [World] --> [Herald] --> [Envoy] --> [Scribe] --> [Worker]

  Here's how events flow through the system (using 2 partitions as an example):

    1) Events arrive at the World and are dispatched to the Herald

            object 1 :attack  ──┐
            object 1 :move    ──┤
            object 2 :heal    ──┼─> [World] ---(notifies)---> [Herald]
            object 3 :move    ──┤
            object 3 :attack  ──┘

    2) The Herald routes them to partitions by hashing the object ID:

            Envoy P0 - [{1, :move}, {1, :attack}]
            Envoy P1 - [{2, :heal}, {3, :attack}, {3, :move}]

    3) Each Envoy groups events per object in separate "lanes" (queues):

            Envoy P0 - %{"1" => [:move, :attack]}
            Envoy P1 - %{"2" => [:heal], "3" => [:attack, :move]}

    4) Scribe assigns each object's batch to a worker for sequential processing:

            Worker A - {1, [:move, :attack]}
            Worker B - {2, [:heal]}
            Worker C - {3, [:attack, :move]}

  This architecture provides:
  - **Concurrency**: Events for different objects are processed in parallel across partitions
  - **Consistency**: Events for the same object are always processed in order
  - **Scalability**: The number of partitions can be configured based on workload
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [Genesis.Manager]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
