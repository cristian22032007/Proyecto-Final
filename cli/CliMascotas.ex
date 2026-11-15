defmodule CliMascotas do
  @moduledoc "Comandos del CLI sobre mascotas perdidas y encontradas."

  def ejecutar("report_pet", [tipo, especie, nombre, color, tamano, zona, contacto | resto], _usuario)
      when length(resto) <= 1 do
    caracteristicas = Enum.at(resto, 0, "")

    with {:ok, _zona} <- ServidorZonas.consultar(zona),
         {:ok, mascota} <-
           ServidorMascotas.reportar(tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto) do
      {:ok, "Reporte registrado: #{mascota}"}
    end
  end

  def ejecutar("match_pets", [], _usuario) do
    {:ok, texto_coincidencias(ServidorMascotas.buscar_coincidencias())}
  end

  def ejecutar("confirm_match", [id_perdida, id_encontrada], _usuario) do
    with {:ok, {perdida, encontrada, puntaje}} <-
           ServidorMascotas.confirmar_coincidencia(id_perdida, id_encontrada) do
      {:ok, "Coincidencia confirmada: #{perdida.id} y #{encontrada.id} resueltas (#{puntaje} puntos)"}
    end
  end

  def ejecutar("list_pets", filtros, _usuario) do
    with {:ok, lista_filtros} <- CliAnalisis.leer_filtros(filtros, &filtro/2) do
      lista = ServidorMascotas.buscar(lista_filtros)
      {:ok, CliAnalisis.lista_texto(lista, "No hay reportes con esos filtros")}
    end
  end

  def ejecutar(_comando, _argumentos, _usuario), do: {:error, :uso}

  defp texto_coincidencias([]), do: "No hay posibles coincidencias"

  defp texto_coincidencias(lista) do
    detalle =
      lista
      |> Util2.convertir_coleccion_mensaje(fn {perdida, encontrada, puntaje} ->
        " - #{perdida.id} (#{perdida.nombre}) <-> #{encontrada.id}: #{puntaje} puntos\n"
      end)
      |> Enum.join()
      |> String.trim_trailing()

    "Posibles coincidencias (umbral #{Mascota.umbral()}):\n" <> detalle
  end

  defp filtro("especie", valor), do: {:ok, {:especie, valor}}
  defp filtro("zona", valor), do: {:ok, {:zona, valor}}
  defp filtro("estado", valor), do: CliAnalisis.con_atomo(:estado, Mascota.convertir_estado(valor))
  defp filtro("tipo", valor), do: CliAnalisis.con_atomo(:tipo, Mascota.convertir_tipo(valor))
  defp filtro(clave, _valor), do: {:error, "Filtro desconocido: #{clave}"}
end
