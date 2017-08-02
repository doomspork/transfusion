defmodule Transfusion.Router do
  @moduledoc """
  """

  defmacro __using__(opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 5)
    retry_after = Keyword.get(opts, :retry_after, 300) # Seconds, 300 = 5 minutes

    quote do
      use GenServer

      import Transfusion.Router

      require Logger

      def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

      def init(state) do
        Process.send_after(self(), :sweep, 1000)

        {:ok, state}
      end

      def handle_cast({:ack, %{_meta: %{id: id}} = msg, resp}, queue) do
        Logger.info(fn -> "Message (#{pretty_msg(msg)}) SUCCESS: #{inspect(resp)}" end)
        {:noreply, remove_msg(queue, id)}
      end

      def handle_cast({:error, %{_meta: %{id: id}} = msg, reason}, queue) do
        Logger.error(fn -> "Message (#{pretty_msg(msg)}) ERROR: #{inspect(reason)}" end)
        on_error(reason, msg)
        {:noreply, remove_msg(queue, id)}
      end

      def handle_cast({:publish, topic, type, msg}, queue) do
        %{_meta: %{id: id}} = msg = attach_meta(topic, type, msg)

        broadcast(topic, type, msg)

        queue =
          case route(topic, type, msg) do
            :noop -> queue
            _ -> Map.put(queue, id, msg)
          end

        {:noreply, queue}
      end

      def handle_info(:sweep, queue) do
        expired_ids =
          queue
          |> Enum.filter(&expired?(now(), &1))
          |> Keyword.keys

        {expired, queue} = Map.split(queue, expired_ids)

        Enum.each(expired, &republish/1)
        Process.send_after(self(), :sweep, 1000)

        {:noreply, queue}
      end

      def publish(topic, type, msg) when is_binary(type), do: publish(topic, String.split(type, "."), msg)
      def publish(topic, type, msg) when is_list(type), do: GenServer.cast(__MODULE__, {:publish, topic, type, msg})

      def republish(%{_meta: %{attempts: attempts} = meta} = msg, error \\ nil) do
        unless is_nil(error), do: Logger.error("Republish because: #{inspect(error)}")

        msg =
          if attempts >= unquote(max_retries) do
            {:error, msg, :max_retries}
          else
            {:publish, meta.topic, meta.type, msg}
          end

        GenServer.cast(__MODULE__, msg)
      end

      def run_route(consumer, handler, msg) do
        try do
          consumer
          |> apply(handler, [msg])
          |> route_result(msg)
        rescue
          e -> republish(msg, e)
        end
      end

      defp attach_meta(topic, type, msg) do
        meta = Map.get(msg, :_meta, default_meta(topic, type))
        meta = Map.merge(meta, %{attempts: meta.attempts + 1})

        Map.put(msg, :_meta, meta)
      end

      defp default_meta(topic, type),
        do: %{attempts: 0, id: gen_id(), published_at: now(), router: self(), topic: topic, type: type}

      defp expired?(now, {_, %{_meta: %{attempts: attempts, published_at: published_at}}}),
        do: (published_at + (attempts * unquote(retry_after))) < now

      defp gen_id do
        64
        |> :crypto.strong_rand_bytes
        |> Base.url_encode64
        |> String.replace(~r{[^a-zA-Z0-9]}, "")
        |> binary_part(0, 64)
      end

      defp now, do: System.system_time(:second)

      defp pretty_msg(%{_meta: %{topic: topic, type: type, id: id}}), do: "#{topic}.#{Enum.join(type, ".")} (id: #{id})"

      defp remove_msg(queue, msg_id), do: Map.delete(queue, msg_id)

      defp route_result(:error, msg), do: route_result({:error, "no error returned"}, msg)
      defp route_result({:error, reason}, msg), do: GenServer.cast(__MODULE__, {:error, msg, reason})
      defp route_result(:ok, msg), do: route_result({:ok, "no result returned"}, msg)
      defp route_result({:ok, resp}, msg), do: GenServer.cast(__MODULE__, {:ack, msg, resp})
      defp route_result(nil, msg), do: route_result(:ok, msg)
      defp route_result(result, msg), do: route_result({:ok, result}, msg)

      @before_compile Transfusion.Router
    end
  end

  defmacro __before_compile__(%{module: module}) do
    quote do
      unquote(broadcast_catchall(module))
      unquote(error_handler(module))

      defp route(_topic, _message_type, _msg), do: :noop

      defoverridable [route: 3]
    end
  end

  defmacro broadcast(topic, opts) do
    broadcast_function(topic, opts)
  end

  defmacro on_error(callback) do
    case callback do
      cb when is_atom(cb) ->
        quote do
          def on_error(error, msg) do
            apply(__MODULE__, unquote(callback), [error, msg])
          end
        end
      {:fn, _, _} ->
        quote do
          def on_error(error, msg) do
            apply(unquote(callback), [error, msg])
          end
        end
      _ -> raise "on_error/2 must be a function or atom"
    end
  end

  defmacro forward(topic, [to: router]) do
    quote do
      defp route(unquote(topic), message_type, msg) do
        unquote(router).publish(unquote(topic), Enum.join(message_type, "."), msg)
      end
    end
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

  defp error_handler(module) do
    unless Module.defines?(module, {:on_error, 2}) do
      quote do
        defp on_error(_, _), do: :ok # Do nothing
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
        Task.Supervisor.start_child(Transfusion.TaskSupervisor, __MODULE__, :run_route, [unquote(consumer), unquote(handler), msg])
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
