# Genesis

Genesis is an ECS (Entity Component System) library for Elixir focused on easy of use and ergonomics. This library is heavily inspired by the architecture used in the game [Caves of Qud](https://www.cavesofqud.com/) and [ADOM (Ancient Domains of Mystery)](https://www.adom.de/).

> [!TIP]
> If you don't yet know what an Entity Component System is, the [ECS FAQ repository](https://github.com/SanderMertens/ecs-faq) from the creator of [Flecs](https://www.flecs.dev/) (a very popular ECS library) is a very good resource to get a good overview.

In the case of Genesis, the ECS terminology is used quite loosely as we don't make any assumptions about your game loop looks like. Genesis was created to take advantage Elixir strenghts to create an event-driven architecture that is very usefull for building turn-based games. In fact, the whole idea for this library is based on these talks from Thomas Biskup and Briand Bucklew:

- [AI in Qud and Sproggiwood](https://www.youtube.com/watch?v=4uxN5GqXcaA)
- [Data-Driven Engines of Qud and Sproggiwood](https://www.youtube.com/watch?v=U03XXzcThGU)
- [There be dragons: Entity Component Systems for Roguelikes](https://www.youtube.com/watch?v=fGLJC5UY2o4)

## Installation

```elixir
def deps do
  [
    {:genesis, "~> 0.1.0"}
  ]
end
```

## Special Thanks ❤️

A big thanks to both Brian Bucklew and Thomas Biskup for the inspiring talks. The Caves of Qud modding guides in particular was a great resource to see what this architecture would be capable of.

Special thanks to other ECS libraries that influenced the development of Genesis:

- [Geotic](https://github.com/ddmills/geotic) - A friendly JavaScript ECS library that is also based on the the Briand Bucklew and Thomas Biskup talks. Finding this library in the midst of traditional ECS implementations was a breath of fresh.
- [ECSx](https://github.com/ecsx-framework/ECSx) - Another excellent ECS library with a more traditional approach. ECSx paved the way as one of the very first Elixir implementations. It greatly impacted some of Genesis's design choices.
