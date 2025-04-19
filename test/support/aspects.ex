defmodule Genesis.Aspects.Moniker do
  use Genesis.Aspect, events: [:describe]

  prop :name, :string, required: true
  prop :description, :string, required: false
end

defmodule Genesis.Aspects.Position do
  use Genesis.Aspect, events: [:move]

  prop :x, :integer, required: true
  prop :y, :integer, required: true
end

defmodule Genesis.Aspects.Health do
  use Genesis.Aspect, events: [:take_damage]

  prop :current, :integer, required: true
  prop :maximum, :integer, required: false
end
