defmodule Transfusion.Router do
  @moduledoc """
  The Router is in charge of deciding where messages go, whether to broadcast messages out, and how to handle errors.

  # Example

    defmodule Example.Router do
      use Transfusion.Router,
        max_retries: 5,
        retry_after: 10000 # milliseconds

      require Logger

      broadcast "*", to: [AnotherExample.Router]

      forward "users", to: Users.Router

      topic "events", Example.Consumer do
        map "new.message", to: :new
      end

      def handle_error(msg, reason) do
        # Log or submit your error

        :noretry
      end
    end
  """
  defmacro __using__(opts \\ []) do
    quote do
      use GenServer

      require Logger

      import Transfusion.Router

      @type msg :: %{_meta: %{attempts: integer, id: binary}, data: map}

      @doc false
      def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

      @doc false
      def init(state) do
        Process.send_after(self(), :sweep, 1000)

        {:ok, state}
      end

      @doc """
      Acknowledges a message has been processed and can be removed from the queue.
      """
      def handle_cast({:ack, %{_meta: %{id: id}} = msg, resp}, queue) do
        Logger.info(fn -> "Message (#{pretty_msg(msg)}) SUCCESS: #{inspect(resp)}" end)
        {:noreply, Map.delete(queue, id)}
      end

      @doc """
      Handles errored messages and invokes error handling
      """
      def handle_cast({:error, %{_meta: %{id: id}} = msg, reason}, queue) do
        Logger.error(fn -> "Message (#{pretty_msg(msg)}) ERROR: #{inspect(reason)}" end)
        {:noreply, Map.delete(queue, id)}
      end

      @doc """
      Handle publishing of messages.  Attaches meta data, increments attempts, broadcasts the message, and finally
      invokes any route handlers.
      """
      def handle_cast({:publish, topic, type, %{_meta: %{id: id}} = msg}, queue) do
        broadcast(topic, type, msg)

        queue =
          case route(topic, type, msg) do
            :noop -> queue
            _ -> Map.put(queue, id, msg)
          end

        {:noreply, queue}
      end

      @doc """
      Sweeps the queue for expired messages and retries them
      """
      def handle_info(:sweep, queue) do
        expired_ids =
          queue
          |> Enum.filter(&expired?(now(), &1))
          |> Keyword.keys

        {expired, queue} = Map.split(queue, expired_ids)

        Enum.each(expired, &publish/1)
        Process.send_after(self(), :sweep, 1000)

        {:noreply, queue}
      end

      def error(msg, error), do: GenServer.cast(__MODULE__, {:error, msg, error})

      def publish(%{_meta: %{topic: topic, type: type}} = msg), do: publish(topic, type, msg)
      def publish(topic, type, msg) when is_binary(type), do: publish(topic, String.split(type, "."), msg)
      def publish(topic, type, msg) when is_list(type) do
        %{_meta: %{attempts: attempts, id: id}} = msg = attach_meta(topic, type, msg)

        if attempts >= max_retries() do
          error_handling(msg, :max_retries) # This could end up as an infinite loop, let's think about it.
        else
          GenServer.cast(__MODULE__, {:publish, topic, type, msg})
        end
      end

      @doc false
      def run_route(consumer, handler, msg) do
        consumer
        |> apply(handler, [msg])
        |> route_result(msg)
      rescue
        error -> error_handling(msg, error)
      end

      defp config_value(key, default) do
        value = Keyword.get(unquote(opts), key)
        otp_app = Keyword.get(unquote(opts), :otp_app)

        cond do
          not is_nil(value) -> value
          is_nil(value) and not is_nil(otp_app) ->
            otp_app
            |> Application.get_env(__MODULE__)
            |> Keyword.get(key, default)
          true -> default
        end
      end

      defp error_handling(msg, error) do
        case handle_error(error, msg) do
          :retry   -> publish(msg)
          :noretry -> error(msg, error)
          result   -> raise "expected `:retry` or `:noretry`, got `#{result}`"
        end
      end

      def expired?(now, {_, %{_meta: %{attempts: attempts, published_at: published_at}}}),
        do: (published_at + (attempts * retry_after())) < now

      defp max_retries, do: config_value(:max_retries, 5)

      defp retry_after, do: config_value(:retry_after, 300)

      defp route_result(:error, msg), do: error_handling(msg, "no error returned")
      defp route_result({:error, reason}, msg), do: error_handling(msg, reason)
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

      @spec handle_error(any, msg) :: :retry | :noretry

      @doc """
      Invoked for all errors and exceptions
      """
      def handle_error(_e, _msg), do: :noretry

      defp route(_topic, _message_type, _msg), do: :noop

      defoverridable [handle_error: 2, route: 3]
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

  defmacro topic(topic, consumer, [do: block]), do: message_mapping(topic, consumer, block)

  def attach_meta(topic, type, msg) do
    meta = Map.get(msg, :_meta, default_meta(topic, type))
    meta = Map.merge(meta, %{attempts: meta.attempts + 1})

    Map.put(msg, :_meta, meta)
  end

  def default_meta(topic, type),
    do: %{attempts: 0, id: gen_id(), published_at: now(), router: self(), topic: topic, type: type}

  def gen_id do
    64
    |> :crypto.strong_rand_bytes
    |> Base.url_encode64
    |> String.replace(~r{[^a-zA-Z0-9]}, "")
    |> binary_part(0, 64)
  end

  def now, do: System.system_time(:second)

  def pretty_msg(%{_meta: %{topic: topic, type: type, id: id}}), do: "#{topic}.#{Enum.join(type, ".")} (id: #{id})"

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

  defp message_mapping(topic, consumer, {:__block__, _, mappings}),
    do: Enum.map(mappings, &message_mapping(topic, consumer, &1))
  defp message_mapping(topic, consumer, {:map, _, mapping}),
    do: message_mapping(topic, consumer, mapping)
  defp message_mapping(topic, consumer, [message_type, [to: handler]]) do
    message_match = message_type_match(message_type)
    quote do
      defp route(unquote(topic), unquote(message_match), msg) do
        args = [unquote(consumer), unquote(handler), msg]
        Task.Supervisor.start_child(Transfusion.TaskSupervisor, __MODULE__, :run_route, args)
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
