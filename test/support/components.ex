defmodule Genesis.Components.Moniker do
  use Genesis.Component, events: [:describe]

  prop :name, :string
  prop :description, :string
end

defmodule Genesis.Components.Position do
  use Genesis.Component, events: [:move]

  prop :x, :integer
  prop :y, :integer
end

defmodule Genesis.Components.Health do
  use Genesis.Component, events: [:damage]

  prop :current, :integer
  prop :maximum, :integer
end

defmodule Genesis.Components.Selectable do
  use Genesis.Component, events: [:select, :deselect]
  # No properties defined (this will function as a tag)
end

defmodule Genesis.Components.Container do
  use Genesis.Component, events: [:open, :close, :add, :remove]

  prop :name, :string
  prop :capacity, :integer, required: true
  prop :weight, :float, default: 0.0
  prop :owner, :string, default: "Unassigned"
  prop :is_locked, :boolean, default: false
  prop :durability, :integer, default: 100
  prop :material, :atom, default: :wood
end

defmodule Genesis.Components.MetaInfo do
  use Genesis.Component

  prop :metadata, :any
  prop :creation_date, Date
end
