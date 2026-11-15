defmodule CliAlbergues do
  @moduledoc "Comandos del CLI sobre albergues, ingresos y salidas."

  def ejecutar("register_shelter", [codigo, nombre, zona, capacidad | resto], _usuario)
      when length(resto) <= 1 do
    with {:ok, capacidad_entera} <- CliAnalisis.entero(capacidad, "capacidad"),
         {:ok, ocupacion} <- CliAnalisis.entero_opcional(resto, "ocupación"),
         {:ok, _zona} <- ServidorZonas.consultar(zona),
         {:ok, albergue} <-
           ServidorAlbergues.registrar(codigo, nombre, zona, capacidad_entera, ocupacion) do
      {:ok, "Albergue registrado: #{albergue}"}
    end
  end

  def ejecutar("check_shelter", [codigo], _usuario) do
    with {:ok, albergue} <- ServidorAlbergues.consultar(codigo) do
      {:ok, String.trim_trailing(Albergue.generar_resumen(albergue))}
    end
  end

  # La persona debe existir; al ingresar pasa a "en_albergue"
  def ejecutar("register_entry", [codigo, documento], _usuario) do
    with {:ok, persona} <- ServidorPersonas.consultar(documento),
         :ok <- validar_estado_albergue(persona),
         {:ok, albergue} <- ServidorAlbergues.ingreso(codigo, documento),
         :ok <- marcar_en_albergue(persona) do
      {:ok, "#{persona.nombre} ingresó al albergue #{codigo} (cupos disponibles: #{Albergue.cupos_disponibles(albergue)})"}
    end
  end

  # Al salir, quien estaba "en_albergue" pasa a "localizada"
  def ejecutar("register_exit", [codigo, documento], _usuario) do
    with {:ok, albergue} <- ServidorAlbergues.salida(codigo, documento) do
      liberar_persona(documento)
      {:ok, "La persona #{documento} salió del albergue #{codigo} (cupos disponibles: #{Albergue.cupos_disponibles(albergue)})"}
    end
  end

  def ejecutar("shelter_resource", [codigo, codigo_recurso], _usuario) do
    with {:ok, _recurso} <- ServidorRecursos.consultar(codigo_recurso),
         {:ok, _albergue} <- ServidorAlbergues.asociar_recurso(codigo, codigo_recurso) do
      {:ok, "Recurso #{codigo_recurso} asociado al albergue #{codigo}"}
    end
  end

  def ejecutar("shelter_need", [codigo, id_necesidad], _usuario) do
    with {:ok, _necesidad} <- ServidorNecesidades.consultar(id_necesidad),
         {:ok, _albergue} <- ServidorAlbergues.asociar_necesidad(codigo, id_necesidad) do
      {:ok, "Necesidad #{id_necesidad} asociada al albergue #{codigo}"}
    end
  end

  def ejecutar("shelter_report", argumentos, _usuario) when length(argumentos) <= 1 do
    with {:ok, limite} <- CliAnalisis.entero_opcional(argumentos, "límite") do
      cantidad = if limite == 0, do: 3, else: limite
      lista = ServidorAlbergues.reporte_ocupacion(cantidad)

      {:ok,
       "Albergues con mayor ocupación:\n" <>
         CliAnalisis.lista_texto(lista, "No hay albergues registrados")}
    end
  end

  def ejecutar(_comando, _argumentos, _usuario), do: {:error, :uso}

  # Antes de ingresar se comprueba (con la función pura) que el cambio de estado sea válido
  defp validar_estado_albergue(%Persona{estado: :en_albergue}), do: :ok

  defp validar_estado_albergue(%Persona{} = persona) do
    case Persona.cambiar_estado(persona, :en_albergue) do
      {:ok, _persona} -> :ok
      {:error, razon} -> {:error, razon}
    end
  end

  defp marcar_en_albergue(%Persona{estado: :en_albergue}), do: :ok

  defp marcar_en_albergue(%Persona{documento: documento}) do
    case ServidorPersonas.cambiar_estado(documento, "en_albergue") do
      {:ok, _persona} -> :ok
      {:error, razon} -> {:error, razon}
    end
  end

  defp liberar_persona(documento) do
    case ServidorPersonas.consultar(documento) do
      {:ok, %Persona{estado: :en_albergue}} -> ServidorPersonas.cambiar_estado(documento, "localizada")
      _ -> :ok
    end
  end
end
