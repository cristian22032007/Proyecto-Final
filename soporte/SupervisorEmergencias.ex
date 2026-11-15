defmodule SupervisorEmergencias do
  use Supervisor

  @servidores [
    ServidorUsuarios,
    ServidorZonas,
    ServidorRecursos,
    ServidorNecesidades,
    ServidorPersonas,
    ServidorMascotas,
    ServidorAlbergues
  ]

  def start_link(_opciones \\ []) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def servidores, do: @servidores

  @impl true
  def init(:ok) do
    hijos =
      Enum.map(@servidores, fn servidor ->
        %{id: servidor, start: {servidor, :start_link, [[]]}, restart: :permanent}
      end) ++
        [{DynamicSupervisor, name: SupervisorSesiones, strategy: :one_for_one}]

    Supervisor.init(hijos, strategy: :one_for_one)
  end
end
