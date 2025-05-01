defmodule Genesis.Prefab do
  @moduledoc false
  defstruct [:name, :inherit, :aspects]

  alias __MODULE__
  alias Genesis.Context

  def load(attrs, prefix) do
    name = Map.fetch!(attrs, :name)
    aspects = Map.fetch!(attrs, :aspects)
    inherits = Map.get(attrs, :inherits, [])

    loaded =
      Enum.map(aspects, fn attrs ->
        type = Map.fetch!(attrs, :type)
        props = Map.fetch!(attrs, :props)
        on_conflict = Map.get(attrs, :on_conflict, :merge)

        module = ensure_exists!(type, prefix)

        {module, {on_conflict, props}}
      end)

    inherited =
      inherits
      |> Enum.map(&Context.get(:genesis_prefabs, &1))
      |> Enum.flat_map(& &1.aspects)
      |> Enum.map(&{&1.__struct__, {:inherit, Map.from_struct(&1)}})

    merged = merge_aspects(inherited, loaded)
    final_aspects = Enum.map(merged, fn {m, a} -> m.new(a) end)
    %Prefab{name: name, inherit: inherits, aspects: final_aspects}
  end

  defp ensure_exists!(module, prefix) do
    module = Module.concat(prefix, module)
    # Using this instead of `Code.ensure_loaded!/1` just so we can have
    # a more descriptive error message that helps debugging prefab creation.
    case Code.ensure_loaded(module) do
      {:module, module} -> module
      {:error, _} -> raise "The aspect module #{inspect(module)} doesn't exist"
    end
  end

  defp merge_aspects(inherited, loaded) do
    Enum.reduce(inherited ++ loaded, %{}, fn
      {module, {op, props}}, acc when op in [:inherit, :replace] ->
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
