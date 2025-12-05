defmodule Genesis.ValueTest do
  use ExUnit.Case, async: true

  describe "prop/3" do
    test "rejects non-atom name" do
      error_msg = ~r/property names must atoms/

      assert_raise CompileError, error_msg, fn ->
        component_fixture(NonAtomNameFixture, {"invalid", :string, []})
      end
    end

    test "rejects invalid type" do
      error_msg = ~r/property type must be one of/

      assert_raise CompileError, error_msg, fn ->
        component_fixture(InvalidTypeFixture, {:invalid, :invalid, []})
      end
    end

    test "rejects required with default" do
      error_msg = ~r/cannot have both :required and :default/

      assert_raise CompileError, error_msg, fn ->
        component_fixture(
          RequiredWithDefaultFixture,
          {:age, :integer, [required: true, default: 10]}
        )
      end
    end

    test "rejects non-boolean required" do
      error_msg = ~r/the :required option must be a boolean/

      assert_raise CompileError, error_msg, fn ->
        component_fixture(NonBooleanRequiredFixture, {:flag, :boolean, [required: :yes]})
      end
    end

    test "rejects invalid default" do
      error_msg = ~r/not a valid default/

      assert_raise CompileError, error_msg, fn ->
        component_fixture(InvalidDefaultFixture, {:age, :integer, [default: "invalid"]})
      end
    end

    test "rejects non-list values" do
      error_msg = ~r/:values option must be a list/

      assert_raise CompileError, error_msg, fn ->
        component_fixture(NonListValuesFixture, {:age, :integer, [values: 1]})
      end
    end

    test "rejects values with invalid entries" do
      error_msg = ~r/:values option contains invalid values/

      assert_raise CompileError, error_msg, fn ->
        component_fixture(InvalidValuesFixture, {:age, :integer, [values: ["invalid"]]})
      end
    end

    test "rejects format on non-string properties" do
      error_msg = ~r/:format option can only be used with properties of type :string/

      assert_raise CompileError, error_msg, fn ->
        component_fixture(FormatOnNonStringFixture, {:age, :integer, [format: ~r/\d+/]})
      end
    end

    test "rejects format that is not a regex" do
      error_msg = ~r/:format option must be a Regex/

      assert_raise CompileError, error_msg, fn ->
        component_fixture(FormatNotRegexFixture, {:name, :string, [format: ".*"]})
      end
    end

    test "rejects min when not number" do
      error_msg = ~r/:min option must be an integer or float/

      assert_raise CompileError, error_msg, fn ->
        component_fixture(NonNumberMinFixture, {:age, :integer, [min: "invalid"]})
      end
    end

    test "rejects min on unsupported type" do
      error_msg =
        ~r/:min option can only be used with properties of type :integer, :float, or :string/

      assert_raise CompileError, error_msg, fn ->
        component_fixture(MinUnsupportedTypeFixture, {:flag, :boolean, [min: 1]})
      end
    end

    test "rejects max when not number" do
      error_msg = ~r/:max option must be an integer or float/

      assert_raise CompileError, error_msg, fn ->
        component_fixture(NonNumberMaxFixture, {:age, :integer, [max: "invalid"]})
      end
    end

    test "rejects max on unsupported type" do
      error_msg =
        ~r/:max option can only be used with properties of type :integer, :float, or :string/

      assert_raise CompileError, error_msg, fn ->
        component_fixture(MaxUnsupportedTypeFixture, {:flag, :boolean, [max: 1]})
      end
    end

    test "rejects min greater than max" do
      error_msg = ~r/:min option cannot be greater than the :max option/

      assert_raise CompileError, error_msg, fn ->
        component_fixture(MinGreaterThanMaxFixture, {:age, :integer, [min: 5, max: 1]})
      end
    end
  end

  describe "cast/2" do
    test "rejects unknown properties" do
      name = :test_string
      props = [{name, :string, []}]

      attrs = %{:unkown => "value", name => "value"}
      assert %{^name => "value"} = Genesis.Value.cast(attrs, props)
      refute Map.has_key?(Genesis.Value.cast(attrs, props), :unkown)
    end

    test "considers whitespace-only strings as empty for required string properties" do
      name = :test_string
      props = [{name, :string, [required: true]}]

      error_msg = "property #{inspect(name)} is required"

      # Empty string and whitespace-only strings should be considered empty
      assert_raise ArgumentError, error_msg, fn ->
        Genesis.Value.cast(%{name => ""}, props)
      end

      assert_raise ArgumentError, error_msg, fn ->
        Genesis.Value.cast(%{name => "   "}, props)
      end

      assert_raise ArgumentError, error_msg, fn ->
        Genesis.Value.cast(%{name => "\t\n"}, props)
      end

      # Non-empty string should work fine
      assert %{^name => "valid value"} = Genesis.Value.cast(%{name => "valid value"}, props)
    end

    test "integer min option" do
      name = :test_integer
      props = [{name, :integer, [min: 10, max: 20]}]

      assert %{^name => 10} = Genesis.Value.cast(%{name => 10}, props)

      error_msg = "value 9 for property #{inspect(name)} is less than the minimum allowed 10"
      assert_raise ArgumentError, error_msg, fn -> Genesis.Value.cast(%{name => 9}, props) end
    end

    test "integer max option" do
      name = :test_integer
      props = [{name, :integer, [min: 10, max: 20]}]

      assert %{^name => 10} = Genesis.Value.cast(%{name => 10}, props)

      assert %{^name => 20} = Genesis.Value.cast(%{name => 20}, props)

      error_msg = "value 21 for property #{inspect(name)} is greater than the maximum allowed 20"

      assert_raise ArgumentError, error_msg, fn ->
        Genesis.Value.cast(%{name => 21}, props)
      end
    end

    test "string format option" do
      name = :test_string
      props = [{name, :string, [format: ~r/^\d+$/]}]

      assert %{^name => "123"} = Genesis.Value.cast(%{name => "123"}, props)

      error_msg =
        ~s|value "invalid" for property #{inspect(name)} does not match the required format ~r/^\\d+$/|

      assert_raise ArgumentError, error_msg, fn ->
        Genesis.Value.cast(%{name => "invalid"}, props)
      end
    end

    test "atom values option" do
      name = :test_atom
      props = [{name, :atom, [values: [:on, :off]]}]

      assert %{^name => :on} = Genesis.Value.cast(%{name => :on}, props)
      assert %{^name => :on} = Genesis.Value.cast(%{name => "on"}, props)

      error_msg =
        ~s|value "invalid" for property #{inspect(name)} is not allowed, must be one of [:on, :off, \"on\", \"off\"]|

      assert_raise ArgumentError, error_msg, fn ->
        Genesis.Value.cast(%{name => "invalid"}, props)
      end
    end

    test "accepts any" do
      name = :test_any
      value = %{metadata: [%{foo: "bar"}]}
      props = [{name, :any, [required: true]}]

      assert %{^name => ^value} = Genesis.Value.cast(%{name => value}, props)
    end

    test "accepts struct types" do
      name = :test_date
      date = Date.utc_today()
      props = [{name, {:struct, Date}, []}]

      assert %{^name => ^date} = Genesis.Value.cast(%{name => date}, props)
    end
  end

  for type <- [:atom, :string, :float, :integer, :boolean] do
    describe "cast/2 for #{type}" do
      test "casts attributes by property definitions" do
        type = unquote(type)
        name = :"test_#{type}"

        value = fixture(type)
        props = [{name, type, [required: true]}]

        assert %{^name => ^value} = Genesis.Value.cast(%{name => value}, props)
      end

      test "handles required properties" do
        type = unquote(type)
        name = :"test_#{type}"

        value = fixture(type)
        props = [{name, type, [required: true]}]

        assert %{^name => ^value} = Genesis.Value.cast(%{name => value}, props)

        error_msg = "property #{inspect(name)} is required"

        assert_raise ArgumentError, error_msg, fn ->
          Genesis.Value.cast(%{name => nil}, props)
        end
      end

      test "adds default values for properties" do
        type = unquote(type)
        name = :"test_#{type}"

        default = fixture(type)
        props = [{name, type, [default: default]}]

        assert %{^name => ^default} = Genesis.Value.cast(%{}, props)
      end

      test "rejects invalid types" do
        type = unquote(type)
        name = :"test_#{type}"

        props = [{name, type, [required: true]}]
        attrs = [{name, %{}}]

        error_msg =
          ~s|invalid value %{} given to property #{inspect(name)} of type #{inspect(type)}|

        assert_raise ArgumentError, error_msg, fn -> Genesis.Value.cast(attrs, props) end
      end

      test "ignores keys not in props definition" do
        type = unquote(type)
        name = :"test_#{type}"
        value = fixture(type)

        props = [{name, type, [required: true]}]
        attrs = [{name, value}, {:unkown, "value"}]

        assert %{^name => ^value} = Genesis.Value.cast(attrs, props)
        refute Map.has_key?(Genesis.Value.cast(attrs, props), :unkown)
      end

      test "handles nil for optional props" do
        type = unquote(type)
        name = :"test_#{type}"

        props = [{name, type, [required: false]}]
        attrs = [{name, nil}]

        assert %{^name => nil} = Genesis.Value.cast(attrs, props)
      end

      test "properly casts only valid values" do
        type = unquote(type)
        name = :"test_#{type}"
        value = fixture(type)

        props = [{name, type, [required: true]}]
        attrs = [{name, value}]

        assert %{^name => ^value} = Genesis.Value.cast(attrs, props)
      end
    end
  end

  defp fixture(:atom), do: :test_atom
  defp fixture(:string), do: "test_string"
  defp fixture(:float), do: 3.14
  defp fixture(:integer), do: 42
  defp fixture(:boolean), do: true

  defp component_fixture(suffix, {name, type, opts}) when is_atom(suffix) do
    defmodule Module.concat(__MODULE__, suffix) do
      use Genesis.Component
      prop(name, type, opts)
    end
  end
end
