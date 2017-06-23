defmodule Transfusion.MessageTest do
  use ExUnit.Case

  defmodule TestConsumer do
    def test(%{field: value, pid: pid}), do: send(pid, {:msg, value})
    def test(%{pid: pid} = msg), do: send(pid, {:msg, msg})
  end

  defmodule TestRouter do
    use Transfusion.Router

    topic "events", TestConsumer do
      map "test", to: :test
    end
  end

  defmodule TestMessage do
    use Transfusion.Message, router: TestRouter

    def generate_message_type(%{field: value}), do: value
    def topic, do: "events"
  end

  test "setup with functions" do
    assert TestMessage.topic() == "events"
    assert TestMessage.generate_message_type(%{field: "dynamic"}) == "dynamic"
  end

  test "publishes message" do
    assert {:ok, _} = TestMessage.publish(%{field: "test", pid: self()})
    assert_receive {:msg, "test"}, 10 # Short delay for async tasks to work
  end

  defmodule DslMessage do
    use Transfusion.Message, router: TestRouter

    topic "events"
    message_type "static"
  end

  test "setup with DSL" do
    assert DslMessage.topic() == "events"
    assert DslMessage.generate_message_type(%{}) == "static"
  end

  defmodule ValidatedMessage do
    use Transfusion.Message, router: TestRouter

    topic "events"
    message_type "test"

    values do
      attribute :always, Map, required: true
      attribute :sometimes, Map
      attribute :string, String
      attribute :pid, Any
    end
  end

  test "validate message fields" do
    assert {:ok, _} = ValidatedMessage.validate(%{always: %{}, sometimes: %{}})
    assert {:ok, _} = ValidatedMessage.validate(%{always: %{}, sometimes: nil})
    assert {:ok, _} = ValidatedMessage.validate(%{always: %{}})
    assert {:ok, _} = ValidatedMessage.validate(%{always: %{}, string: "I am a string"})

    assert {:error, [":string (binary) invalid value: 42"]} = ValidatedMessage.validate(%{always: %{}, string: 42})
    assert {:error, [_, ":always is required"]} = ValidatedMessage.validate(%{string: 42})
  end

  test "validate and publish" do
    assert {:ok, _} = ValidatedMessage.publish(%{always: %{one: 1}, pid: self(), string: "success"})
    assert_receive {:msg, %{always: %{one: 1}, pid: _, string: "success"}}, 10 # Short delay for async tasks to work

    assert {:error, [":always is required"]} = ValidatedMessage.publish(%{})
  end
end
