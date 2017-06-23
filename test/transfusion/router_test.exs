defmodule Transfusion.RouterTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  defmodule TestConsumer do
    def prefix(msg), do: IO.puts(msg)
    def test(msg), do: IO.puts(msg)
    def wildcard(msg), do: IO.puts(msg)
  end

  defmodule TestRouter do
    use Transfusion.Router

    topic "events", TestConsumer do
      map "*.prefix", to: :prefix
      map "test", to: :test
      map "wildcard.*", to: :wildcard
    end
  end

  test "messages route correctly" do
    assert capture_io(fn ->
      TestRouter.publish("events", "test", "it works!")
      Process.sleep(10) # Tiny delay for `Task.async/3` to work
    end) == "it works!\n"
  end

  test "routes wildcard messages" do
    assert capture_io(fn ->
      TestRouter.publish("events", "wildcard.matching", "it works!")
      Process.sleep(10) # Tiny delay for `Task.async/3` to work
    end) == "it works!\n"
  end

  test "allows for wildcards as prefix" do
    assert capture_io(fn ->
      TestRouter.publish("events", "anything.prefix", "it works!")
      Process.sleep(10) # Tiny delay for `Task.async/3` to work
    end) == "it works!\n"
  end
end
