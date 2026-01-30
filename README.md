# Genesis

Genesis is an ECS (Entity Component System) library for Elixir focused on ease of use and ergonomics. This library is heavily inspired by the architecture used in the game [Caves of Qud](https://www.cavesofqud.com/) and [ADOM (Ancient Domains of Mystery)](https://www.adom.de/).

> [!TIP]
> If you don't yet know what an Entity Component System is, the [ECS FAQ repository](https://github.com/SanderMertens/ecs-faq) from the creator of [Flecs](https://www.flecs.dev/) (a very popular ECS library) is a very good resource to get a good overview.

In the case of Genesis, the ECS terminology is used quite loosely as we don't make any assumptions about what your game loop looks like. Genesis was created to take advantage of Elixir strengths to create an event-driven architecture that is very useful for building certain types of games. In fact, the whole idea for this library is based on the following talks from Thomas Biskup and Brian Bucklew:

- [AI in Qud and Sproggiwood](https://www.youtube.com/watch?v=4uxN5GqXcaA)
- [Data-Driven Engines of Qud and Sproggiwood](https://www.youtube.com/watch?v=U03XXzcThGU)
- [There be dragons: Entity Component Systems for Roguelikes](https://www.youtube.com/watch?v=fGLJC5UY2o4)

## Installation

```elixir
def deps do
  [
    {:genesis, "~> 0.10.0"}
  ]
end
```

## Getting Started

This tutorial will walk you through creating a combat system where a sword can attack and potentially ignite a flammable barrel.

### Defining Components

Components are modular pieces of behavior that can be attached to game entities. Let's start with a `Durability` component that handles damage:

```elixir
defmodule Durability do
  use Genesis.Component, events: [:attack]

  prop :durability, :integer, default: 100

  def handle_event(:attack, event) do
    update(event.entity, :durability, &(&1 - event.args.damage))
    {:cont, event}
  end
end
```

Next, let's create a `Flammable` component that can be ignited by fire damage:

```elixir
defmodule Flammable do
  use Genesis.Component, events: [:attack]

  prop :burning, :boolean, default: false

  def handle_event(:attack, event) do
    if event.args.type == :fire do
      update(event.entity, burning: true)
    end
    {:cont, event}
  end
end
```

### Registering Components

Before using components, they need to be registered with the manager:

```elixir
Genesis.Manager.register_components([Durability, Flammable])
```

### Starting a World and Creating Entities

Now we can create a world, instantiate entities, and attach components:

```elixir
{:ok, world} = Genesis.World.start_link()

barrel = Genesis.World.create(world)

Flammable.attach(barrel)
Durability.attach(barrel, durability: 50)
```

### Dispatching Events

Let's attack the barrel with different weapons:

```elixir
Genesis.World.send(world, barrel, :attack, %{damage: 10, type: :physical})

Durability.get(barrel)
#=> %Durability{durability: 40}

Flammable.get(barrel)
#=> %Flammable{burning: false}

Genesis.World.send(world, barrel, :attack, %{damage: 15, type: :fire})

Durability.get(barrel)
#=> %Durability{durability: 25}

Flammable.get(barrel)
#=> %Flammable{burning: true}
```

This example demonstrates the core Genesis workflow: defining components with behavior, registering them, instantiating entities in a world, attaching components, and dispatching events to drive game logic.

## Special Thanks ❤️

A big thanks to both Brian Bucklew and Thomas Biskup for the inspiring talks. The Caves of Qud modding guides in particular were a great resource to see what this architecture would be capable of.

Special thanks to other ECS libraries that influenced the development of Genesis:

- [Geotic](https://github.com/ddmills/geotic) - A friendly JavaScript ECS library that is also based on the Brian Bucklew and Thomas Biskup talks. Finding this library in the midst of traditional ECS implementations was a breath of fresh air.
- [ECSx](https://github.com/ecsx-framework/ECSx) - Another excellent ECS library with a more traditional approach. ECSx paved the way as one of the very first Elixir implementations. It greatly impacted some of Genesis's design choices.
