defmodule Genesis.Prefab do
  @moduledoc """
  Prefabs are templates for creating entities with predefined components and properties.
  They can extend other prefabs to inherit their components, and override or merge properties.

  ## Usage

  Prefabs are defined using maps and registered with the manager:

      Genesis.Manager.register_prefab(%{
        name: "Spaceship",
        components: %{
          "engine" => %{speed: 50, fuel: 100},
          "shields" => %{strength: 50},
          "weapons" => %{lasers: 2, torpedoes: 0}
        }
      })

      spaceship = Genesis.World.create(world, "Spaceship")

  ## Extending Prefabs

  Prefabs can extend other prefabs to inherit its components:

      Genesis.Manager.register_prefab(%{
        name: "X-Wing",
        extends: ["Spaceship"],
        components: %{
          "engine" => %{speed: 100, fuel: 200},
          "shields" => %{strength: 40}
        }
      })

      xwing = Genesis.World.create(world, "X-Wing")

  When a prefab extends another, it inherits all components from its parent.
  Optionally, a children can override specific component properties by declaring them again.

  In this particular example, an instance of a X-Wing will inherit the `weapons` component from `Spaceship`
  and override both the `engine` and `shields` components with new properties that are specific to the X-Wing.

  ## Relationships

  Genesis is a minimalistic ECS library focused on the core building blocks. It doesn't enforce patterns
  for modeling relationships, hierarchies, or complex pipelines that convert authoring data into runtime data.

  Even though you can quite easily represent relationships by referencing entities inside of components,
  we recommend avoiding using prefabs to represent deeply hierarchical data. For such cases, it's often
  better to break out of ECS and use a dedicated solution to correctly load your entities into the system.
  """

  defstruct name: nil, extends: [], components: []

  alias __MODULE__

  @doc false
  def load(attrs) do
    name = Map.fetch!(attrs, :name)
    extends = Map.get(attrs, :extends, [])

    declared = Map.fetch!(attrs, :components)
    extended = fetch_parent_components(extends, name)

    # Merge the children components over the ones inherited from parents.
    merged_components = Genesis.Utils.merge_components(extended, declared)
    %Prefab{name: name, extends: extends, components: merged_components}
  end

  defp fetch_parent_components(extends, child_name) do
    Enum.reduce(extends, %{}, fn parent_name, acc ->
      case Genesis.Context.fetch(Genesis.Prefabs, parent_name) do
        {_entity, parent_components} ->
          Map.merge(acc, Genesis.Utils.extract_properties(parent_components))

        nil ->
          raise ArgumentError,
                "prefab #{inspect(child_name)} extends #{inspect(parent_name)} but #{inspect(parent_name)} is not registered"
      end
    end)
  end
end
