defmodule Genesis.Entity do
  @moduledoc """
  An opaque type that represents an entity and contains information about its origin.
  In essence, an entity is simply a unique identifier (reference) that exists within a specific context.
  An entity holds information about the node, world, and context it belongs to, along with a unique identification hash.
  """

  @type t :: %__MODULE__{
          node: node(),
          context: pid(),
          world: pid() | nil,
          ref: reference(),
          hash: binary(),
          name: binary() | nil,
          parent: binary() | nil
        }

  defstruct [:node, :context, :world, :ref, :hash, :name, :parent]

  @doc """
  Creates a new entity.

  Options:
    * `:context` - the context PID where the entity lives (required)
    * `:world` - the world GenServer PID if entity belongs to a world (optional)
    * `:name` - an optional name for the entity (optional)
    * `:parent` - the parent entity name this was cloned from (optional)
  """
  def new(opts) do
    ref = make_ref()
    name = Keyword.get(opts, :name)
    world = Keyword.get(opts, :world)
    parent = Keyword.get(opts, :parent)
    context = Keyword.fetch!(opts, :context)

    identity = {node(), world, context, ref}
    hash = :crypto.hash(:sha, :erlang.term_to_binary(identity))

    %__MODULE__{
      ref: ref,
      hash: hash,
      name: name,
      node: node(),
      world: world,
      parent: parent,
      context: context
    }
  end
end

defimpl Inspect, for: Genesis.Entity do
  import Inspect.Algebra

  def inspect(%{hash: hash, name: nil}, _opts) do
    concat(["#Entity<", format_hash(hash), ">"])
  end

  def inspect(%{hash: hash, name: name, parent: parent}, _opts) do
    concat(["#Entity<", space(format_hash(hash), format_name(name, parent)), ">"])
  end

  defp format_name(name, nil), do: concat(["(", name, ")"])
  defp format_name(name, parent), do: concat(["(", name, "/", parent, ")"])
  defp format_hash(hash), do: binary_part(Base.encode16(hash, case: :lower), 0, 10)
end
