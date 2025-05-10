defmodule Genesis.Prefab do
  @moduledoc false
  defstruct [:name, :inherit, :aspects]

  alias __MODULE__
  alias Genesis.Context
  alias Genesis.Naming

  def load(attrs, registered) do
    name = Map.fetch!(attrs, :name)
    aspects = Map.fetch!(attrs, :aspects)
    inherits = Map.get(attrs, :inherits, [])

    # Create an alias/module lookup from registered aspects
    lookup = Map.new(registered, &{elem(&1, 1), elem(&1, 0)})

    declared =
      Enum.map(aspects, fn {as, props} ->
        module = Map.fetch!(lookup, as)
        loaded = Code.ensure_loaded!(module)
        {loaded, {:merge, props}}
      end)

    inherited =
      inherits
      |> Enum.map(&Context.get!(Naming.table(:prefabs), &1))
      |> Enum.flat_map(& &1.aspects)
      |> Enum.map(&{&1.__struct__, {:inherit, Map.from_struct(&1)}})

    merged_aspects = merge_aspects(inherited, declared)
    final_aspects = Enum.map(merged_aspects, fn {module, props} -> module.new(props) end)

    %Prefab{name: name, inherit: inherits, aspects: final_aspects}
  end

  defp merge_aspects(inherited, declared) do
    Enum.reduce(inherited ++ declared, %{}, fn
      {module, {:inherit, props}}, acc ->
        Map.put(acc, module, props)

      {module, {:merge, props}}, acc ->
        case Map.fetch(acc, module) do
          {:ok, existing} ->
            merged = Map.merge(existing, props)
            Map.put(acc, module, merged)

          :error ->
            Map.put(acc, module, props)
        end
    end)
  end
end
