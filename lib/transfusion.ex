defmodule Transfusion do
  @moduledoc """
  Documentation for Transfusion.
  """

  def publish(topic, %{} = msg) do
  end
  def publish(_, _), do: {:error, "unsupported message type"}
end
