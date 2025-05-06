defmodule Genesis.Value do
  @doc false
  defguard is_props(term) when is_list(term) or (is_map(term) and not is_struct(term))

  @doc """
  Defines a property for the aspect.
  """
  defmacro prop(name, type, opts \\ []) do
    quote bind_quoted: binding() do
      not is_atom(name) && raise "prop name must be an atom, got: #{inspect(name)}"

      types = [:atom, :binary, :float, :integer, :boolean, :datetime]
      type not in types && raise "prop type must be a scalar type, got: #{inspect(type)}"

      default_value = Keyword.get(opts, :default)
      Genesis.Value.check_value(default_value, type)

      Module.put_attribute(__MODULE__, :properties, {name, type, opts})
    end
  end

  @doc """
  Casts the given attrs using the given props definition.
  """
  def cast(_attrs, []), do: %{}

  def cast(attrs, props) do
    attrs
    |> Enum.into(%{})
    |> merge_defaults(props)
    |> tap(&validate(&1, props))
    |> cast_attrs(props)
  end

  @doc false
  def to_fields([]), do: []

  def to_fields(properties) do
    Enum.map(properties, fn {name, _type, opts} ->
      {name, Keyword.get(opts, :default)}
    end)
  end

  @doc false
  def check_value(nil, _type), do: nil
  def check_value(value, :binary) when is_binary(value), do: value
  def check_value(value, :integer) when is_integer(value), do: value
  def check_value(value, :float) when is_float(value), do: value
  def check_value(value, :boolean) when is_boolean(value), do: value
  def check_value(value, :atom) when is_atom(value), do: value
  def check_value(value, :datetime) when is_struct(value, DateTime), do: value

  def check_value(value, type),
    do: raise("value #{inspect(value)} is not valid for prop type #{type}")

  defp merge_defaults(attrs, props) do
    Enum.reduce(props, attrs, fn {name, _type, opts}, acc ->
      Map.put_new(acc, name, Keyword.get(opts, :default))
    end)
  end

  defp validate(attrs, props) do
    Enum.each(props, fn {name, _type, opts} ->
      required? = Keyword.get(opts, :required, false)

      if required? && empty_value?(Map.get(attrs, name)) do
        raise "required property #{inspect(name)} cannot be empty"
      end
    end)
  end

  defp empty_value?(nil), do: true
  defp empty_value?(value) when is_binary(value), do: String.trim(value) == ""
  defp empty_value?(_), do: false

  defp cast_attrs(attrs, props) do
    Map.new(props, fn {name, type, _opts} ->
      value = Map.get(attrs, name)
      {name, check_value(value, type)}
    end)
  end
end
