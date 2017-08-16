defmodule Transfusion.RouterTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  defmodule TestConsumer do
    def error(_msg), do: :error
    def prefix(%{msg: msg, pid: pid}), do: send(pid, {:msg, msg})
    def test(%{msg: msg, pid: pid}), do: send(pid, {:msg, msg})
    def wildcard(%{msg: msg, pid: pid}), do: send(pid, {:msg, msg})
    def retries(_msg), do: {:error, :retry}
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

    def handle_error(:max_retries, %{pid: pid}) do
      send(pid, :max_retries)
      :noretry
    end

    def handle_error(:retry, _msg), do: :retry

    def handle_error(_error, %{pid: pid}) do
      send(pid, :error)
      :noretry
    end
  end

  defmodule ExceptionConsumer do
    defexception ~w(message pid)a

    def test(%{pid: pid}), do: raise ExceptionConsumer, pid: pid
  end

  defmodule ExceptionRouter do
    use Transfusion.Router,
      exception_strategy: :error

    topic "events", ExceptionConsumer do
      map "test", to: :test
    end

    def handle_error(%{pid: pid}, _) do
      send(pid, :exception)
      :noretry
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

  test "invokes error handler for max retries" do
    TestRouter.start_link()

    meta = %{id: "abc123", attempts: 2, topic: "events", type: ["test"]}

    log_output = capture_log(fn ->
      TestRouter.publish("events", "retry", %{pid: self(), _meta: meta})
      Process.sleep(100)
    end)

    assert_receive :max_retries, 50
    assert log_output =~ ~r/ERROR: :max_retries/

    GenServer.stop(TestRouter, :normal)
  end

  test "consumer errors invoke error handler" do
    TestRouter.start_link()

    log_output = capture_log(fn ->
      TestRouter.publish("events", "error", %{pid: self()})
      Process.sleep(100)
    end)

    assert_receive :error, 50
    assert log_output =~ ~r/ERROR: "no error returned"/

    GenServer.stop(TestRouter, :normal)
  end

  test "invokes error handler for exception when strategy is set to `:error`" do
    ExceptionRouter.start_link()

    log_output = capture_log(fn ->
      ExceptionRouter.publish("events", "test", %{pid: self()})
      Process.sleep(100)
    end)

    assert_receive :exception, 50
    assert log_output =~ ~r/ERROR: %Transfusion.RouterTest.ExceptionConsumer/

    GenServer.stop(ExceptionRouter, :normal)
  end
end
