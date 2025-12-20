defmodule Genesis.UtilsTest do
  use ExUnit.Case, async: true

  alias Genesis.Utils
  alias Genesis.Components.Container
  alias Genesis.Components.Health
  alias Genesis.Components.Moniker
  alias Genesis.Components.MetaInfo
  alias Genesis.Components.Position
  alias Genesis.Components.Selectable

  test "aliasify/1" do
    assert "container" = Utils.aliasify(Container)
    assert "health" = Utils.aliasify(Health)
    assert "moniker" = Utils.aliasify(Moniker)
    assert "meta_info" = Utils.aliasify(MetaInfo)
    assert "position" = Utils.aliasify(Position)
    assert "selectable" = Utils.aliasify(Selectable)
  end

  test "component?/1" do
    assert Utils.component?(Container)
    assert Utils.component?(Health)
    assert Utils.component?(Moniker)
    assert Utils.component?(MetaInfo)
    assert Utils.component?(Position)
    assert Utils.component?(Selectable)
    refute Utils.component?(__MODULE__)
  end
end
