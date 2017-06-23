defmodule Transfusion.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(Task.Supervisor, [[name: Transfusion.TaskSupervisor, restart: :transient]]),
    ]

    opts = [strategy: :one_for_one, name: Transfusion.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
