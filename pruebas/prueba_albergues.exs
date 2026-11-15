defmodule PruebaAlbergues do
  def main do
    Almacen.usar_directorio_temporal()
    {:ok, _} = ServidorAlbergues.start_link()

    Util2.mostrar("=== REGISTRO ===", :mensaje)

    ServidorAlbergues.registrar("A01", "Albergue Norte", "zona_norte", 150, 120)
    |> mostrar_resultado()

    ServidorAlbergues.registrar("A02", "Albergue Centro", "zona_centro", 5) |> mostrar_resultado()
    ServidorAlbergues.registrar("A03", "Albergue Sur", "zona_sur", 40, 10) |> mostrar_resultado()
    ServidorAlbergues.registrar("A01", "Repetido", "zona_norte", 50) |> mostrar_resultado()

    ServidorAlbergues.registrar("A04", "Capacidad negativa", "zona_norte", -10)
    |> mostrar_resultado()

    ServidorAlbergues.registrar("A05", "Capacidad cero", "zona_norte", 0) |> mostrar_resultado()

    ServidorAlbergues.registrar("A06", "Ocupación excesiva", "zona_norte", 150, 200)
    |> mostrar_resultado()

    ServidorAlbergues.registrar("A07", "  ", "zona_norte", 50) |> mostrar_resultado()

    Util2.mostrar("\n=== INGRESOS Y SALIDAS ===", :mensaje)
    ServidorAlbergues.ingreso("A01", "1001") |> mostrar_resultado()
    ServidorAlbergues.ingreso("A01", "1001") |> mostrar_resultado()
    ServidorAlbergues.salida("A01", "1001") |> mostrar_resultado()
    ServidorAlbergues.salida("A01", "1001") |> mostrar_resultado()
    ServidorAlbergues.salida("A01", "9999") |> mostrar_resultado()
    ServidorAlbergues.ingreso("A99", "1001") |> mostrar_resultado()
    ServidorAlbergues.ingreso("A01", "  ") |> mostrar_resultado()

    Util2.mostrar(
      "\n=== CONFLICTO: 20 personas intentan entrar a A02 (capacidad 5) ===",
      :mensaje
    )

    resultados =
      1..20
      |> Enum.map(fn i ->
        documento = "D" <> String.pad_leading(Integer.to_string(i), 2, "0")
        Task.async(fn -> {documento, ServidorAlbergues.ingreso("A02", documento)} end)
      end)
      |> Enum.map(&Task.await/1)

    admitidos = Enum.filter(resultados, fn {_documento, r} -> match?({:ok, _}, r) end)

    Util2.mostrar(
      "Admitidos: #{length(admitidos)}, rechazados: #{20 - length(admitidos)}",
      :mensaje
    )

    {:ok, a02} = ServidorAlbergues.consultar("A02")
    Util2.mostrar("Ocupación A02: #{Albergue.ocupacion(a02)}/#{a02.capacidad}", :mensaje)
    ServidorAlbergues.cupos("A02") |> IO.inspect(label: "Cupos A02")
    ServidorAlbergues.ingreso("A02", "D99") |> mostrar_resultado()

    [{primer_admitido, _} | _] = admitidos
    Util2.mostrar("\nSale #{primer_admitido} y queda un cupo:", :mensaje)
    ServidorAlbergues.salida("A02", primer_admitido) |> mostrar_resultado()
    ServidorAlbergues.cupos("A02") |> IO.inspect(label: "Cupos A02")
    ServidorAlbergues.ingreso("A02", "D99") |> mostrar_resultado()
    ServidorAlbergues.ingreso("A02", "D98") |> mostrar_resultado()

    Util2.mostrar("\n=== CONFLICTO: la misma persona entra 5 veces a la vez a A03 ===", :mensaje)

    repetidos =
      1..5
      |> Enum.map(fn _ -> Task.async(fn -> ServidorAlbergues.ingreso("A03", "X1") end) end)
      |> Enum.map(&Task.await/1)

    exitosos = Enum.count(repetidos, &match?({:ok, _}, &1))
    Util2.mostrar("Ingresos exitosos: #{exitosos}, rechazados: #{5 - exitosos}", :mensaje)

    Util2.mostrar("\n=== RECURSOS Y NECESIDADES ASOCIADOS A A01 ===", :mensaje)
    ServidorAlbergues.asociar_recurso("A01", "R001") |> mostrar_resultado()
    ServidorAlbergues.asociar_recurso("A01", "R001") |> mostrar_resultado()
    ServidorAlbergues.asociar_necesidad("A01", "N001") |> mostrar_resultado()
    ServidorAlbergues.asociar_necesidad("A99", "N001") |> mostrar_resultado()

    Util2.mostrar("\n=== CHECK SHELTER A01 ===", :mensaje)
    {:ok, a01} = ServidorAlbergues.consultar("A01")
    a01 |> Albergue.generar_resumen() |> Util2.mostrar(:mensaje)

    Util2.mostrar("=== REPORTE: ALBERGUES CON MAYOR OCUPACIÓN (top 2) ===", :mensaje)

    ServidorAlbergues.reporte_ocupacion(2)
    |> Util2.convertir_coleccion_mensaje()
    |> Util2.mostrar(:mensaje)

    Util2.mostrar("=== TODOS LOS ALBERGUES ===", :mensaje)

    ServidorAlbergues.listar()
    |> Util2.convertir_coleccion_mensaje()
    |> Util2.mostrar(:mensaje)
  end

  defp mostrar_resultado({:ok, valor}), do: Util2.mostrar("  OK: #{valor}", :mensaje)
  defp mostrar_resultado({:error, razon}), do: Util2.mostrar("  ERROR: #{razon}", :mensaje)
end

PruebaAlbergues.main()
