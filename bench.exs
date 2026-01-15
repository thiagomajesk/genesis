# Benchmarking script for Genesis Context operations (elixir bench.exs)
# Use --tag: tag to identify the benchmark run (defaults to "baseline")
# Use --filter: regex to filter which benchmark jobs to run (default to all)

################################################################################
# Setup
#################################################################################
Mix.install([{:genesis, path: "."}, {:benchee, "~> 1.5"}])

args = System.argv()
opts = [tag: :string, filter: :string]
{parsed, _remaining} = OptionParser.parse!(args, strict: opts)

# Regex filter to select functions to run
filter = Keyword.get(parsed, :filter)

if is_nil(filter) or String.trim(filter) == "",
  do: raise("You must provide a --filter option with a valid regex")

################################################################################
# Helper functions
#################################################################################
build_components = fn component_types ->
  Enum.map(component_types, fn component_type ->
    value = Enum.random(1..length(component_types))
    struct!(component_type, %{key: to_string(value), value: value})
  end)
end

seed_entities = fn input ->
  Enum.map(1..input.max_entities, fn _ ->
    entity = Genesis.Context.create(input.context)
    components = build_components.(input.component_types)

    case Genesis.Context.assign(input.context, entity, components) do
      :ok ->
        entity

      {:error, _reason} ->
        raise "Failed to assign components to: #{inspect(entity)}"
    end
  end)
end

################################################################################
# Configuration
#################################################################################
jobs = %{
  "assign" => {
    fn input ->
      %{entity: entity, components: components} = input.scenario
      Genesis.Context.assign(input.context, entity, components)
    end,
    before_scenario: fn input ->
      seed_entities.(input)
      entity = Genesis.Context.create(input.context)
      components = build_components.(input.component_types)
      Map.put(input, :scenario, %{entity: entity, components: components})
    end
  },
  "info" => {
    fn input ->
      %{entity: entity} = input.scenario
      Genesis.Context.info(input.context, entity)
    end,
    before_scenario: fn input ->
      entities = seed_entities.(input)
      entity = Enum.random(entities)
      Map.put(input, :scenario, %{entity: entity})
    end
  },
  "exists?" => {
    fn input ->
      %{entity: entity} = input.scenario
      Genesis.Context.exists?(input.context, entity)
    end,
    before_scenario: fn input ->
      entities = seed_entities.(input)
      entity = Enum.random(entities)
      Map.put(input, :scenario, %{entity: entity})
    end
  },
  "fetch" => {
    fn input ->
      %{entity: entity} = input.scenario
      Genesis.Context.fetch(input.context, entity)
    end,
    before_scenario: fn input ->
      entities = seed_entities.(input)
      entity = Enum.random(entities)
      Map.put(input, :scenario, %{entity: entity})
    end
  },
  "lookup" => {
    fn input ->
      %{name: name} = input.scenario
      Genesis.Context.lookup(input.context, name)
    end,
    before_scenario: fn input ->
      seed_entities.(input)
      entity = Genesis.Context.create(input.context, name: "benchmark_target")
      components = build_components.(input.component_types)
      Genesis.Context.assign(input.context, entity, components)
      Map.put(input, :scenario, %{name: "benchmark_target"})
    end
  },
  "get" => {
    fn input ->
      %{entity: entity, component_type: component_type} = input.scenario
      Genesis.Context.get(input.context, entity, component_type)
    end,
    before_scenario: fn input ->
      entities = seed_entities.(input)
      entity = Enum.random(entities)
      component_type = Enum.random(input.component_types)
      Map.put(input, :scenario, %{entity: entity, component_type: component_type})
    end
  },
  "all" => {
    fn input ->
      %{component_type: component_type} = input.scenario
      Genesis.Context.all(input.context, component_type)
    end,
    before_scenario: fn input ->
      seed_entities.(input)
      component_type = Enum.random(input.component_types)
      Map.put(input, :scenario, %{component_type: component_type})
    end
  },
  "emplace" => {
    fn input ->
      %{entity: entity, component: component} = input.scenario
      Genesis.Context.emplace(input.context, entity, component)
    end,
    before_scenario: fn input ->
      seed_entities.(input)
      entity = Genesis.Context.create(input.context)
      [component | other_components] = build_components.(input.component_types)
      Genesis.Context.assign(input.context, entity, other_components)
      Map.put(input, :scenario, %{entity: entity, component: component})
    end
  },
  "replace" => {
    fn input ->
      %{entity: entity, component: component} = input.scenario
      Genesis.Context.replace(input.context, entity, component)
    end,
    before_scenario: fn input ->
      entities = seed_entities.(input)
      entity = Enum.random(entities)
      component_type = Enum.random(input.component_types)
      component = struct!(component_type, %{key: "updated", value: 999})
      Map.put(input, :scenario, %{entity: entity, component: component})
    end
  },
  "patch" => {
    fn input ->
      %{entity: entity, metadata: metadata} = input.scenario
      Genesis.Context.patch(input.context, entity, metadata)
    end,
    before_scenario: fn input ->
      entities = seed_entities.(input)
      entity = Enum.random(entities)
      metadata = %{updated_at: System.system_time(), extra: "data"}
      Map.put(input, :scenario, %{entity: entity, metadata: metadata})
    end
  },
  "erase" => {
    fn input ->
      %{entity: entity, component_type: component_type} = input.scenario
      Genesis.Context.erase(input.context, entity, component_type)
    end,
    before_scenario: fn input ->
      entities = seed_entities.(input)
      entity = Enum.random(entities)
      component_type = Enum.random(input.component_types)
      Map.put(input, :scenario, %{entity: entity, component_type: component_type})
    end
  },
  "destroy" => {
    fn input ->
      %{entity: entity} = input.scenario
      Genesis.Context.destroy(input.context, entity)
    end,
    before_scenario: fn input ->
      entities = seed_entities.(input)
      entity = Enum.random(entities)
      Map.put(input, :scenario, %{entity: entity})
    end
  },
  "create" => {
    fn input ->
      Genesis.Context.create(input.context)
    end,
    before_scenario: fn input ->
      seed_entities.(input)
      Map.put(input, :scenario, %{})
    end
  },
  "match" => {
    fn input ->
      %{component_type: component_type, value: value} = input.scenario
      Genesis.Context.match(input.context, component_type, value: value)
    end,
    before_scenario: fn input ->
      seed_entities.(input)
      component_type = Enum.random(input.component_types)
      value = Enum.random(1..length(input.component_types))
      Map.put(input, :scenario, %{component_type: component_type, value: value})
    end
  },
  "at_least" => {
    fn input ->
      %{component_type: component_type, value: value} = input.scenario
      Genesis.Context.at_least(input.context, component_type, :value, value)
    end,
    before_scenario: fn input ->
      seed_entities.(input)
      component_type = Enum.random(input.component_types)
      value = Enum.random(1..length(input.component_types))
      Map.put(input, :scenario, %{component_type: component_type, value: value})
    end
  },
  "at_most" => {
    fn input ->
      %{component_type: component_type, value: value} = input.scenario
      Genesis.Context.at_most(input.context, component_type, :value, value)
    end,
    before_scenario: fn input ->
      seed_entities.(input)
      component_type = Enum.random(input.component_types)
      value = Enum.random(1..length(input.component_types))
      Map.put(input, :scenario, %{component_type: component_type, value: value})
    end
  },
  "between" => {
    fn input ->
      %{component_type: component_type, min: min, max: max} = input.scenario
      Genesis.Context.between(input.context, component_type, :value, min, max)
    end,
    before_scenario: fn input ->
      seed_entities.(input)
      component_type = Enum.random(input.component_types)
      values = Enum.take_random(1..length(input.component_types), 2)

      Map.put(input, :scenario, %{
        component_type: component_type,
        min: Enum.min(values),
        max: Enum.max(values)
      })
    end
  },
  "children_of" => {
    fn input ->
      %{parent: parent} = input.scenario
      Genesis.Context.children_of(input.context, parent)
    end,
    before_scenario: fn input ->
      seed_entities.(input)
      parent = Genesis.Context.create(input.context)
      components = build_components.(input.component_types)
      Genesis.Context.assign(input.context, parent, components)

      # Make 10% of max entities as children
      num_children = max(1, div(input.max_entities, 10))

      Enum.each(1..num_children, fn _ ->
        child = Genesis.Context.create(input.context, parent: parent)
        Genesis.Context.assign(input.context, child, build_components.(input.component_types))
      end)

      Map.put(input, :scenario, %{parent: parent})
    end
  },
  "all_of" => {
    fn input ->
      %{component_types: component_types} = input.scenario
      Genesis.Context.all_of(input.context, component_types)
    end,
    before_scenario: fn input ->
      seed_entities.(input)
      count = min(2, length(input.component_types))
      component_types = Enum.take_random(input.component_types, count)
      Map.put(input, :scenario, %{component_types: component_types})
    end
  },
  "any_of" => {
    fn input ->
      %{component_types: component_types} = input.scenario
      Genesis.Context.any_of(input.context, component_types)
    end,
    before_scenario: fn input ->
      seed_entities.(input)
      count = min(2, length(input.component_types))
      component_types = Enum.take_random(input.component_types, count)
      Map.put(input, :scenario, %{component_types: component_types})
    end
  },
  "none_of" => {
    fn input ->
      %{component_types: component_types} = input.scenario
      Genesis.Context.none_of(input.context, component_types)
    end,
    before_scenario: fn input ->
      seed_entities.(input)
      count = min(2, length(input.component_types))
      component_types = Enum.take_random(input.component_types, count)
      Map.put(input, :scenario, %{component_types: component_types})
    end
  },
  "clear" => {
    fn input ->
      Genesis.Context.clear(input.context)
    end,
    before_scenario: fn input ->
      seed_entities.(input)
      Map.put(input, :scenario, %{})
    end
  },
  "metadata" => {
    fn input ->
      %{limit: limit} = input.scenario
      Enum.take(Genesis.Context.metadata(input.context), limit)
    end,
    before_scenario: fn input ->
      seed_entities.(input)
      limit = div(input.max_entities, 2)
      Map.put(input, :scenario, %{limit: limit})
    end
  },
  "components" => {
    fn input ->
      %{limit: limit} = input.scenario
      Enum.take(Genesis.Context.components(input.context), limit)
    end,
    before_scenario: fn input ->
      seed_entities.(input)
      limit = div(input.max_entities, 2)
      Map.put(input, :scenario, %{limit: limit})
    end
  },
  "entities" => {
    fn input ->
      %{limit: limit} = input.scenario
      Enum.take(Genesis.Context.entities(input.context), limit)
    end,
    before_scenario: fn input ->
      seed_entities.(input)
      limit = div(input.max_entities, 2)
      Map.put(input, :scenario, %{limit: limit})
    end
  }
}

################################################################################
# Benchmark!
#################################################################################
# Pre-create fake component types (plain structs)
component_types =
  Enum.map(0..99, fn index ->
    name = :"Elixir.Component#{index}"
    opts = Macro.Env.location(__ENV__)
    struct = quote(do: defstruct([:key, :value]))
    with {:module, _, _, _} <- Module.create(name, struct, opts), do: name
  end)

{:ok, context} = Genesis.Context.start_link()

inputs = %{
  "small" => %{max_entities: 10},
  "medium" => %{max_entities: 100},
  "large" => %{max_entities: 1_000}
}

# Filter the jobs we actually want to run
jobs =
  Enum.filter(jobs, fn {key, _} ->
    Regex.match?(~r/#{filter}/, key)
  end)

Benchee.run(
  jobs,
  time: 3,
  memory_time: 2,
  inputs: inputs,
  before_scenario: fn input ->
    input
    |> Map.put(:context, context)
    |> Map.put(:component_types, component_types)
  end,
  after_scenario: fn input ->
    Genesis.Context.clear(input.context)
    Map.delete(input, :scenario)
  end,
  print: [fast_warning: false],
  measure_function_call_overhead: true,
  formatters: [{Benchee.Formatters.Console, extended_statistics: true}]
)
