defmodule PruebaSupervisor do
  def main do
    Almacen.usar_directorio_temporal()
    {:ok, _} = SupervisorEmergencias.start_link()

    Util2.mostrar("=== ÁRBOL ===", :mensaje)

    Supervisor.which_children(SupervisorEmergencias)
    |> Enum.each(fn {id, pid, tipo, _} -> Util2.mostrar("  #{inspect(id)} #{inspect(pid)} #{tipo}", :mensaje) end)

    ServidorZonas.registrar_zona("Z01", "Centro", "critico", 5000)
    ServidorRecursos.registrar("R001", "agua", 50, "litros", "centro_acopio_1")

    Util2.mostrar("\n=== MATAR ServidorRecursos ===", :mensaje)
    pid_viejo = Process.whereis(ServidorRecursos)
    Process.exit(pid_viejo, :kill)
    :timer.sleep(200)
    pid_nuevo = Process.whereis(ServidorRecursos)

    Util2.mostrar("PID viejo: #{inspect(pid_viejo)}, PID nuevo: #{inspect(pid_nuevo)}", :mensaje)
    Util2.mostrar("¿Se reinició? #{pid_nuevo != nil and pid_nuevo != pid_viejo}", :mensaje)

    {:ok, recurso} = ServidorRecursos.consultar("R001")
    Util2.mostrar("Inventario recuperado: #{recurso.cantidad} litros", :mensaje)

    Util2.mostrar("\n=== Los demás servidores no se afectan ===", :mensaje)
    {:ok, zona} = ServidorZonas.consultar("Z01")
    Util2.mostrar("Zona Z01 sigue ahí: #{zona.nombre}", :mensaje)

    Util2.mostrar("\n=== DynamicSupervisor ===", :mensaje)

    {:ok, hijo} =
      DynamicSupervisor.start_child(
        SupervisorSesiones,
        %{id: :demo, start: {Agent, :start_link, [fn -> :sesion end]}, restart: :temporary}
      )

    DynamicSupervisor.count_children(SupervisorSesiones) |> IO.inspect(label: "Hijos dinámicos")
    DynamicSupervisor.terminate_child(SupervisorSesiones, hijo)
    DynamicSupervisor.count_children(SupervisorSesiones) |> IO.inspect(label: "Tras terminar")
  end
end

PruebaSupervisor.main()
