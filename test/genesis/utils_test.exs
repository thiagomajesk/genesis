defmodule Genesis.UtilsTest do
  use ExUnit.Case, async: true

  alias Genesis.Utils
  alias Genesis.Aspects.Container
  alias Genesis.Aspects.Health
  alias Genesis.Aspects.Moniker
  alias Genesis.Aspects.MetaInfo
  alias Genesis.Aspects.Position
  alias Genesis.Aspects.Selectable

  test "aliasify/1" do
    assert "container" = Utils.aliasify(Container)
    assert "health" = Utils.aliasify(Health)
    assert "moniker" = Utils.aliasify(Moniker)
    assert "meta_info" = Utils.aliasify(MetaInfo)
    assert "position" = Utils.aliasify(Position)
    assert "selectable" = Utils.aliasify(Selectable)
  end

  test "aspect?/1" do
    assert Utils.aspect?(Container)
    assert Utils.aspect?(Health)
    assert Utils.aspect?(Moniker)
    assert Utils.aspect?(MetaInfo)
    assert Utils.aspect?(Position)
    assert Utils.aspect?(Selectable)
    refute Utils.aspect?(__MODULE__)
  end
end
