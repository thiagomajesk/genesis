defmodule Genesis.Prefab do
  @moduledoc """
  Provides querying capabilities for prefabs registered in the manager.

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

  import Genesis.Utils, only: [is_name: 1]

  defstruct name: nil, extends: [], components: []

  alias __MODULE__

  @doc """
  Returns all prefab components of the given type.
  Returns a list of tuples containing the prefab and the component struct.

  ## Examples

      iex> Genesis.Prefab.all(Health)
      [{entity_1, %Health{current: 100}}, {entity_2, %Health{current: 50}}]
  """
  def all(component_type) when is_atom(component_type),
    do: Genesis.Query.__all__(:prefabs, component_type)

  @doc """
  Retrieves the component attached to a prefab.
  Returns the component struct if present or `nil`.

  ## Examples

      iex> Genesis.Prefab.get(Health, entity_1)
      %Health{current: 100}
  """
  def get(component_type, entity, default \\ nil) when is_atom(component_type),
    do: Genesis.Query.__get__(:prefabs, component_type, entity, default)

  @doc """
  Returns all prefab components that match the given properties.

  ## Examples

      iex> Genesis.Prefab.match(Moniker, name: "Tripida")
      [{entity_1, %Moniker{name: "Tripida"}}]
  """
  def match(component_type, properties) when is_atom(component_type),
    do: Genesis.Query.__match__(:prefabs, component_type, properties)

  @doc """
  Returns all prefab components that have the given property with a value greater than or equal to the given minimum.

  ## Examples

      iex> Genesis.Prefab.at_least(Health, :current, 50)
      [{entity_1, %Health{current: 75}}]
  """
  def at_least(component_type, property, value)
      when is_atom(component_type) and is_atom(property) and is_integer(value),
      do: Genesis.Query.__at_least__(:prefabs, component_type, property, value)

  @doc """
  Returns all prefab components that have the given property with a value less than or equal to the given maximum.

  ## Examples

      iex> Genesis.Prefab.at_most(Health, :current, 50)
      [{entity_1, %Health{current: 25}}]
  """
  def at_most(component_type, property, value)
      when is_atom(component_type) and is_atom(property) and is_integer(value),
      do: Genesis.Query.__at_most__(:prefabs, component_type, property, value)

  @doc """
  Returns all prefab components that have the given property with a value between the given minimum and maximum (inclusive).

  ## Examples

      iex> Genesis.Prefab.between(Health, :current, 50, 100)
      [{entity_1, %Health{current: 75}}]
  """
  def between(component_type, property, min, max)
      when is_atom(component_type) and is_atom(property) and
             is_integer(min) and is_integer(max) and min <= max,
      do: Genesis.Query.__between__(:prefabs, component_type, property, min, max)

  @doc """
  Checks if a prefab exists in the prefabs registry.
  Returns `true` if found, or `false` otherwise.
  """
  def exists?(entity_or_name)
      when is_reference(entity_or_name) or is_name(entity_or_name),
      do: Genesis.Query.__exists__(:prefabs, entity_or_name)

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
      case Genesis.Registry.fetch(:prefabs, parent_name) do
        {_entity, parent_components} ->
          Map.merge(acc, Genesis.Utils.extract_properties(parent_components))

        nil ->
          raise ArgumentError,
                "prefab #{inspect(child_name)} extends #{inspect(parent_name)} but #{inspect(parent_name)} is not registered"
      end
    end)
  end
end
