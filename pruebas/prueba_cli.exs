defmodule PruebaCli do
  def main do
    Almacen.usar_directorio_temporal()
    {:ok, _} = SupervisorEmergencias.start_link()

    titulo("SESIONES")
    laura = ejecutar(nil, "connect laura 1234 coordinador centro")
    carlos = ejecutar(nil, "connect carlos 1234 coordinador centro")
    ana = ejecutar(nil, "connect ana 1234 ciudadano zona_norte")
    pedro = ejecutar(nil, "connect pedro 1234 voluntario zona_norte")

    titulo("ZONAS")
    ejecutar(laura, ~s(register_zone centro "Centro" critico 5000))
    ejecutar(laura, ~s(register_zone zona_norte "Zona Norte" alto 800))
    ejecutar(laura, "register_sector centro sector_3 alto 1200")
    ejecutar(laura, ~s(register_point centro sector_3 "Punto sector 3" 150))
    ejecutar(laura, "zone_status centro")
    ejecutar(laura, "register_need agua 30 critica zona_inexistente x")

    titulo("NECESIDADES Y RECURSO")
    ejecutar(laura, ~s(register_need agua 30 critica centro "Punto de atención sector 3"))
    ejecutar(laura, "register_resource R001 agua 50 litros centro_acopio_1")
    ejecutar(carlos, ~s(register_need agua 25 alta centro "Albergue del centro"))

    titulo("CONFLICTO: dos coordinadores asignan sobre 50 litros")
    Util2.mostrar("> (laura) assign_resource N001 R001   |   (carlos) assign_resource N002 R001", :mensaje)

    [
      Task.async(fn -> Cli.procesar_linea(laura, "assign_resource N001 R001") end),
      Task.async(fn -> Cli.procesar_linea(carlos, "assign_resource N002 R001") end)
    ]
    |> Enum.each(&Task.await/1)

    titulo("PERSONAS Y MENSAJES")
    ejecutar(ana, ~s(report_person 1001 "Andrés Gómez" 34 zona_norte localizada))
    ejecutar(ana, ~s(send_family_message 1001 "Estoy bien, estoy en el albergue norte"))
    ejecutar(ana, "list_family_messages 1001")
    ejecutar(laura, "mark_message M001 entregado")

    titulo("ALBERGUE")
    ejecutar(laura, ~s(register_shelter A01 "Albergue Norte" zona_norte 150))
    ejecutar(pedro, "register_entry A01 1001")
    ejecutar(pedro, "find_person 1001")
    ejecutar(laura, "shelter_resource A01 R001")
    ejecutar(laura, "shelter_need A01 N001")
    ejecutar(laura, "check_shelter A01")

    titulo("MASCOTAS")
    ejecutar(ana, ~s(report_pet lost perro "Luna" negra mediana zona_norte 3001111111 "collar rojo y mancha blanca"))
    ejecutar(pedro, ~s(report_pet found perro desconocido negra mediana zona_norte 3003333333 "collar rojo"))
    ejecutar(pedro, "match_pets")
    ejecutar(laura, "confirm_match MA001 MA002")
    ejecutar(laura, "list_pets estado=resuelta")

    titulo("PERMISOS Y ERRORES")
    ejecutar(ana, "assign_resource N001 R001")
    ejecutar(pedro, ~s(register_zone sur "Sur" bajo))
    ejecutar(nil, "list_needs")
    ejecutar(laura, "volar")
    ejecutar(laura, "register_need agua")
    ejecutar(laura, "list_needs prioridad=urgente")
    ejecutar(laura, ~s(register_need agua 5 alta centro "comillas sin cerrar))

    titulo("CONSULTAS")
    ejecutar(laura, "list_needs zona=centro prioridad=critica")
    ejecutar(laura, "pending_needs")
    ejecutar(laura, "transfer_resource R001 centro_acopio_1 albergue_2 5")
    ejecutar(laura, "list_resources")
    ejecutar(laura, "availability agua")
    ejecutar(laura, "critical_resources")
    ejecutar(laura, "shelter_report 2")

    titulo("RESUMEN")
    ejecutar(laura, "summary")

    titulo("SALIDA")
    ejecutar(pedro, "register_exit A01 1001")
    ejecutar(pedro, "find_person 1001")
    ejecutar(laura, "disconnect")
    ejecutar(nil, "disconnect")
  end

  defp ejecutar(sesion, linea) do
    Util2.mostrar("> #{linea}", :mensaje)
    {:continuar, nueva_sesion} = Cli.procesar_linea(sesion, linea)
    nueva_sesion
  end

  defp titulo(texto), do: Util2.mostrar("\n=== #{texto} ===", :mensaje)
end

PruebaCli.main()
