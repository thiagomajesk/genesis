defmodule Genesis.Aspects.Moniker do
  use Genesis.Aspect, events: [:describe]

  prop :name, :string
  prop :description, :string
end

defmodule Genesis.Aspects.Position do
  use Genesis.Aspect, events: [:move]

  prop :x, :integer
  prop :y, :integer
end

defmodule Genesis.Aspects.Health do
  use Genesis.Aspect, events: [:damage]

  prop :current, :integer
  prop :maximum, :integer
end

defmodule Genesis.Aspects.Selectable do
  use Genesis.Aspect, events: [:select, :deselect]
  # No properties defined (this will function as a tag)
end

defmodule Genesis.Aspects.Container do
  use Genesis.Aspect, events: [:open, :close, :add, :remove]

  prop :name, :string
  prop :capacity, :integer, required: true
  prop :weight, :float, default: 0.0
  prop :owner, :string, default: "Unassigned"
  prop :is_locked, :boolean, default: false
  prop :durability, :integer, default: 100
  prop :material, :atom, default: :wood
end

defmodule Genesis.Aspects.MetaInfo do
  use Genesis.Aspect

  prop :creation_date, :any
end
