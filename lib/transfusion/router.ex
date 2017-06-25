defmodule Transfusion.Router do
  @moduledoc """
  """

  defmacro __using__(_opts) do
    quote do
      import Transfusion.Router

      require Logger

      def publish(topic, %{message_type: type} = msg) do # hold over from Exque
        IO.warn("[#{__MODULE__}] deprecated use publish/3", Macro.Env.stacktrace(__ENV__))
        publish(topic, type, msg)
      end
      def publish(topic, type, msg) when is_binary(type) do
        publish(topic, String.split(type, "."), msg)
      end
      def publish(topic, type, msg) when is_list(type) do
        if ignore?(topic, type) do
          Logger.debug(fn -> "[#{__MODULE__}] ignored (#{topic}/#{Enum.join(type, ".")}): #{inspect(msg)}" end)
        else
          broadcast(topic, type, msg)
          route(topic, type, msg)
        end
      end

      @before_compile Transfusion.Router
    end
  end

  defmacro __before_compile__(%{module: module}) do
    quote do
      unquote(broadcast_catchall(module))

      defp ignore?(_, _), do: false

      defp route(topic, message_type, msg) do
        Logger.debug(fn -> "[#{__MODULE__}] no handler (#{topic}/#{Enum.join(message_type, ".")}): #{inspect(msg)}" end)
      end
    end
  end

  defmacro broadcast(topic, opts) do
    broadcast_function(topic, opts)
  end

  defmacro forward(topic, [to: router]) do
    quote do
      defp route(unquote(topic), message_type, msg) do
        unquote(router).publish(unquote(topic), Enum.join(message_type, "."), msg)
      end
    end
  end

  defmacro ignore(topic, message_types) when is_list(message_types) do
    for message_type <- message_types, do: ignore_function(topic, message_type)
  end

  defmacro topic(topic, consumer, [do: block]), do: message_mapping(topic, consumer, block)

  defp broadcast_catchall(module) do
    unless Module.defines?(module, {:broadcast, 3}) do
      quote do
        defp broadcast(_, _, _), do: :ok # Do nothing
      end
    end
  end

  defp broadcast_function(topic, [to: routers]) when is_list(routers) do
    topic_match =
      if topic == "*" do
        {:_, [], Elixir} # AST for `_`
      else
        topic
      end

    quote do
      defp broadcast(unquote(topic_match) = topic, message_type, msg) do
        Enum.map(unquote(routers), fn (router) ->
          Task.Supervisor.start_child(Transfusion.TaskSupervisor, router, :publish, [topic, message_type, msg])
        end)
      end
    end
  end

  defp broadcast_function(topic, [to: router]) do
    broadcast_function(topic, [to: [router]])
  end

  defp ignore_function(topic, message_type) do
    message_match = message_type_match(message_type)

    quote do
      defp ignore?(unquote(topic), unquote(message_match), msg) do
        true
      end
    end
  end

  defp message_mapping(topic, consumer, {:__block__, _, mappings}),
    do: Enum.map(mappings, &message_mapping(topic, consumer, &1))
  defp message_mapping(topic, consumer, {:map, _, mapping}),
    do: message_mapping(topic, consumer, mapping)
  defp message_mapping(topic, consumer, [message_type, [to: handler]]) do
    message_match = message_type_match(message_type)
    quote do
      defp route(unquote(topic), unquote(message_match), msg) do
        Logger.debug(fn -> "[#{__MODULE__}] routing (#{unquote(topic)}/#{unquote(message_type)}): #{inspect(msg)}" end)
        Task.Supervisor.start_child(Transfusion.TaskSupervisor, unquote(consumer), unquote(handler), [msg])

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
