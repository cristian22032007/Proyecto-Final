defmodule CliRecursos do
  @moduledoc "Comandos del CLI sobre recursos e inventario."

  def ejecutar("register_resource", [codigo, nombre, cantidad, unidad, ubicacion], _usuario) do
    with {:ok, cantidad_entera} <- CliAnalisis.entero(cantidad, "cantidad"),
         {:ok, recurso} <-
           ServidorRecursos.registrar(codigo, String.downcase(nombre), cantidad_entera, unidad, ubicacion) do
      {:ok, "Recurso registrado: #{texto_recurso(recurso)}"}
    end
  end

  def ejecutar("list_resources", [], _usuario) do
    lista =
      ServidorRecursos.listar()
      |> Util2.ordenar(:asc, & &1.codigo)
      |> Enum.map(&texto_recurso/1)

    {:ok, CliAnalisis.lista_texto(lista, "No hay recursos registrados")}
  end

  def ejecutar("availability", [nombre | resto], _usuario) when length(resto) <= 1 do
    ubicacion = Enum.at(resto, 0, :todas)
    total = ServidorRecursos.disponibilidad(String.downcase(nombre), ubicacion)
    donde = if ubicacion == :todas, do: "en total", else: "en #{ubicacion}"
    {:ok, "Disponibilidad de #{nombre} #{donde}: #{total}"}
  end

  def ejecutar("transfer_resource", [codigo, origen, destino, cantidad], _usuario) do
    with {:ok, cantidad_entera} <- CliAnalisis.entero(cantidad, "cantidad"),
         {:ok, recurso} <- ServidorRecursos.consultar(codigo),
         :ok <-
           CliAnalisis.verificar(
             recurso.ubicacion == origen,
             "El recurso #{codigo} no está en #{origen} (está en #{recurso.ubicacion})"
           ),
         {:ok, _} <- ServidorRecursos.transferir(codigo, destino, cantidad_entera) do
      {:ok, "Transferidos #{cantidad_entera} #{recurso.unidad} de #{recurso.nombre}: #{origen} -> #{destino}"}
    end
  end

  # Recursos críticos: tipos donde la demanda pendiente supera el inventario total
  def ejecutar("critical_resources", [], _usuario) do
    deficits =
      ServidorNecesidades.pendientes()
      |> Enum.reject(&(&1.tipo == :otra))
      |> Enum.reduce(%{}, fn necesidad, acumulado ->
        Map.update(acumulado, Atom.to_string(necesidad.tipo), necesidad.cantidad, &(&1 + necesidad.cantidad))
      end)
      |> Enum.map(fn {tipo, demanda} -> {tipo, demanda, ServidorRecursos.disponibilidad(tipo)} end)
      |> Enum.filter(fn {_tipo, demanda, disponible} -> demanda > disponible end)
      |> Util2.ordenar(:desc, fn {_tipo, demanda, disponible} -> demanda - disponible end)

    {:ok, texto_criticos(deficits)}
  end

  def ejecutar(_comando, _argumentos, _usuario), do: {:error, :uso}

  defp texto_criticos([]),
    do: "No hay recursos críticos: el inventario cubre las necesidades pendientes"

  defp texto_criticos(deficits) do
    detalle =
      deficits
      |> Util2.convertir_coleccion_mensaje(fn {tipo, demanda, disponible} ->
        " - #{tipo}: demanda #{demanda}, disponible #{disponible}, faltan #{demanda - disponible}\n"
      end)
      |> Enum.join()
      |> String.trim_trailing()

    "Recursos críticos (la demanda pendiente supera el inventario):\n" <> detalle
  end

  defp texto_recurso(%Recurso{} = r),
    do: "#{r.codigo} | #{r.nombre} | #{r.cantidad} #{r.unidad} | #{r.ubicacion}"
end
