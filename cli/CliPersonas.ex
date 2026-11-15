defmodule CliPersonas do
  @moduledoc "Comandos del CLI sobre personas afectadas y mensajes entre familiares."

  def ejecutar("report_person", [documento, nombre, edad, zona | resto], _usuario)
      when length(resto) <= 1 do
    estado = Enum.at(resto, 0, "reportada")

    with {:ok, edad_entera} <- CliAnalisis.entero(edad, "edad"),
         {:ok, _zona} <- ServidorZonas.consultar(zona),
         {:ok, persona} <- ServidorPersonas.registrar(documento, nombre, edad_entera, zona, estado) do
      {:ok, "Persona registrada: #{persona}"}
    end
  end

  # Con "=" se busca por filtros; sin "=" es un documento
  def ejecutar("find_person", [argumento | _] = argumentos, _usuario) do
    if String.contains?(argumento, "=") do
      with {:ok, filtros} <- CliAnalisis.leer_filtros(argumentos, &filtro/2) do
        {:ok, CliAnalisis.lista_texto(ServidorPersonas.buscar(filtros), "No se encontraron personas")}
      end
    else
      with {:ok, persona} <- ServidorPersonas.consultar(argumento) do
        {:ok, "#{persona}"}
      end
    end
  end

  def ejecutar("send_family_message", [documento | contenido], usuario) do
    with {:ok, mensaje} <-
           ServidorPersonas.enviar_mensaje(usuario.usuario, documento, Enum.join(contenido, " ")) do
      {:ok, "Mensaje registrado: #{mensaje}"}
    end
  end

  def ejecutar("list_family_messages", [documento], _usuario) do
    with {:ok, _persona} <- ServidorPersonas.consultar(documento) do
      lista = ServidorPersonas.listar_mensajes(documento)
      {:ok, CliAnalisis.lista_texto(lista, "No hay mensajes para #{documento}")}
    end
  end

  def ejecutar("mark_message", [id, estado], _usuario) do
    with {:ok, mensaje} <- ServidorPersonas.marcar_mensaje(id, estado) do
      {:ok, "Mensaje actualizado: #{mensaje}"}
    end
  end

  def ejecutar(_comando, _argumentos, _usuario), do: {:error, :uso}

  defp filtro("nombre", valor), do: {:ok, {:nombre, valor}}
  defp filtro("documento", valor), do: {:ok, {:documento, valor}}
  defp filtro("zona", valor), do: {:ok, {:zona, valor}}
  defp filtro("estado", valor), do: CliAnalisis.con_atomo(:estado, Persona.convertir_estado(valor))
  defp filtro(clave, _valor), do: {:error, "Filtro desconocido: #{clave}"}
end
