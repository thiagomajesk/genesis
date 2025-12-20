defmodule Genesis.RegistryTest do
  use ExUnit.Case, async: true

  alias Genesis.Registry
  alias Genesis.Components.Health
  alias Genesis.Components.Position

  @registry __MODULE__

  setup do
    :ok = Registry.init(@registry)
    on_exit(fn -> Registry.clear(@registry) end)
    {:ok, registry: @registry}
  end

  describe "create" do
    test "creates an entity", %{registry: registry} do
      {:ok, entity} = Registry.create(registry)

      assert {^entity, nil, %{}} = Registry.info(registry, entity)
    end

    test "creates an entity with name", %{registry: registry} do
      {:ok, entity} = Registry.create(registry, name: "Foo")

      assert {^entity, "Foo", %{}} = Registry.info(registry, entity)
    end

    test "creates an entity with metadata", %{registry: registry} do
      metadata = %{created_at: DateTime.utc_now()}
      {:ok, entity} = Registry.create(registry, metadata: metadata)

      assert {^entity, nil, ^metadata} = Registry.info(registry, entity)
    end
  end

  describe "info" do
    test "returns nil for non-existent id", %{registry: registry} do
      assert nil == Registry.info(registry, make_ref())
    end

    test "retrieves information about an entity by id", %{registry: registry} do
      {:ok, entity} = Registry.create(registry, name: "Foo")

      assert {^entity, "Foo", %{}} = Registry.info(registry, entity)
    end
  end

  describe "lookup" do
    test "returns nil for non-existent name", %{registry: registry} do
      assert nil == Registry.lookup(registry, "Foo")
    end

    test "looks up an entity by name", %{registry: registry} do
      {:ok, entity} = Registry.create(registry, name: "Foo")

      assert {^entity, "Foo", %{}} = Registry.lookup(registry, "Foo")
    end
  end

  describe "fetch" do
    test "returns nil for non-existent entity", %{registry: registry} do
      assert nil == Registry.fetch(registry, make_ref())
    end

    test "fetches components of an entity", %{registry: registry} do
      {:ok, entity} = Registry.create(registry)

      Registry.emplace(registry, entity, %Position{x: 10, y: 20})

      assert {^entity, [%Position{x: 10, y: 20}]} = Registry.fetch(registry, entity)
      assert {^entity, _name, %{components: [Position]}} = Registry.info(registry, entity)
    end
  end

  describe "emplace" do
    test "inserts a component for an entity", %{registry: registry} do
      {:ok, entity} = Registry.create(registry)

      assert :ok = Registry.emplace(registry, entity, %Position{x: 10, y: 20})
      assert {^entity, _name, %{components: [Position]}} = Registry.info(registry, entity)
    end

    test "inserting the same component twice fails", %{registry: registry} do
      {:ok, entity} = Registry.create(registry)

      assert :ok = Registry.emplace(registry, entity, %Position{x: 10, y: 20})

      assert {:error, :already_inserted} =
               Registry.emplace(registry, entity, %Position{x: 10, y: 20})
    end
  end

  describe "replace" do
    test "replaces an existing component", %{registry: registry} do
      {:ok, entity} = Registry.create(registry)

      Registry.emplace(registry, entity, %Position{x: 0, y: 0})

      assert :ok = Registry.replace(registry, entity, %Position{x: 10, y: 20})
      assert {^entity, [%Position{x: 10, y: 20}]} = Registry.fetch(registry, entity)
      assert {^entity, _name, %{components: [Position]}} = Registry.info(registry, entity)
    end

    test "fails when component does not exist", %{registry: registry} do
      {:ok, entity} = Registry.create(registry)

      assert {:error, :not_found} =
               Registry.replace(registry, entity, %Position{x: 10, y: 20})
    end
  end

  describe "clear" do
    test "clears all data from the registry", %{registry: registry} do
      {:ok, entity} = Registry.create(registry)

      Registry.emplace(registry, entity, %Health{current: 10, maximum: 10})
      Registry.emplace(registry, entity, %Position{x: 10, y: 20})

      assert :ok = Registry.clear(registry)

      assert nil == Registry.info(registry, entity)
      assert nil == Registry.fetch(registry, entity)
    end
  end

  describe "patch" do
    test "patches metadata of an entity", %{registry: registry} do
      {:ok, entity} = Registry.create(registry, metadata: %{foo: "bar", bar: "baz"})

      assert :ok = Registry.patch(registry, entity, %{foo: "baz"})

      assert {^entity, nil, %{foo: "baz"}} = Registry.info(registry, entity)
    end

    test "fails to patch a non-existent entity", %{registry: registry} do
      assert {:error, :not_found} = Registry.patch(registry, make_ref(), %{foo: "bar"})
    end
  end

  describe "register" do
    test "registers a name for an entity without a name", %{registry: registry} do
      {:ok, entity} = Registry.create(registry)

      Registry.register(registry, entity, "Foo")

      assert {^entity, "Foo", %{}} = Registry.info(registry, entity)
    end

    test "fails to register a name for an entity that already has a name", %{registry: registry} do
      {:ok, entity} = Registry.create(registry, name: "Foo")

      assert {:error, {:already_registered, "Foo"}} =
               Registry.register(registry, entity, "Bar")
    end

    test "fails to register a name for a non-existent entity", %{registry: registry} do
      assert {:error, :not_found} = Registry.register(registry, make_ref(), "Foo")
    end
  end

  describe "erase" do
    test "erases all components from an entity", %{registry: registry} do
      {:ok, entity} = Registry.create(registry)

      Registry.emplace(registry, entity, %Health{current: 10, maximum: 10})
      Registry.emplace(registry, entity, %Position{x: 10, y: 20})

      assert :ok = Registry.erase(registry, entity)

      assert {^entity, []} = Registry.fetch(registry, entity)
      assert {^entity, _name, %{components: []}} = Registry.info(registry, entity)
    end

    test "fails to erase a non-existent entity", %{registry: registry} do
      assert {:error, :entity_not_found} = Registry.erase(registry, make_ref(), Health)
    end

    test "failes to erase a non-existent component from an entity", %{registry: registry} do
      {:ok, entity} = Registry.create(registry)

      assert {:error, :component_not_found} = Registry.erase(registry, entity, Health)
    end

    test "erases the component from an entity", %{registry: registry} do
      {:ok, entity} = Registry.create(registry)

      Registry.emplace(registry, entity, %Health{current: 10, maximum: 10})
      Registry.emplace(registry, entity, %Position{x: 10, y: 20})

      assert :ok = Registry.erase(registry, entity, Health)

      assert {^entity, [%Position{}]} = Registry.fetch(registry, entity)
      assert {^entity, _name, %{components: [Position]}} = Registry.info(registry, entity)
    end
  end

  describe "assign" do
    test "fails to assign components to non-existent entity", %{registry: registry} do
      assert {:error, :entity_not_found} =
               Registry.assign(registry, make_ref(), [%Position{x: 10, y: 20}])
    end

    test "assigns components to an existing entity", %{registry: registry} do
      {:ok, entity} = Registry.create(registry)

      components = [%Position{x: 10, y: 20}, %Health{current: 100, maximum: 100}]

      assert :ok = Registry.assign(registry, entity, components)

      assert {^entity, ^components} = Registry.fetch(registry, entity)
      assert {^entity, _name, %{components: [Position, Health]}} = Registry.info(registry, entity)
    end

    test "replaces existing components with new ones", %{registry: registry} do
      {:ok, entity} = Registry.create(registry)

      Registry.emplace(registry, entity, %Position{x: 0, y: 0})
      Registry.emplace(registry, entity, %Health{current: 50, maximum: 100})

      components = [%Position{x: 10, y: 20}]

      assert :ok = Registry.assign(registry, entity, components)

      assert {^entity, ^components} = Registry.fetch(registry, entity)
      assert {^entity, _name, %{components: [Position]}} = Registry.info(registry, entity)
    end

    test "clears all components when assigning empty list", %{registry: registry} do
      {:ok, entity} = Registry.create(registry)

      Registry.emplace(registry, entity, %Position{x: 10, y: 20})
      Registry.emplace(registry, entity, %Health{current: 100, maximum: 100})

      assert :ok = Registry.assign(registry, entity, [])

      assert {^entity, []} = Registry.fetch(registry, entity)
      assert {^entity, _name, %{components: []}} = Registry.info(registry, entity)
    end
  end

  describe "destroy" do
    test "fails to destroy a non-existent entity", %{registry: registry} do
      assert {:error, :not_found} = Registry.destroy(registry, make_ref())
    end

    test "destroys an entity and removes all associated data", %{registry: registry} do
      {:ok, entity} = Registry.create(registry)
      Registry.emplace(registry, entity, %Position{x: 10, y: 20})

      assert :ok = Registry.destroy(registry, entity)

      assert nil == Registry.info(registry, entity)
      assert nil == Registry.fetch(registry, entity)
    end
  end
end
