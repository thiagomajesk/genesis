defmodule Genesis.ContextTest do
  use ExUnit.Case, async: true

  alias Genesis.Context
  alias Genesis.Components.Health
  alias Genesis.Components.Moniker
  alias Genesis.Components.Position

  setup do
    %{context: start_supervised!(Context)}
  end

  describe "create" do
    test "creates an entity", %{context: context} do
      entity = Context.create(context, context: context)

      assert {^entity, types, %{}} = Context.info(context, entity)
      assert MapSet.equal?(types, MapSet.new([]))
    end

    test "creates an entity with name", %{context: context} do
      entity = Context.create(context, name: "Foo", context: context)

      assert {^entity, types, %{}} = Context.info(context, entity)
      assert MapSet.equal?(types, MapSet.new([]))
    end

    test "creates an entity with metadata", %{context: context} do
      created_by = self()
      metadata = %{created_by: created_by}
      entity = Context.create(context, metadata: metadata, context: context)

      assert {^entity, types, %{created_by: ^created_by}} = Context.info(context, entity)
      assert MapSet.equal?(types, MapSet.new([]))
    end
  end

  describe "info" do
    test "returns nil for non-existent id", %{context: context} do
      entity = Genesis.Entity.new(context: context)
      assert nil == Context.info(context, entity)
    end

    test "retrieves information about an entity by id", %{context: context} do
      entity = Context.create(context, name: "Foo", context: context)

      assert {^entity, types, %{}} = Context.info(context, entity)
      assert MapSet.equal?(types, MapSet.new([]))
    end
  end

  describe "lookup" do
    test "returns nil for non-existent name", %{context: context} do
      assert nil == Context.lookup(context, "Foo")
    end

    test "looks up an entity by name", %{context: context} do
      entity = Context.create(context, name: "Foo", context: context)

      assert {^entity, types, %{}} = Context.lookup(context, "Foo")
      assert MapSet.equal?(types, MapSet.new([]))
    end
  end

  describe "exists?" do
    test "checks entity existence by reference and name", %{context: context} do
      entity_1 = Context.create(context, name: "Foo", context: context)
      entity_2 = Context.create(context, name: "Bar", context: context)

      assert Context.exists?(context, entity_1)
      assert Context.exists?(context, "Foo")
      assert Context.exists?(context, entity_2)
      assert Context.exists?(context, "Bar")

      nonexistent_entity = Genesis.Entity.new(context: context)
      refute Context.exists?(context, nonexistent_entity)
      refute Context.exists?(context, "NonExistent")
    end
  end

  describe "fetch" do
    test "returns nil for non-existent entity", %{context: context} do
      entity = Genesis.Entity.new(context: context)
      assert nil == Context.fetch(context, entity)
    end

    test "fetches components of an entity", %{context: context} do
      entity = Context.create(context, context: context)

      Context.emplace(context, entity, %Position{x: 10, y: 20})

      assert {^entity, [%Position{x: 10, y: 20}]} = Context.fetch(context, entity)
      assert {^entity, types, _metadata} = Context.info(context, entity)
      assert MapSet.equal?(types, MapSet.new([Position]))
    end

    test "fetches components of an entity by name", %{context: context} do
      entity = Context.create(context, name: "Foo", context: context)

      Context.emplace(context, entity, %Position{x: 10, y: 20})

      assert {^entity, [%Position{x: 10, y: 20}]} = Context.fetch(context, "Foo")
      assert {^entity, types, %{}} = Context.info(context, entity)
      assert MapSet.equal?(types, MapSet.new([Position]))
    end
  end

  describe "emplace" do
    test "inserts a component for an entity", %{context: context} do
      entity = Context.create(context, context: context)

      assert :ok = Context.emplace(context, entity, %Position{x: 10, y: 20})
      assert {^entity, types, %{}} = Context.info(context, entity)
      assert MapSet.equal?(types, MapSet.new([Position]))
    end

    test "inserting the same component twice fails", %{context: context} do
      entity = Context.create(context, context: context)

      assert :ok = Context.emplace(context, entity, %Position{x: 10, y: 20})

      assert {:error, :already_inserted} =
               Context.emplace(context, entity, %Position{x: 10, y: 20})
    end
  end

  describe "replace" do
    test "replaces an existing component", %{context: context} do
      entity = Context.create(context, context: context)

      Context.emplace(context, entity, %Position{x: 0, y: 0})

      assert :ok = Context.replace(context, entity, %Position{x: 10, y: 20})
      assert {^entity, [%Position{x: 10, y: 20}]} = Context.fetch(context, entity)
      assert {^entity, types, %{}} = Context.info(context, entity)
      assert MapSet.equal?(types, MapSet.new([Position]))
    end

    test "fails when component does not exist", %{context: context} do
      entity = Context.create(context, context: context)

      assert {:error, :component_not_found} =
               Context.replace(context, entity, %Position{x: 10, y: 20})
    end
  end

  describe "clear" do
    test "clears all data from the context", %{context: context} do
      entity = Context.create(context, context: context)

      Context.emplace(context, entity, %Health{current: 10, maximum: 10})
      Context.emplace(context, entity, %Position{x: 10, y: 20})

      assert :ok = Context.clear(context)

      assert nil == Context.info(context, entity)
      assert nil == Context.fetch(context, entity)
    end
  end

  describe "patch" do
    test "patches metadata of an entity", %{context: context} do
      entity = Context.create(context, metadata: %{foo: "bar", bar: "baz"}, context: context)

      assert :ok = Context.patch(context, entity, %{foo: "baz"})

      assert {^entity, types, %{foo: "baz"}} = Context.info(context, entity)
      assert MapSet.equal?(types, MapSet.new([]))
    end

    test "fails to patch a non-existent entity", %{context: context} do
      entity = Genesis.Entity.new(context: context)

      assert {:error, :entity_not_found} =
               Context.patch(context, entity, %{foo: "bar"})
    end
  end

  describe "erase" do
    test "erases all components from an entity", %{context: context} do
      entity = Context.create(context, context: context)

      Context.emplace(context, entity, %Health{current: 10, maximum: 10})
      Context.emplace(context, entity, %Position{x: 10, y: 20})

      assert :ok = Context.erase(context, entity)

      assert {^entity, []} = Context.fetch(context, entity)
      assert {^entity, types, %{}} = Context.info(context, entity)
      assert MapSet.equal?(types, MapSet.new([]))
    end

    test "fails to erase a non-existent entity", %{context: context} do
      entity = Genesis.Entity.new(context: context)

      assert {:error, :entity_not_found} =
               Context.erase(context, entity, Health)
    end

    test "fails to erase a non-existent component from an entity", %{context: context} do
      entity = Context.create(context, context: context)

      assert {:error, :component_not_found} = Context.erase(context, entity, Health)
    end

    test "erases the component from an entity", %{context: context} do
      entity = Context.create(context, context: context)

      Context.emplace(context, entity, %Health{current: 10, maximum: 10})
      Context.emplace(context, entity, %Position{x: 10, y: 20})

      assert :ok = Context.erase(context, entity, Health)

      assert {^entity, [%Position{}]} = Context.fetch(context, entity)
      assert {^entity, types, %{}} = Context.info(context, entity)
      assert MapSet.equal?(types, MapSet.new([Position]))
    end
  end

  describe "assign" do
    test "fails to assign components to non-existent entity", %{context: context} do
      entity = Genesis.Entity.new(context: context)

      assert {:error, :entity_not_found} =
               Context.assign(context, entity, [%Position{x: 10, y: 20}])
    end

    test "assigns components to an existing entity", %{context: context} do
      entity = Context.create(context, context: context)

      components = [%Position{x: 10, y: 20}, %Health{current: 100, maximum: 100}]

      assert :ok = Context.assign(context, entity, components)

      assert {^entity, ^components} = Context.fetch(context, entity)
      assert {^entity, types, %{}} = Context.info(context, entity)
      assert MapSet.equal?(types, MapSet.new([Position, Health]))
    end

    test "replaces existing components with new ones", %{context: context} do
      entity = Context.create(context, context: context)

      Context.emplace(context, entity, %Position{x: 0, y: 0})
      Context.emplace(context, entity, %Health{current: 50, maximum: 100})

      components = [%Position{x: 10, y: 20}]

      assert :ok = Context.assign(context, entity, components)

      assert {^entity, ^components} = Context.fetch(context, entity)
      assert {^entity, types, %{}} = Context.info(context, entity)
      assert MapSet.equal?(types, MapSet.new([Position]))
    end

    test "clears all components when assigning empty list", %{context: context} do
      entity = Context.create(context, context: context)

      Context.emplace(context, entity, %Position{x: 10, y: 20})
      Context.emplace(context, entity, %Health{current: 100, maximum: 100})

      assert :ok = Context.assign(context, entity, [])

      assert {^entity, []} = Context.fetch(context, entity)
      assert {^entity, types, %{}} = Context.info(context, entity)
      assert MapSet.equal?(types, MapSet.new([]))
    end
  end

  describe "destroy" do
    test "fails to destroy a non-existent entity", %{context: context} do
      entity = Genesis.Entity.new(context: context)
      assert {:error, :entity_not_found} = Context.destroy(context, entity)
    end

    test "destroys an entity and removes all associated data", %{context: context} do
      entity = Context.create(context, context: context)
      Context.emplace(context, entity, %Position{x: 10, y: 20})

      assert :ok = Context.destroy(context, entity)

      assert nil == Context.info(context, entity)
      assert nil == Context.fetch(context, entity)
    end
  end

  describe "streams" do
    test "streams all metadata", %{context: context} do
      entity_1 = Context.create(context, metadata: %{foo: "bar"}, context: context)
      entity_2 = Context.create(context, metadata: %{baz: "qux"}, context: context)

      stream = Context.metadata(context)

      record_1 = Enum.find(stream, fn {k, _v} -> k == entity_1 end)
      record_2 = Enum.find(stream, fn {k, _v} -> k == entity_2 end)

      assert {^entity_1, {types_1, %{foo: "bar"}}} = record_1
      assert {^entity_2, {types_2, %{baz: "qux"}}} = record_2
      assert MapSet.equal?(types_1, MapSet.new([]))
      assert MapSet.equal?(types_2, MapSet.new([]))
    end

    test "streams all components", %{context: context} do
      entity_1 = Context.create(context, context: context)
      entity_2 = Context.create(context, context: context)

      Context.emplace(context, entity_1, %Position{x: 10, y: 20})
      Context.emplace(context, entity_2, %Position{x: 30, y: 40})

      stream = Context.components(context)

      record_1 = Enum.find(stream, fn {k, _v} -> k == entity_1 end)
      record_2 = Enum.find(stream, fn {k, _v} -> k == entity_2 end)

      assert {^entity_1, {Position, %Position{x: 10, y: 20}}} = record_1
      assert {^entity_2, {Position, %Position{x: 30, y: 40}}} = record_2
    end

    test "streams all entities", %{context: context} do
      entity_1 = Context.create(context, name: "Foo", context: context)
      entity_2 = Context.create(context, name: "Bar", context: context)

      Context.emplace(context, entity_1, %Position{x: 10, y: 20})
      Context.emplace(context, entity_2, %Position{x: 30, y: 40})

      stream = Context.entities(context)

      record_1 = Enum.find(stream, fn {k, _v} -> k == entity_1 end)
      record_2 = Enum.find(stream, fn {k, _v} -> k == entity_2 end)

      assert {^entity_1, {types_1, _metadata, [%Position{x: 10, y: 20}]}} = record_1
      assert {^entity_2, {types_2, _metadata, [%Position{x: 30, y: 40}]}} = record_2
      assert MapSet.equal?(types_1, MapSet.new([Position]))
      assert MapSet.equal?(types_2, MapSet.new([Position]))
    end
  end

  describe "queries" do
    test "get/1", %{context: context} do
      entity = Context.create(context, context: context)

      Context.emplace(context, entity, %Health{current: 100})

      refute Context.get(context, entity, Moniker)
      assert %Health{current: 100} = Context.get(context, entity, Health)
    end

    test "get/2", %{context: context} do
      entity = Context.create(context, context: context)

      Context.emplace(context, entity, %Health{current: 100})

      assert :default = Context.get(context, entity, Moniker, :default)
      assert %Health{current: 100} = Context.get(context, entity, Health)
    end

    test "all/0", %{context: context} do
      entity_1 = Context.create(context, context: context)
      entity_2 = Context.create(context, context: context)
      entity_3 = Context.create(context, context: context)

      Context.emplace(context, entity_1, %Health{current: 100})
      Context.emplace(context, entity_2, %Health{current: 100})
      Context.emplace(context, entity_3, %Health{current: 100})

      entities = Enum.map(Context.all(context, Health), &elem(&1, 0))

      assert Enum.member?(entities, entity_1)
      assert Enum.member?(entities, entity_2)
      assert Enum.member?(entities, entity_3)
    end

    test "at_least/2", %{context: context} do
      entity_1 = Context.create(context, context: context)
      entity_2 = Context.create(context, context: context)

      Context.emplace(context, entity_1, %Health{current: 10})
      Context.emplace(context, entity_2, %Health{current: 50})

      assert [{^entity_2, _}] = Context.at_least(context, Health, :current, 50)
      assert [] = Context.at_least(context, Health, :invalid, 50)
    end

    test "at_most/2", %{context: context} do
      entity_1 = Context.create(context, context: context)
      entity_2 = Context.create(context, context: context)

      Context.emplace(context, entity_1, %Health{current: 10})
      Context.emplace(context, entity_2, %Health{current: 50})

      assert [{^entity_1, _}] = Context.at_most(context, Health, :current, 10)
      assert [] = Context.at_most(context, Health, :invalid, 10)
    end

    test "between/3", %{context: context} do
      entity_1 = Context.create(context, context: context)
      entity_2 = Context.create(context, context: context)

      Context.emplace(context, entity_1, %Health{current: 10})
      Context.emplace(context, entity_2, %Health{current: 50})

      assert [{^entity_1, _}] = Context.between(context, Health, :current, 5, 15)
      assert [{^entity_2, _}] = Context.between(context, Health, :current, 40, 60)
      assert [] = Context.between(context, Health, :invalid, 5, 15)
    end

    test "match/1", %{context: context} do
      entity_1 = Context.create(context, context: context)
      entity_2 = Context.create(context, context: context)

      Context.emplace(context, entity_1, %Health{current: 100, maximum: 100})
      Context.emplace(context, entity_2, %Health{current: 0, maximum: 100})

      assert [{^entity_1, _}] = Context.match(context, Health, current: 100)
      assert [{^entity_2, _}] = Context.match(context, Health, current: 0, maximum: 100)
      assert [] = Context.match(context, Health, invalid: 100)
    end

    test "all_of", %{context: context} do
      entity_1 = Context.create(context, context: context)

      Context.emplace(context, entity_1, %Health{current: 100})
      Context.emplace(context, entity_1, %Position{x: 10, y: 20})
      Context.emplace(context, entity_1, %Moniker{name: "Entity"})

      entity_2 = Context.create(context, context: context)

      Context.emplace(context, entity_2, %Health{current: 100})
      Context.emplace(context, entity_2, %Position{x: 10, y: 20})

      assert [^entity_1] = Context.all_of(context, [Health, Position, Moniker])
    end

    test "any_of", %{context: context} do
      entity_1 = Context.create(context, context: context)

      Context.emplace(context, entity_1, %Health{current: 100})
      Context.emplace(context, entity_1, %Position{x: 10, y: 20})
      Context.emplace(context, entity_1, %Moniker{name: "Entity"})

      entity_2 = Context.create(context, context: context)

      Context.emplace(context, entity_2, %Position{x: 5, y: 15})

      assert [^entity_1] = Context.any_of(context, [Health, Moniker])
    end

    test "none_of", %{context: context} do
      entity_1 = Context.create(context, context: context)

      Context.emplace(context, entity_1, %Moniker{name: "Entity"})

      entity_2 = Context.create(context, context: context)

      Context.emplace(context, entity_2, %Health{current: 100})
      Context.emplace(context, entity_2, %Position{x: 10, y: 20})

      assert [^entity_1] = Context.none_of(context, [Health, Position])
    end

    test "search", %{context: context} do
      entity_1 = Context.create(context, context: context)

      Context.emplace(context, entity_1, %Health{current: 100})
      Context.emplace(context, entity_1, %Position{x: 10, y: 20})
      Context.emplace(context, entity_1, %Moniker{name: "Entity"})

      entity_2 = Context.create(context, context: context)

      Context.emplace(context, entity_2, %Health{current: 100})
      Context.emplace(context, entity_2, %Position{x: 10, y: 20})

      entity_3 = Context.create(context, context: context)

      Context.emplace(context, entity_3, %Health{current: 100})
      Context.emplace(context, entity_3, %Moniker{name: "Entity"})

      opts = [all: [Health], any: [Moniker], none: [Position]]
      assert [^entity_3] = Context.search(context, opts)
    end
  end
end
