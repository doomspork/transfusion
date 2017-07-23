defmodule Transfusion.RouterTest do
  use ExUnit.Case, async: false

  defmodule TestConsumer do
    def error(_msg), do: :error
    def prefix(%{msg: msg, pid: pid}), do: send(pid, {:msg, msg})
    def test(%{msg: msg, pid: pid}), do: send(pid, {:msg, msg})
    def wildcard(%{msg: msg, pid: pid}), do: send(pid, {:msg, msg})
  end

  defmodule TestRouter do
    use Transfusion.Router,
      max_retries: 2,
      retry_after: 100

    topic "events", TestConsumer do
      map "*.prefix", to: :prefix
      map "error", to: :error
      map "test", to: :test
      map "wildcard.*", to: :wildcard
    end

    on_error fn
      (:max_retries, msg) -> send(msg.pid, :max_retries)
      (_, msg) -> send(msg.pid, :error)
    end
  end

  test "messages route correctly" do
    TestRouter.start_link()

    TestRouter.publish("events", "test", %{msg: "route", pid: self()})
    assert_receive {:msg, "route"}, 50

    GenServer.stop(TestRouter, :normal)
  end

  test "routes wildcard messages" do
    TestRouter.start_link()

    TestRouter.publish("events", "wildcard.matching", %{msg: "wildcard", pid: self()})
    assert_receive {:msg, "wildcard"}, 50

    GenServer.stop(TestRouter, :normal)
  end

  test "allows for wildcards as prefix" do
    TestRouter.start_link()

    TestRouter.publish("events", "anything.prefix", %{msg: "prefix", pid: self()})
    assert_receive {:msg, "prefix"}, 50

    GenServer.stop(TestRouter, :normal)
  end

  test "triggers on_error/2 for max retries" do
    TestRouter.start_link()

    TestRouter.publish("events", "test", %{pid: self(), _meta: %{id: "abc123", attempts: 3}})

    assert_receive :max_retries, 50

    GenServer.stop(TestRouter, :normal)
  end

  test "consumer errors trigger on_error/2" do
    TestRouter.start_link()

    TestRouter.publish("events", "error", %{pid: self()})

    assert_receive :error, 150

    GenServer.stop(TestRouter, :normal)
  end
end
