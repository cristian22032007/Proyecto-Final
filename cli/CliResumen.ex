defmodule CliResumen do
  @moduledoc "Comando summary: resumen global de la emergencia."

  def ejecutar("summary", [], _usuario) do
    zonas = ServidorZonas.listar()
    recursos = ServidorRecursos.listar()
    pendientes = ServidorNecesidades.pendientes()
    personas = ServidorPersonas.buscar()
    mensajes = Enum.flat_map(personas, fn p -> ServidorPersonas.listar_mensajes(p.documento) end)
    mascotas = ServidorMascotas.buscar()
    albergues = ServidorAlbergues.listar()

    ocupacion = albergues |> Enum.map(&Albergue.ocupacion/1) |> Enum.sum()
    capacidad = albergues |> Enum.map(& &1.capacidad) |> Enum.sum()

    texto = """
    === RESUMEN GLOBAL ===
    Zonas registradas: #{length(zonas)}
    Recursos restantes: #{resumir_recursos(recursos)}
    Necesidades pendientes: #{length(pendientes)}
    Personas localizadas: #{Enum.count(personas, &(&1.estado == :localizada))}
    Personas por estado: #{resumir(Enum.frequencies_by(personas, & &1.estado))}
    Mensajes: #{length(mensajes)} (pendientes: #{Enum.count(mensajes, &(&1.estado == :pendiente))})
    Mascotas por estado: #{resumir(Enum.frequencies_by(mascotas, & &1.estado))}
    Albergues: #{length(albergues)} (ocupación #{ocupacion}/#{capacidad})
    """

    {:ok, String.trim_trailing(texto)}
  end

  def ejecutar(_comando, _argumentos, _usuario), do: {:error, :uso}

  defp resumir(mapa) when map_size(mapa) == 0, do: "ninguno"

  defp resumir(mapa) do
    mapa
    |> Enum.sort()
    |> Enum.map_join(", ", fn {clave, valor} -> "#{clave}: #{valor}" end)
  end

  defp resumir_recursos(recursos) do
    recursos
    |> Enum.reduce(%{}, fn recurso, acumulado ->
      Map.update(acumulado, "#{recurso.nombre} (#{recurso.unidad})", recurso.cantidad, &(&1 + recurso.cantidad))
    end)
    |> resumir()
  end
end
