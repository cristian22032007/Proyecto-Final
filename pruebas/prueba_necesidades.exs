defmodule PruebaNecesidades do
  def main do
    Almacen.usar_directorio_temporal()
    {:ok, _} = ServidorRecursos.start_link()
    {:ok, _} = ServidorNecesidades.start_link()

    ServidorRecursos.registrar("R001", "agua", 50, "litros", "centro_acopio_1")
    ServidorRecursos.registrar("R002", "alimentos", 10, "kg", "centro_acopio_1")

    Util2.mostrar("=== REGISTRO ===", :mensaje)

    ServidorNecesidades.registrar(
      "agua",
      30,
      "critica",
      "centro",
      "Punto de atención sector 3",
      "laura"
    )
    |> mostrar_resultado()

    ServidorNecesidades.registrar("agua", 25, "alta", "centro", "Albergue del centro", "juan")
    |> mostrar_resultado()

    ServidorNecesidades.registrar(
      "alimentos",
      10,
      "baja",
      "norte",
      "Familias del barrio norte",
      "ana"
    )
    |> mostrar_resultado()

    ServidorNecesidades.registrar(
      "medicamentos",
      5,
      "critica",
      "norte",
      "Insulina para el albergue",
      "ana"
    )
    |> mostrar_resultado()

    ServidorNecesidades.registrar("gasolina", 10, "alta", "centro", "Tipo inválido", "ana")
    |> mostrar_resultado()

    ServidorNecesidades.registrar("agua", 0, "alta", "centro", "Cantidad inválida", "ana")
    |> mostrar_resultado()

    ServidorNecesidades.registrar("agua", 10, "urgente", "centro", "Prioridad inválida", "ana")
    |> mostrar_resultado()

    Util2.mostrar("\n=== CONFLICTO: N001 (30) y N002 (25) sobre R001 (50) ===", :mensaje)

    resultados =
      ["N001", "N002"]
      |> Enum.map(fn id ->
        Task.async(fn -> {id, ServidorNecesidades.asignar(id, "R001")} end)
      end)
      |> Enum.map(&Task.await/1)

    Enum.each(resultados, fn {id, resultado} ->
      Util2.mostrar("Asignar #{id}:", :mensaje)
      mostrar_resultado(resultado)
    end)

    {:ok, r001} = ServidorRecursos.consultar("R001")
    Util2.mostrar("Agua restante: #{r001.cantidad} litros", :mensaje)

    Util2.mostrar("\n=== PENDIENTES (ordenadas por prioridad) ===", :mensaje)

    ServidorNecesidades.pendientes()
    |> Util2.convertir_coleccion_mensaje()
    |> Util2.mostrar(:mensaje)

    Util2.mostrar("=== FILTRO: zona centro, prioridad crítica ===", :mensaje)

    ServidorNecesidades.listar(zona: "centro", prioridad: :critica)
    |> Util2.convertir_coleccion_mensaje()
    |> Util2.mostrar(:mensaje)

    {ganadora, _} = Enum.find(resultados, fn {_id, r} -> match?({:ok, _}, r) end)

    Util2.mostrar("=== CICLO DE ESTADOS de #{ganadora} ===", :mensaje)
    ServidorNecesidades.cambiar_estado(ganadora, :atendida) |> mostrar_resultado()
    ServidorNecesidades.cambiar_estado(ganadora, :en_atencion) |> mostrar_resultado()
    ServidorNecesidades.cambiar_estado(ganadora, :atendida) |> mostrar_resultado()
    ServidorNecesidades.cambiar_estado(ganadora, :atendida) |> mostrar_resultado()
    ServidorNecesidades.asignar(ganadora, "R001") |> mostrar_resultado()
    ServidorNecesidades.cambiar_estado(ganadora, :cancelada) |> mostrar_resultado()

    Util2.mostrar("\n=== TIPO DE RECURSO Y CANCELACIÓN ===", :mensaje)
    ServidorNecesidades.asignar("N004", "R001") |> mostrar_resultado()
    ServidorNecesidades.asignar("N003", "R002") |> mostrar_resultado()
    {:ok, r002} = ServidorRecursos.consultar("R002")
    Util2.mostrar("Alimentos tras asignar N003: #{r002.cantidad} kg", :mensaje)

    ServidorNecesidades.cambiar_estado("N003", :cancelada) |> mostrar_resultado()
    {:ok, r002} = ServidorRecursos.consultar("R002")
    Util2.mostrar("Alimentos tras cancelar N003: #{r002.cantidad} kg", :mensaje)

    ServidorNecesidades.consultar("N999") |> mostrar_resultado()
  end

  defp mostrar_resultado({:ok, necesidad}), do: Util2.mostrar("  OK: #{necesidad}", :mensaje)
  defp mostrar_resultado({:error, razon}), do: Util2.mostrar("  ERROR: #{razon}", :mensaje)
end

PruebaNecesidades.main()
