defmodule Transfusion.Message do
  defmacro __using__(opts) do
    router = Keyword.fetch!(opts, :router)

    quote do
      @before_compile Transfusion.Message

      import Transfusion.Message

      Module.register_attribute(__MODULE__, :fields, accumulate: true, persist: false)

      def publish(msg) do
        case validate(msg) do
          {:ok, _} -> unquote(router).publish(topic(), generate_message_type(msg), msg)
          {:error, _} = err -> err
        end
      end
    end
  end

  defmacro __before_compile__(_) do
    quote do
      def validate(msg) do
        errors =
          @fields
          |> Enum.map(&check_type(&1, Map.get(msg, &1)))
          |> Enum.filter_map(&(elem(&1, 0) == :error), &(elem(&1, 1)))

        if length(errors) > 0 do
          {:error, errors}
        else
          {:ok, msg}
        end
      end

      defoverridable [validate: 1]

      def check_type(_, value), do: {:ok, value}

      defoverridable [check_type: 2]
    end
  end

  defmacro topic(topic) do
    quote do
      def topic, do: unquote(topic)

      defoverridable [topic: 0]
    end
  end

  defmacro message_type(type) do
    quote do
      def generate_message_type(_), do: unquote(type)

      defoverridable [generate_message_type: 1]
    end
  end

  defmacro attribute(field, {:__aliases__, _, [type]}, opts \\ []) do
    quote do
      Module.put_attribute(__MODULE__, :fields, unquote(field))

      unquote(nil_handler(field, opts))
      unquote(type_field(field, type))

      def check_type(unquote(field), value), do: {:ok, value}
    end
  end

  defmacro values([do: block]) do
    quote do
      unquote(block)
    end
  end

  defp nil_handler(field, opts) do
    required = Keyword.get(opts, :required, false)
    if required do
      quote do
        def check_type(unquote(field), nil) do
          {:error, ":#{unquote(field)} is required"}
        end
      end
    else
      quote do
        def check_type(unquote(field), nil) do
          {:ok, nil}
        end
      end
    end
  end

  defp type_field(_field, :Any) do
    quote do
    end
  end

  defp type_field(field, :String), do: type_check("binary", field)

  defp type_field(field, type) do
    type
    |> to_string
    |> String.downcase
    |> type_check(field)
  end

  defp type_check(type, field) do
    guard = String.to_atom("is_#{type}")

    quote do
      def check_type(unquote(field), value) when not unquote(guard)(value) do
        {:error, ":#{unquote(field)} (#{unquote(type)}) invalid value: #{inspect(value)}"}
      end
    end
  end
end
