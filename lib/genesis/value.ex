defmodule Genesis.Value do
  @valid_types [:any, :atom, :string, :boolean, :float, :integer]

  @doc """
  Defines a property for a Component.

  ## Types

  The following types are currently supported:

  - `:any`
  - `:atom`
  - `:string`
  - `:boolean`
  - `:float`
  - `:integer`

  Because we don't provide an exhaustive list of types, `:any` can be used as an wildcard where
  the other types don't seem appropriate. However, it should be used sparingly as it doesn't provide
  any typing or casting guarantees. Keep in mind that whenever possible, using scalar types should
  still be preferred as it enforces good ECS design practices.

  For instance, you might be tempted to use `:any` to model complex relationships between entities,
  such as one-to-many associations, by storing complex data structures in a single property. A more idiomatic
  approach would be to create separate entities and link them through components instead. This adheres
  to ECS principles and enhances the maintainability, scalability, and extensibility of your architecture.

  ## Examples

      prop :name, :string, required: true
      prop :amount, :integer, default: 0
      prop :status, :atom, values: [:active, :inactive]
      prop :email, :string, format: ~r/@/
      prop :bonus, :float, min: 0.0, max: 95.5
      prop :alive, :boolean, default: true
      prop :created_at, Date, required: true

  ## Options

    * `:required` - marks the property as required.
    * `:default` - the default value if one is not provided.
    * `:values` - restricts accepted values to the given list.
    * `:format` - regex used to validate string properties.
    * `:min` - the minimum number allowed (or minimum string length).
    * `:max` - the maximum number allowed (or maximum string length).
  """
  defmacro prop(name, type, opts \\ []) do
    quote bind_quoted: binding() do
      Genesis.Value.__prop__(__MODULE__, name, type, opts, __ENV__.file, __ENV__.line)
    end
  end

  @doc false
  def cast(_attrs, []), do: %{}

  def cast(attrs, properties) do
    attrs
    |> normalize()
    |> merge_defaults(properties)
    |> cast_properties(properties)
  end

  @doc false
  def __defaults__([]), do: []

  def __defaults__(properties) do
    Enum.map(properties, fn {name, _type, opts} ->
      {name, Keyword.get(opts, :default)}
    end)
  end

  @doc false
  def __setup__(module, _file, _line) do
    Module.register_attribute(module, :properties, accumulate: true)
  end

  @doc false
  def __prop__(module, name, type, opts, file, line) do
    #
    # Property keys validation
    #
    if not is_atom(name) do
      compile_error!(
        module,
        file,
        line,
        "property names must atoms, got: #{inspect(name)}"
      )
    end

    #
    # Duplicated property validation
    #
    properties = Module.get_attribute(module, :properties)

    if name in properties do
      compile_error!(
        module,
        file,
        line,
        "another property with the name #{inspect(name)} is already defined"
      )
    end

    #
    # Required/Default consistency validation
    #
    if Keyword.has_key?(opts, :required) and Keyword.has_key?(opts, :default) do
      compile_error!(
        module,
        file,
        line,
        "a property cannot have both :required and :default options"
      )
    end

    #
    # Required option validation
    #
    required = Keyword.get(opts, :required, false)

    if not is_boolean(required) do
      compile_error!(
        module,
        file,
        line,
        "the :required option must be a boolean, got: #{inspect(required)}"
      )
    end

    #
    # Default option validation
    #
    default = Keyword.get(opts, :default)

    if not valid_value?(type, default) do
      compile_error!(
        module,
        file,
        line,
        "#{inspect(default)} is not a valid default for property #{inspect(name)} of type #{inspect(type)}"
      )
    end

    #
    # Values option validation
    #
    values = Keyword.get(opts, :values)

    if not is_nil(values) and not is_list(values) do
      compile_error!(
        module,
        file,
        line,
        "the :values option must be a list, got: #{inspect(values)}"
      )
    end

    if not is_nil(values) and Enum.any?(values, &(not valid_value?(type, &1))) do
      compile_error!(
        module,
        file,
        line,
        "the :values option contains invalid values for property #{inspect(name)} of type #{inspect(type)}"
      )
    end

    #
    # Format option validation
    #
    format = Keyword.get(opts, :format)

    if type != :string and not is_nil(format) do
      compile_error!(
        module,
        file,
        line,
        "the :format option can only be used with properties of type :string"
      )
    end

    if not is_nil(format) and not is_struct(format, Regex) do
      compile_error!(
        module,
        file,
        line,
        "the :format option must be a Regex, got: #{inspect(format)}"
      )
    end

    #
    # Min option validation
    #
    min = Keyword.get(opts, :min)

    if not is_nil(min) and not is_number(min) do
      compile_error!(
        module,
        file,
        line,
        "the :min option must be an integer or float, got: #{inspect(min)}"
      )
    end

    if type not in [:integer, :float, :string] and not is_nil(min) do
      compile_error!(
        module,
        file,
        line,
        "the :min option can only be used with properties of type :integer, :float, or :string"
      )
    end

    #
    # Max option validation
    #
    max = Keyword.get(opts, :max)

    if not is_nil(max) and not is_number(max) do
      compile_error!(
        module,
        file,
        line,
        "the :max option must be an integer or float, got: #{inspect(max)}"
      )
    end

    if type not in [:integer, :float, :string] and not is_nil(max) do
      compile_error!(
        module,
        file,
        line,
        "the :max option can only be used with properties of type :integer, :float, or :string"
      )
    end

    #
    # Min/Max consistency validation
    #
    if not is_nil(min) and not is_nil(max) and min > max do
      compile_error!(
        module,
        file,
        line,
        "the :min option cannot be greater than the :max option for property #{inspect(name)}"
      )
    end

    #
    # Property type validation
    #
    cond do
      type in @valid_types ->
        Module.put_attribute(module, :properties, {name, type, opts})

      String.starts_with?(Atom.to_string(type), "Elixir.") ->
        Module.put_attribute(module, :properties, {name, {:struct, type}, opts})

      true ->
        compile_error!(
          module,
          file,
          line,
          "a property type must be one of #{inspect(@valid_types)}, got: #{inspect(type)}"
        )
    end
  end

  defp compile_error!(module, file, line, msg) do
    raise CompileError, file: file, line: line, description: "[#{inspect(module)}] " <> msg
  end

  defp valid_value?(_type, nil), do: true
  defp valid_value?(:any, _value), do: true
  defp valid_value?(:map, value) when is_map(value), do: true
  defp valid_value?(:list, value) when is_list(value), do: true
  defp valid_value?(:atom, value) when is_atom(value), do: true
  defp valid_value?(:float, value) when is_float(value), do: true
  defp valid_value?(:string, value) when is_binary(value), do: true
  defp valid_value?(:integer, value) when is_integer(value), do: true
  defp valid_value?(:boolean, value) when is_boolean(value), do: true
  defp valid_value?({:struct, mod}, value) when is_struct(value, mod), do: true
  defp valid_value?(_type, _value), do: false

  defp empty?(nil), do: true
  defp empty?(value) when is_binary(value), do: String.trim(value) == ""
  defp empty?(_other), do: false

  defp normalize(attrs) do
    Enum.into(attrs, %{}, fn
      {key, value} when is_binary(key) ->
        {key, value}

      {key, value} when is_atom(key) ->
        {to_string(key), value}
    end)
  end

  defp merge_defaults(attrs, properties) do
    properties
    |> __defaults__()
    |> normalize()
    |> Map.merge(attrs)
  end

  defp cast_properties(attrs, properties) do
    Map.new(properties, fn
      {name, type, opts} when type in @valid_types ->
        value = fetch_value(attrs, {name, type, opts})
        cast_property_value(value, {name, type, opts})

      {name, special, opts} when is_tuple(special) ->
        value = fetch_value(attrs, {name, special, opts})
        cast_property_value(value, {name, special, opts})

      {name, type, _opts} ->
        raise ArgumentError, "invalid property type #{inspect(type)} for #{inspect(name)}"
    end)
  end

  defp cast_property_value(value, {name, type, opts}) do
    if Keyword.get(opts, :required, false) and empty?(value) do
      raise ArgumentError, "property #{inspect(name)} is required"
    end

    if not valid_value?(type, value) do
      raise ArgumentError,
            "invalid value #{inspect(value)} given to property #{inspect(name)} of type #{inspect(type)}"
    end

    min = Keyword.get(opts, :min)

    if not is_nil(min) and value < min do
      raise ArgumentError,
            "value #{inspect(value)} for property #{inspect(name)} is less than the minimum allowed #{inspect(min)}"
    end

    max = Keyword.get(opts, :max)

    if not is_nil(max) and value > max do
      raise ArgumentError,
            "value #{inspect(value)} for property #{inspect(name)} is greater than the maximum allowed #{inspect(max)}"
    end

    format = Keyword.get(opts, :format)

    if not is_nil(format) and not Regex.match?(format, value) do
      raise ArgumentError,
            "value #{inspect(value)} for property #{inspect(name)} does not match the required format #{inspect(format)}"
    end

    {name, value}
  end

  defp fetch_value(attrs, {name, type, opts}) do
    value = Map.get(attrs, to_string(name))
    atomize? = type == :atom and is_binary(value)

    values = Keyword.get(opts, :values)

    if atomize? and values == [] do
      raise ArgumentError,
            "The property #{inspect(name)} needs to provide values when casting strings"
    end

    # In case of atom properties, we append string versions of the atoms to the allowed values
    stringified = Stream.map(values, &to_string/1)
    allowed_values = if atomize?, do: Enum.concat(values, stringified), else: values

    if not is_nil(values) and value not in allowed_values do
      raise ArgumentError,
            "value #{inspect(value)} for property #{inspect(name)} is not allowed, must be one of #{inspect(allowed_values)}"
    end

    # Finally, if not exceptions were raised, we can return the value (possibly atomized)
    if atomize?, do: String.to_existing_atom(value), else: value
  end
end
