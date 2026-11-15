defmodule PruebaZonas do
  def main do
    Almacen.usar_directorio_temporal()
    {:ok, _pid} = ServidorZonas.start_link()

    ServidorZonas.registrar_zona("Z01", "Centro", "critico", 5000) |> elem(0) |> IO.inspect()
    ServidorZonas.registrar_zona("Z01", "Otra", "alto", 10) |> IO.inspect()
    ServidorZonas.registrar_zona("Z02", "Norte", "extremo", 10) |> IO.inspect()
    ServidorZonas.registrar_zona("Z03", "Sur", "medio", -5) |> IO.inspect()

    ServidorZonas.registrar_sector("Z01", "Sector 1", "alto", 1200) |> elem(0) |> IO.inspect()
    ServidorZonas.registrar_sector("Z01", "Sector 2", "medio", 800) |> elem(0) |> IO.inspect()
    ServidorZonas.registrar_sector("Z01", "Sector 1", "bajo", 10) |> IO.inspect()
    ServidorZonas.registrar_sector("Z99", "Sector 1", "bajo", 10) |> IO.inspect()

    ServidorZonas.registrar_punto("Z01", "Sector 1", "Punto A", 150) |> elem(0) |> IO.inspect()
    ServidorZonas.registrar_punto("Z01", "Sector 2", "Punto B", 90) |> elem(0) |> IO.inspect()
    ServidorZonas.registrar_punto("Z01", "Sector 2", "Punto B", 10) |> IO.inspect()
    ServidorZonas.registrar_punto("Z01", "Sector 7", "Punto C", 10) |> IO.inspect()

    {:ok, zona} = ServidorZonas.consultar("Z01")
    zona |> Zona.generar_resumen() |> Util2.mostrar(:mensaje)

    ServidorZonas.estadisticas("Z01") |> IO.inspect()
  end
end

PruebaZonas.main()
