defmodule Genesis.Prefab do
  @moduledoc false

  defstruct [:name, :inherit, :aspects]

  alias __MODULE__

  def load(attrs, opts \\ []) do
    registered_prefabs = Keyword.get(opts, :registered_prefabs, [])
    registered_aspects = Keyword.get(opts, :registered_aspects, [])

    aspects_lookup = Map.new(registered_aspects)
    prefabs_lookup = Map.new(registered_prefabs)

    name = Map.fetch!(attrs, :name)
    aspects = Map.fetch!(attrs, :aspects)
    inherits = Map.get(attrs, :inherits, [])

    declared =
      Enum.map(aspects, fn {as, props} ->
        module = Map.fetch!(aspects_lookup, as)
        loaded = Code.ensure_loaded!(module)
        {loaded, {:merge, props}}
      end)

    inherited =
      Enum.flat_map(inherits, fn name ->
        %{aspects: aspects} = Map.fetch!(prefabs_lookup, name)
        Enum.map(aspects, &{&1.__struct__, {:inherit, Map.from_struct(&1)}})
      end)

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
