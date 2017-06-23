defmodule Transfusion.MessageTest do
  use ExUnit.Case

  defmodule TestConsumer do
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

    values do
      attribute :field, String
      attribute :pid, Pid
    end
  end

  test "setup with functions" do
    assert TestMessage.topic() == "events"
    assert TestMessage.generate_message_type(%{field: "dynamic"}) == "dynamic"
  end

  test "publishes message" do
    assert {:ok, _} = TestMessage.publish(%{field: "test", pid: self()})
    assert_receive {:msg, %{field: "test"}}, 10 # Short delay for async tasks to work
  end

  test "excludes undocumented fields" do
    assert {:ok, _} = TestMessage.publish(%{field: "test", pid: self(), unknown: "unknown"})
    assert_receive {:msg, msg}, 10 # Short delay for async tasks to work
    refute Map.has_key?(msg, :unknown)
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
      attribute :float, Float
      attribute :integer, Integer
      attribute :number, Number
      attribute :pid, Pid
      attribute :string, String
    end
  end

  test "validate message fields" do
    assert {:ok, _} = ValidatedMessage.validate(%{always: %{}})
    assert {:ok, _} = ValidatedMessage.validate(%{always: %{}, string: nil})
    assert {:ok, _} = ValidatedMessage.validate(%{always: %{}, string: "I am a string"})

    assert {:error, [_, _]} = ValidatedMessage.validate(%{string: 42})
    assert {:error, [":string (binary) invalid value: 42"]} = ValidatedMessage.validate(%{always: %{}, string: 42})
    assert {:error, [":integer (integer)" <> _]} = ValidatedMessage.validate(%{always: %{}, integer: "binary"})
    assert {:error, [":number (number)" <> _]} = ValidatedMessage.validate(%{always: %{}, number: "binary"})
    assert {:error, [":float (float)" <> _]} = ValidatedMessage.validate(%{always: %{}, float: "binary"})
    assert {:error, [":pid (pid)" <> _]} = ValidatedMessage.validate(%{always: %{}, pid: "binary"})
  end

  test "validate and publish" do
    assert {:ok, _} = ValidatedMessage.publish(%{always: %{one: 1}, pid: self(), string: "success"})
    assert_receive {:msg, %{always: %{one: 1}, pid: _, string: "success"}}, 10 # Short delay for async tasks to work

    assert {:error, [":always is required"]} = ValidatedMessage.publish(%{})
  end
end
