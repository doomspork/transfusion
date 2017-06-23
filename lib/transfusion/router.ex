defmodule Transfusion.Router do
  defmacro __using__(_opts) do
    quote do
      import Transfusion.Router

      require Logger

      def publish(topic, %{message_type: type} = msg) do # hold over from Exque
        IO.warn("deprecated use publish/3", Macro.Env.stacktrace(__ENV__))
        publish(topic, type, msg)
      end
      def publish(topic, type, msg), do: route(topic, String.split(type, "."), msg)
    end
  end

  defmacro forward(topic, router) do
    quote do
      defp route(unquote(topic), message_type, msg) do
        unquote(router).publish(unquote(topic), message_type, msg)
      end
    end
  end

  defmacro topic(topic, consumer, [do: block]), do: message_mapping(topic, consumer, block)

  defp message_mapping(topic, consumer, {:__block__, _, mappings}),
    do: Enum.map(mappings, &message_mapping(topic, consumer, &1))
  defp message_mapping(topic, consumer, {:map, _, mapping}),
    do: message_mapping(topic, consumer, mapping)
  defp message_mapping(topic, consumer, [message_type, [to: handler]]) do
    message_match = message_type_match(message_type)
    quote do
      defp route(unquote(topic), unquote(message_match), msg) do
        Logger.debug(fn -> "Routing (#{unquote(topic)}/#{unquote(message_type)}): #{inspect(msg)}" end)
        Task.async(unquote(consumer), unquote(handler), [msg])

        {:ok, msg}
      end
    end
  end

  defp message_type_match("*"), do: {:_, [], Elixir}
  defp message_type_match(message_type) do
    message_type
    |> String.split(".")
    |> Enum.map(fn
      ("*") -> {:_, [], Elixir}
      (match) -> match
    end)
  end
end
