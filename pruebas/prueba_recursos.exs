defmodule PruebaRecursos do
  def main do
    Almacen.usar_directorio_temporal()
    {:ok, _pid} = ServidorRecursos.start_link()

    ServidorRecursos.registrar("R001", "agua", 50, "litros", "centro_acopio_1")
    |> elem(0)
    |> IO.inspect()

    ServidorRecursos.registrar("R001", "agua", 10, "litros", "otro") |> IO.inspect()
    ServidorRecursos.registrar("R002", "agua", -5, "litros", "otro") |> IO.inspect()

    Util2.mostrar("\n=== CONFLICTO CONCURRENTE: 30 y 25 litros sobre 50 ===", :mensaje)

    tareas = [
      Task.async(fn ->
        {"solicitud A (30)", ServidorRecursos.salida("R001", 30, "necesidad N001")}
      end),
      Task.async(fn ->
        {"solicitud B (25)", ServidorRecursos.salida("R001", 25, "necesidad N002")}
      end)
    ]

    tareas
    |> Enum.map(&Task.await/1)
    |> Enum.each(fn {nombre, resultado} ->
      case resultado do
        {:ok, r} -> Util2.mostrar("#{nombre}: CONFIRMADA, quedan #{r.cantidad}", :mensaje)
        {:error, razon} -> Util2.mostrar("#{nombre}: RECHAZADA, #{razon}", :mensaje)
      end
    end)

    {:ok, final} = ServidorRecursos.consultar("R001")
    Util2.mostrar("Inventario final: #{final.cantidad} litros (nunca negativo)\n", :mensaje)

    Util2.mostrar("=== MUCHAS SOLICITUDES A LA VEZ: 100 de 1 litro sobre 20 ===", :mensaje)
    ServidorRecursos.registrar("R003", "alimentos", 20, "kg", "centro_acopio_1")

    resultados =
      1..100
      |> Enum.map(fn _ -> Task.async(fn -> ServidorRecursos.salida("R003", 1) end) end)
      |> Enum.map(&Task.await/1)

    confirmadas = Enum.count(resultados, &match?({:ok, _}, &1))
    Util2.mostrar("Confirmadas: #{confirmadas}, rechazadas: #{100 - confirmadas}", :mensaje)

    Util2.mostrar("\n=== TRANSFERENCIA ===", :mensaje)
    ServidorRecursos.entrada("R001", 100, "donación") |> elem(0) |> IO.inspect()
    ServidorRecursos.transferir("R001", "albergue_2", 30) |> IO.inspect()
    ServidorRecursos.transferir("R001", "albergue_2", 5000) |> IO.inspect()
    ServidorRecursos.transferir("R001", "centro_acopio_1", 5) |> IO.inspect()

    ServidorRecursos.disponibilidad("agua") |> IO.inspect(label: "Agua total")

    ServidorRecursos.disponibilidad("agua", "albergue_2")
    |> IO.inspect(label: "Agua en albergue_2")
  end
end

PruebaRecursos.main()
