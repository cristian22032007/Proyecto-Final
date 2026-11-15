defmodule PruebaPersonas do
  def main do
    Almacen.usar_directorio_temporal()
    {:ok, _} = ServidorPersonas.start_link()

    Util2.mostrar("=== REGISTRO ===", :mensaje)

    ServidorPersonas.registrar("1001", "Andrés Gómez", 34, "norte", "en_albergue")
    |> mostrar_resultado()

    ServidorPersonas.registrar("1002", "María López", 28, "centro") |> mostrar_resultado()

    ServidorPersonas.registrar("1003", "Luis Pérez", 8, "sur", "sin_informacion")
    |> mostrar_resultado()

    ServidorPersonas.registrar("1001", "Otro Nombre", 20, "norte") |> mostrar_resultado()

    ServidorPersonas.registrar("1004", "Pedro Ruiz", 30, "norte", "perdido")
    |> mostrar_resultado()

    ServidorPersonas.registrar("1005", "Sara Díaz", -3, "norte") |> mostrar_resultado()
    ServidorPersonas.registrar("1006", "  ", 30, "norte") |> mostrar_resultado()

    Util2.mostrar("\n=== CONFLICTO: 5 registros simultáneos del mismo documento ===", :mensaje)

    resultados =
      1..5
      |> Enum.map(fn _ ->
        Task.async(fn -> ServidorPersonas.registrar("2002", "Carlos Ruiz", 40, "centro") end)
      end)
      |> Enum.map(&Task.await/1)

    exitosos = Enum.count(resultados, &match?({:ok, _}, &1))
    Util2.mostrar("Registros exitosos: #{exitosos}, rechazados: #{5 - exitosos}", :mensaje)

    Util2.mostrar("\n=== CAMBIOS DE ESTADO ===", :mensaje)
    ServidorPersonas.cambiar_estado("1001", "localizada") |> mostrar_resultado()
    ServidorPersonas.cambiar_estado("1001", "reunificada") |> mostrar_resultado()
    ServidorPersonas.cambiar_estado("1001", "localizada") |> mostrar_resultado()
    ServidorPersonas.cambiar_estado("1002", "sin_informacion") |> mostrar_resultado()
    ServidorPersonas.cambiar_estado("1002", "volando") |> mostrar_resultado()
    ServidorPersonas.cambiar_estado("9999", "localizada") |> mostrar_resultado()

    Util2.mostrar("\n=== HISTORIAL DE 1001 ===", :mensaje)
    {:ok, historial} = ServidorPersonas.historial("1001")

    historial
    |> Util2.convertir_coleccion_mensaje(fn {fecha, anterior, nuevo} ->
      " - #{fecha}: #{inspect(anterior)} -> #{nuevo}\n"
    end)
    |> Util2.mostrar(:mensaje)

    Util2.mostrar("=== MENSAJES PARA 1001 ===", :mensaje)

    ServidorPersonas.enviar_mensaje("laura", "1001", "Estoy bien, estoy en el albergue norte")
    |> mostrar_resultado()

    ServidorPersonas.enviar_mensaje("familia_gomez", "1001", "Te esperamos en casa")
    |> mostrar_resultado()

    ServidorPersonas.enviar_mensaje("laura", "9999", "Mensaje a nadie") |> mostrar_resultado()
    ServidorPersonas.enviar_mensaje("laura", "1001", "   ") |> mostrar_resultado()

    Util2.mostrar("\nMensajes de 1001:", :mensaje)
    listar_mensajes("1001")

    Util2.mostrar("\n=== MARCAR MENSAJES ===", :mensaje)
    ServidorPersonas.marcar_mensaje("M001", "entregado") |> mostrar_resultado()
    ServidorPersonas.marcar_mensaje("M001", "entregado") |> mostrar_resultado()
    ServidorPersonas.marcar_mensaje("M001", "leido") |> mostrar_resultado()
    ServidorPersonas.marcar_mensaje("M999", "entregado") |> mostrar_resultado()

    Util2.mostrar("\nMensajes de 1001:", :mensaje)
    listar_mensajes("1001")

    Util2.mostrar("\n=== BÚSQUEDAS ===", :mensaje)
    mostrar_lista("Nombre 'andr'", ServidorPersonas.buscar(nombre: "andr"))
    mostrar_lista("Zona centro", ServidorPersonas.buscar(zona: "centro"))
    mostrar_lista("Estado reunificada", ServidorPersonas.buscar(estado: :reunificada))
    mostrar_lista("Documento 1002", ServidorPersonas.buscar(documento: "1002"))

    ServidorPersonas.contar_por_estado() |> IO.inspect(label: "\nPersonas por estado")
  end

  defp listar_mensajes(documento) do
    documento
    |> ServidorPersonas.listar_mensajes()
    |> Util2.convertir_coleccion_mensaje()
    |> Util2.mostrar(:mensaje)
  end

  defp mostrar_lista(titulo, lista) do
    Util2.mostrar("#{titulo}:", :mensaje)

    lista
    |> Util2.convertir_coleccion_mensaje()
    |> Util2.mostrar(:mensaje)
  end

  defp mostrar_resultado({:ok, valor}), do: Util2.mostrar("  OK: #{valor}", :mensaje)
  defp mostrar_resultado({:error, razon}), do: Util2.mostrar("  ERROR: #{razon}", :mensaje)
end

PruebaPersonas.main()
