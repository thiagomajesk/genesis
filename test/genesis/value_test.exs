defmodule Genesis.ValueTest do
  @valid_types [:atom, :binary, :float, :integer, :boolean, :datetime, :pid, :ref]
  @type_params Enum.map(@valid_types, fn type -> %{type: type} end)

  use ExUnit.Case,
    async: true,
    parameterize: @type_params

  import Genesis.Value

  describe "prop/3" do
    test "rejects non-atom name" do
      error_msg = "The property name must be an atom"
      assert_raise RuntimeError, ~r/#{error_msg}/, fn -> prop "invalid", :binary end
    end

    test "rejects invalid type" do
      error_msg = "The property type must be one of"
      assert_raise ArgumentError, ~r/#{error_msg}/, fn -> prop :invalid, :invalid end
    end
  end

  describe "cast/2" do
    test "casts attributes by property definitions", %{type: type} do
      prop_name = :test_prop
      props = [{prop_name, type, [required: true]}]
      value = fixture(type)
      attrs = [{prop_name, value}]

      result = cast(attrs, props)
      assert result[prop_name] == value
    end

    test "handles required properties", %{type: type} do
      prop_name = :test_prop
      props = [{prop_name, type, [required: true]}]

      # Empty values (nil) should raise an error for required props
      error_msg = "The property :test_prop cannot be empty"
      assert_raise RuntimeError, error_msg, fn -> cast(%{prop_name => nil}, props) end

      # Non-empty values should work fine
      value = fixture(type)
      result = cast(%{prop_name => value}, props)
      assert result[prop_name] == value
    end

    test "considers whitespace-only strings as empty for required binary properties" do
      prop_name = :test_prop
      props = [{prop_name, :binary, [required: true]}]
      error_msg = "The property :test_prop cannot be empty"

      # Empty string and whitespace-only strings should be considered empty
      assert_raise RuntimeError, error_msg, fn -> cast(%{prop_name => ""}, props) end
      assert_raise RuntimeError, error_msg, fn -> cast(%{prop_name => "   "}, props) end
      assert_raise RuntimeError, error_msg, fn -> cast(%{prop_name => "\t\n"}, props) end

      # Non-empty string should work fine
      result = cast(%{prop_name => "valid value"}, props)
      assert result[prop_name] == "valid value"
    end

    test "adds default values for properties", %{type: type} do
      prop_name = :test_prop
      default_value = fixture(type)
      props = [{prop_name, type, [required: true, default: default_value]}]
      attrs = []

      result = cast(attrs, props)
      assert result[prop_name] == default_value
    end

    test "rejects invalid types", %{type: type} do
      invalid_value = fixture(:invalid)

      prop_name = :test_prop
      props = [{prop_name, type, [required: true]}]
      attrs = [{prop_name, invalid_value}]

      error_msg = "value #{inspect(invalid_value)} is not valid for prop type #{type}"
      assert_raise ArgumentError, error_msg, fn -> cast(attrs, props) end
    end

    test "ignores keys not in props definition", %{type: type} do
      prop_name = :test_prop
      props = [{prop_name, type, [required: true]}]
      value = fixture(type)
      attrs = [{prop_name, value}, {:other_prop, "other value"}]

      result = cast(attrs, props)
      assert result[prop_name] == value
      refute Map.has_key?(result, :other_prop)
    end

    test "handles nil for optional props", %{type: type} do
      prop_name = :test_prop
      props = [{prop_name, type, [required: false]}]
      attrs = [{prop_name, nil}]

      result = cast(attrs, props)
      assert result[prop_name] == nil
    end

    test "properly casts only valid values", %{type: type} do
      prop_name = :test_prop
      props = [{prop_name, type, [required: true]}]
      value = fixture(type)
      attrs = [{prop_name, value}]

      result = cast(attrs, props)
      assert result[prop_name] == value
    end
  end

  describe "ensure_type!/2" do
    test "validates values against their type", %{type: type} do
      value = fixture(type)
      assert ensure_type!(value, type) == value
    end

    test "raises for invalid type", %{type: type} do
      invalid_value = fixture(:invalid)

      error_msg = "value #{inspect(invalid_value)} is not valid for prop type #{type}"
      assert_raise ArgumentError, error_msg, fn -> ensure_type!(invalid_value, type) end
    end

    test "allows nil for any type", %{type: type} do
      assert ensure_type!(nil, type) == nil
    end
  end

  defp fixture(:atom), do: :test_atom
  defp fixture(:binary), do: "test_string"
  defp fixture(:float), do: 3.14
  defp fixture(:integer), do: 42
  defp fixture(:boolean), do: true
  defp fixture(:datetime), do: DateTime.utc_now()
  defp fixture(:pid), do: self()
  defp fixture(:ref), do: make_ref()
  defp fixture(:invalid), do: %{}
end
