defmodule CliNecesidades do
  @moduledoc "Comandos del CLI sobre necesidades puntuales."

  def ejecutar("register_need", [tipo, cantidad, prioridad, zona | descripcion], usuario) do
    with {:ok, cantidad_entera} <- CliAnalisis.entero(cantidad, "cantidad"),
         {:ok, _zona} <- ServidorZonas.consultar(zona),
         {:ok, necesidad} <-
           ServidorNecesidades.registrar(
             tipo,
             cantidad_entera,
             prioridad,
             zona,
             Enum.join(descripcion, " "),
             usuario.usuario
           ) do
      {:ok, "Necesidad registrada: #{necesidad}"}
    end
  end

  def ejecutar("list_needs", filtros, _usuario) do
    with {:ok, lista_filtros} <- CliAnalisis.leer_filtros(filtros, &filtro/2) do
      lista = ServidorNecesidades.listar(lista_filtros)
      {:ok, CliAnalisis.lista_texto(lista, "No hay necesidades con esos filtros")}
    end
  end

  def ejecutar("pending_needs", [], _usuario) do
    lista = ServidorNecesidades.pendientes()
    {:ok, CliAnalisis.lista_texto(lista, "No hay necesidades pendientes")}
  end

  def ejecutar("assign_resource", [id, codigo_recurso], _usuario) do
    with {:ok, necesidad} <- ServidorNecesidades.asignar(id, codigo_recurso) do
      {:ok, "#{necesidad.id} asignada al recurso #{codigo_recurso}: se descontaron #{necesidad.cantidad}"}
    end
  end

  def ejecutar("change_need_status", [id, estado], _usuario) do
    with {:ok, estado_atomo} <- Necesidad.convertir_estado(estado),
         {:ok, necesidad} <- ServidorNecesidades.cambiar_estado(id, estado_atomo) do
      {:ok, "Necesidad actualizada: #{necesidad}"}
    end
  end

  def ejecutar(_comando, _argumentos, _usuario), do: {:error, :uso}

  defp filtro("zona", valor), do: {:ok, {:zona, valor}}
  defp filtro("tipo", valor), do: CliAnalisis.con_atomo(:tipo, Necesidad.convertir_tipo(valor))
  defp filtro("prioridad", valor), do: CliAnalisis.con_atomo(:prioridad, Necesidad.convertir_prioridad(valor))
  defp filtro("estado", valor), do: CliAnalisis.con_atomo(:estado, Necesidad.convertir_estado(valor))
  defp filtro(clave, _valor), do: {:error, "Filtro desconocido: #{clave}"}
end
