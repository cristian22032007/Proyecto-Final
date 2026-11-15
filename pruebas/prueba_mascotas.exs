defmodule PruebaMascotas do
  def main do
    Almacen.usar_directorio_temporal()
    {:ok, _} = ServidorMascotas.start_link()

    Util2.mostrar("=== REGISTRO ===", :mensaje)

    ServidorMascotas.reportar(
      "lost",
      "perro",
      "Luna",
      "collar rojo y mancha blanca en el pecho",
      "negra",
      "mediana",
      "zona_norte",
      "3001111111"
    )
    |> mostrar_resultado()

    ServidorMascotas.reportar(
      "lost",
      "gato",
      "Michi",
      "pelo largo",
      "blanca",
      "pequeña",
      "zona_sur",
      "3002222222"
    )
    |> mostrar_resultado()

    ServidorMascotas.reportar(
      "found",
      "perro",
      "",
      "collar rojo, mancha blanca",
      "negra",
      "mediana",
      "zona_norte",
      "3003333333"
    )
    |> mostrar_resultado()

    ServidorMascotas.reportar(
      "found",
      "perro",
      "",
      "",
      "cafe",
      "grande",
      "zona_centro",
      "3004444444"
    )
    |> mostrar_resultado()

    ServidorMascotas.reportar(
      "found",
      "gato",
      "",
      "pelo largo",
      "blanca",
      "pequeña",
      "zona_sur",
      "3005555555"
    )
    |> mostrar_resultado()

    ServidorMascotas.reportar(
      "found",
      "perro",
      "Luna",
      "",
      "negra",
      "grande",
      "zona_norte",
      "3006666666"
    )
    |> mostrar_resultado()

    ServidorMascotas.reportar(
      "extraviada",
      "perro",
      "",
      "",
      "negra",
      "mediana",
      "zona_norte",
      "300"
    )
    |> mostrar_resultado()

    ServidorMascotas.reportar("lost", "  ", "", "", "negra", "mediana", "zona_norte", "300")
    |> mostrar_resultado()

    ServidorMascotas.reportar("lost", "perro", "", "", "negra", "enorme", "zona_norte", "300")
    |> mostrar_resultado()

    ServidorMascotas.reportar("lost", "perro", "", "", "negra", "mediana", "zona_norte", "")
    |> mostrar_resultado()

    Util2.mostrar("\n=== POSIBLES COINCIDENCIAS (umbral #{Mascota.umbral()}) ===", :mensaje)
    mostrar_coincidencias(ServidorMascotas.buscar_coincidencias())

    Util2.mostrar("\nEstado tras calcular coincidencias:", :mensaje)
    mostrar_lista(ServidorMascotas.buscar())

    Util2.mostrar("=== CONFIRMACIONES INVÁLIDAS ===", :mensaje)
    ServidorMascotas.confirmar_coincidencia("MA003", "MA001") |> mostrar_resultado()
    ServidorMascotas.confirmar_coincidencia("MA002", "MA003") |> mostrar_resultado()
    ServidorMascotas.confirmar_coincidencia("MA002", "MA999") |> mostrar_resultado()

    Util2.mostrar(
      "\n=== CONFLICTO: MA001 se intenta cerrar con MA003 y con MA006 a la vez ===",
      :mensaje
    )

    resultados =
      ["MA003", "MA006"]
      |> Enum.map(fn id ->
        Task.async(fn -> {id, ServidorMascotas.confirmar_coincidencia("MA001", id)} end)
      end)
      |> Enum.map(&Task.await/1)

    Enum.each(resultados, fn {id, resultado} ->
      Util2.mostrar("MA001 con #{id}:", :mensaje)
      mostrar_resultado(resultado)
    end)

    Util2.mostrar("\n=== CONFIRMAR MA002 CON MA005 Y REPETIR ===", :mensaje)
    ServidorMascotas.confirmar_coincidencia("MA002", "MA005") |> mostrar_resultado()
    ServidorMascotas.confirmar_coincidencia("MA002", "MA005") |> mostrar_resultado()

    Util2.mostrar("\n=== CONSULTAS ===", :mensaje)
    Util2.mostrar("Especie perro:", :mensaje)
    mostrar_lista(ServidorMascotas.buscar(especie: "perro"))
    Util2.mostrar("Zona zona_norte:", :mensaje)
    mostrar_lista(ServidorMascotas.buscar(zona: "zona_norte"))
    Util2.mostrar("Estado resuelta:", :mensaje)
    mostrar_lista(ServidorMascotas.buscar(estado: :resuelta))
    Util2.mostrar("Tipo encontrada:", :mensaje)
    mostrar_lista(ServidorMascotas.buscar(tipo: :encontrada))

    Util2.mostrar("=== COINCIDENCIAS DESPUÉS DE CERRAR LAS PERDIDAS ===", :mensaje)
    mostrar_coincidencias(ServidorMascotas.buscar_coincidencias())

    Util2.mostrar("\n=== COINCIDENCIAS CONFIRMADAS ===", :mensaje)

    ServidorMascotas.listar_coincidencias()
    |> Util2.convertir_coleccion_mensaje(fn {fecha, id_p, id_e, puntaje} ->
      " - #{fecha}: #{id_p} <-> #{id_e} (#{puntaje} puntos)\n"
    end)
    |> Util2.mostrar(:mensaje)
  end

  defp mostrar_lista(lista) do
    lista
    |> Util2.convertir_coleccion_mensaje()
    |> Util2.mostrar(:mensaje)
  end

  defp mostrar_coincidencias([]), do: Util2.mostrar("  Sin coincidencias", :mensaje)

  defp mostrar_coincidencias(lista) do
    lista
    |> Util2.convertir_coleccion_mensaje(fn {perdida, encontrada, puntaje} ->
      " - #{perdida.id} (#{perdida.nombre}) <-> #{encontrada.id}: #{puntaje} puntos\n"
    end)
    |> Util2.mostrar(:mensaje)
  end

  defp mostrar_resultado({:ok, {perdida, encontrada, puntaje}}) do
    Util2.mostrar(
      "  OK: #{perdida.id} y #{encontrada.id} resueltas (#{puntaje} puntos)",
      :mensaje
    )
  end

  defp mostrar_resultado({:ok, valor}), do: Util2.mostrar("  OK: #{valor}", :mensaje)
  defp mostrar_resultado({:error, razon}), do: Util2.mostrar("  ERROR: #{razon}", :mensaje)
end

PruebaMascotas.main()
