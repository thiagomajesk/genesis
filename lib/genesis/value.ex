defmodule Genesis.Value do
  @doc """
  Defines a property for an Aspect.

  ## Examples

      prop :name, :binary, required: true
      prop :age, :integer, default: 0

  The supported types are:  `:atom`, `:binary`, `:boolean`, `:datetime`,
  `:float`, `:integer`, `:pid`, `:ref`.

  ## Options

    * `:required` - when set to `true`, the property must be provided when
    creating or updating the aspect. Defaults to `false`.

    * `:default` - specifies a default value for the property if none is provided.

  ## Validation

  The property value is validated against its type when the aspect is created
  or updated. If the value does not match the type, an `ArgumentError` is raised.
  """
  defmacro prop(name, type, opts \\ []) do
    quote bind_quoted: binding() do
      not is_atom(name) && raise "The property name must be an atom, got: #{inspect(name)}"

      validators = Genesis.Value.validators()

      case Map.fetch(validators, type) do
        {:ok, validator} ->
          default_value = Keyword.get(opts, :default)
          Genesis.Value.ensure_type!(default_value, type)
          Module.put_attribute(__MODULE__, :properties, {name, type, opts})

        :error ->
          valid_types = Map.keys(validators)

          raise ArgumentError,
                "The property type must be one of #{inspect(valid_types)}, got: #{inspect(type)}"
      end
    end
  end

  @doc """
  Casts attrs against the given props definition.
  """
  def cast(_attrs, []), do: %{}

  def cast(attrs, props) do
    attrs
    |> normalize()
    |> merge_defaults(props)
    |> build_props(props)
  end

  @doc """
  Checks that the given value can be used as a prop of `type`.
  Raises `ArgumentError` if the value does not match the `type`.
  """
  def ensure_type!(nil, _type), do: nil

  def ensure_type!(value, type) do
    validator = Map.get(validators(), type)

    cond do
      validator && validator.(value) -> value
      true -> raise ArgumentError, "value #{inspect(value)} is not valid for prop type #{type}"
    end
  end

  @doc false
  def validators do
    %{
      atom: &is_atom/1,
      binary: &is_binary/1,
      boolean: &is_boolean/1,
      datetime: &is_struct(&1, DateTime),
      float: &is_float/1,
      integer: &is_integer/1,
      pid: &is_pid/1,
      ref: &is_reference/1
    }
  end

  @doc false
  def defaults([]), do: []

  def defaults(properties) do
    Enum.map(properties, fn {name, _type, opts} ->
      {name, Keyword.get(opts, :default)}
    end)
  end

  defp normalize(attrs) do
    Enum.into(attrs, %{}, fn
      {key, value} when is_atom(key) ->
        {to_string(key), value}

      {key, value} ->
        {key, value}
    end)
  end

  defp merge_defaults(attrs, props) do
    Enum.reduce(props, attrs, fn {name, _type, opts}, acc ->
      Map.put_new(acc, to_string(name), Keyword.get(opts, :default))
    end)
  end

  defp build_props(attrs, props) do
    Map.new(props, fn {name, type, opts} ->
      value = Map.get(attrs, to_string(name))

      required? = Keyword.get(opts, :required, false)

      if required? && empty_value?(value) do
        raise "The property #{inspect(name)} cannot be empty"
      end

      {name, ensure_type!(value, type)}
    end)
  end

  defp empty_value?(nil), do: true
  defp empty_value?(value) when is_binary(value), do: String.trim(value) == ""
  defp empty_value?(_), do: false
end
