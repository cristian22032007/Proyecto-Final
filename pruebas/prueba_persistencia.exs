defmodule PruebaPersistencia do
  @servidores [
    ServidorUsuarios,
    ServidorZonas,
    ServidorRecursos,
    ServidorNecesidades,
    ServidorPersonas,
    ServidorMascotas,
    ServidorAlbergues
  ]

  def main do
    Almacen.usar_directorio_temporal()
    Util2.mostrar("Carpeta de datos: #{Almacen.directorio()}", :mensaje)

    Util2.mostrar("\n=== FASE 1: registrar datos ===", :mensaje)
    iniciar()
    cargar_datos()
    verificar()
    detener()

    Util2.mostrar("\n=== ARCHIVOS GENERADOS ===", :mensaje)

    Almacen.directorio()
    |> File.ls!()
    |> Enum.sort()
    |> Util2.convertir_coleccion_mensaje()
    |> Util2.mostrar(:mensaje)

    Util2.mostrar("Contenido de necesidades.txt:", :mensaje)

    Almacen.directorio()
    |> Path.join("necesidades.txt")
    |> File.read!()
    |> Util2.mostrar(:mensaje)

    Util2.mostrar("\n=== FASE 2: reiniciar los servidores y recuperar ===", :mensaje)
    iniciar()
    verificar()

    Util2.mostrar("\n--- Comprobaciones adicionales ---", :mensaje)
    mostrar("connect con clave correcta", ServidorUsuarios.connect("laura", "1234", "coordinador", "centro"))
    mostrar("connect con clave incorrecta", ServidorUsuarios.connect("laura", "mala", "coordinador", "centro"))
    mostrar("Actividad de laura", length(ServidorUsuarios.listar_actividad("laura")))
    mostrar("Zona repetida", ServidorZonas.registrar_zona("Z01", "Otra", "alto", 10) |> elem(0))

    {:ok, nueva} = ServidorNecesidades.registrar("agua", 10, "alta", "centro", "Nueva necesidad", "juan")
    mostrar("ID de la nueva necesidad", nueva.id)

    detener()
  end

  defp iniciar do
    Enum.each(@servidores, fn servidor -> {:ok, _pid} = servidor.start_link() end)
  end

  defp detener, do: Enum.each(@servidores, &GenServer.stop/1)

  defp cargar_datos do
    ServidorUsuarios.connect("laura", "1234", "coordinador", "centro")

    ServidorZonas.registrar_zona("Z01", "Centro", "critico", 5000)
    ServidorZonas.registrar_sector("Z01", "Sector 1", "alto", 1200)
    ServidorZonas.registrar_punto("Z01", "Sector 1", "Punto A", 150)

    ServidorRecursos.registrar("R001", "agua", 50, "litros", "centro_acopio_1")

    ServidorNecesidades.registrar("agua", 30, "critica", "centro", "Punto de atención | sector 3, línea 2", "laura")
    ServidorNecesidades.registrar("alimentos", 5, "baja", "norte", "Familias del barrio", "ana")
    ServidorNecesidades.asignar("N001", "R001")

    ServidorPersonas.registrar("1001", "Andrés Gómez", 34, "norte", "en_albergue")
    ServidorPersonas.cambiar_estado("1001", "localizada")
    ServidorPersonas.enviar_mensaje("laura", "1001", "Estoy bien | estoy en el albergue norte")

    ServidorMascotas.reportar("lost", "perro", "Luna", "collar rojo", "negra", "mediana", "zona_norte", "3001111111")
    ServidorMascotas.reportar("found", "perro", "", "collar rojo", "negra", "mediana", "zona_norte", "3003333333")
    ServidorMascotas.buscar_coincidencias()
    ServidorMascotas.confirmar_coincidencia("MA001", "MA002")

    ServidorAlbergues.registrar("A01", "Albergue Norte", "zona_norte", 150, 120)
    ServidorAlbergues.ingreso("A01", "1001")
    ServidorAlbergues.asociar_recurso("A01", "R001")
    ServidorAlbergues.asociar_necesidad("A01", "N001")
  end

  defp verificar do
    mostrar("Actividad de laura", length(ServidorUsuarios.listar_actividad("laura")))

    {:ok, e} = ServidorZonas.estadisticas("Z01")
    mostrar("Zona Z01", {e.estimadas, e.en_sectores, e.puntos, e.atendidas})

    {:ok, recurso} = ServidorRecursos.consultar("R001")
    mostrar("Agua R001 (cantidad, movimientos)", {recurso.cantidad, length(recurso.historial)})

    {:ok, necesidad} = ServidorNecesidades.consultar("N001")
    mostrar("Necesidad N001", {necesidad.estado, necesidad.recurso})
    mostrar("Descripción N001", necesidad.descripcion)

    {:ok, persona} = ServidorPersonas.consultar("1001")
    mostrar("Persona 1001 (estado, cambios)", {persona.estado, length(persona.historial)})

    mostrar(
      "Mensajes de 1001",
      Enum.map(ServidorPersonas.listar_mensajes("1001"), fn mensaje -> mensaje.contenido end)
    )

    mostrar("Mascotas resueltas", length(ServidorMascotas.buscar(estado: :resuelta)))
    mostrar("Coincidencias confirmadas", length(ServidorMascotas.listar_coincidencias()))

    {:ok, albergue} = ServidorAlbergues.consultar("A01")

    mostrar(
      "Albergue A01 (ocupación, recursos, necesidades)",
      {Albergue.ocupacion(albergue), MapSet.to_list(albergue.recursos), MapSet.to_list(albergue.necesidades)}
    )
  end

  defp mostrar(etiqueta, valor), do: Util2.mostrar("  #{etiqueta}: #{inspect(valor)}", :mensaje)
end

PruebaPersistencia.main()
