defmodule Genesis.Entity do
  @moduledoc """
  A struct that represents an entity and contains information about its origin.
  In essence, an entity is simply a unique identifier (reference) that exists within a specific context.
  An entity holds information about the world and context it belongs to, along with a unique identification hash.

  ## Fields

    * `:ref` - the unique reference for this entity
    * `:context` - the context where the entity lives
    * `:world` - the world the entity was instantiated on
    * `:hash` - a checksum that represents the entity's identity
    * `:name` - the name the entity was registered with
    * `:parent` - the entity this was cloned from
  """
  @type t :: %__MODULE__{
          context: pid(),
          world: pid() | nil,
          ref: reference(),
          hash: binary(),
          name: binary() | nil,
          parent: t() | nil
        }

  defstruct [:context, :world, :ref, :hash, :name, :parent]

  alias __MODULE__

  @doc """
  Creates a new entity.

  Options:
    * `:context` - the context PID where the entity lives (required)
    * `:world` - the world GenServer PID if entity belongs to a world (optional)
    * `:name` - an optional name for the entity (optional)
    * `:parent` - the parent entity this was cloned from (optional)
  """
  def new(opts) do
    ref = make_ref()
    name = Keyword.get(opts, :name)
    world = Keyword.get(opts, :world)
    parent = Keyword.get(opts, :parent)
    context = Keyword.fetch!(opts, :context)

    identity = {world, context, ref}
    hash = :crypto.hash(:sha, :erlang.term_to_binary(identity))

    %Entity{
      ref: ref,
      hash: hash,
      name: name,
      world: world,
      parent: parent,
      context: context
    }
  end

  @doc """
  Returns true when two entities represent the same identity.
  """
  def equal?(%Entity{hash: h1}, %Entity{hash: h2}), do: h1 == h2

  @doc """
  Returns true when the entity was created on this node.
  """
  def local?(%Entity{ref: ref}), do: node(ref) == node()

  @doc """
  Returns true when two entities share the same context.
  """
  def colocated?(%Entity{context: c1}, %Entity{context: c2}), do: c1 == c2

  @doc """
  Returns true when the entity has a name.
  """
  def named?(%Entity{name: name}), do: not is_nil(name)

  @doc """
  Returns true when the entity is a child of another entity.
  """
  def child?(%Entity{parent: parent}), do: not is_nil(parent)
end

defimpl Inspect, for: Genesis.Entity do
  import Inspect.Algebra

  def inspect(entity, opts) do
    name = display_name(entity, opts)
    hierarchy = display_hierarchy(entity, opts)
    concat(["#Entity<", name, hierarchy, ">"])
  end

  defp display_hierarchy(entity, opts) do
    hierarchy = format_hierarchy(entity.parent, opts)

    if opts.pretty,
      do: concat("@", Enum.join(hierarchy, "/")),
      else: concat("@", to_string(length(hierarchy)))
  end

  defp format_hierarchy(nil, _opts), do: []

  defp format_hierarchy(entity, opts),
    do: [display_name(entity, opts) | format_hierarchy(entity.parent, opts)]

  defp display_name(%{name: nil} = entity, _opts), do: format_hash(entity.hash)
  defp display_name(entity, opts), do: format_name(entity.name, opts)

  defp format_name(name, opts), do: truncate(name, opts)
  defp format_hash(hash), do: binary_part(Base.encode16(hash, case: :lower), 0, 7)

  defp truncate(string, opts) do
    if String.length(string) >= opts.limit,
      do: String.slice(string, 0, opts.limit) <> "...",
      else: string
  end
end
