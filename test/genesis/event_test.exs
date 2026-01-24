defmodule Genesis.EventTest do
  use ExUnit.Case

  defmodule DriftHandler do
    def handle_event(_name, event) do
      {:cont, %{event | world: nil}}
    end
  end

  test "raises when event drifts during processing" do
    assert_raise RuntimeError, "Event drifted during processing!", fn ->
      Genesis.Event.process(
        Genesis.Event.new(:ping,
          world: self(),
          entity: nil,
          handlers: [DriftHandler]
        )
      )
    end
  end
end
