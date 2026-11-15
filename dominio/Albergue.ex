defmodule Albergue do
  defstruct codigo: "",
            nombre: "",
            zona: "",
            capacidad: 0,
            ocupacion_base: 0,
            personas: MapSet.new(),
            recursos: MapSet.new(),
            necesidades: MapSet.new(),
            historial: []

  # -----------------------------------
  # Creación
  # -----------------------------------

  # La ocupación inicial (ocupacion_base) representa a las personas que ya
  # estaban alojadas antes de usar el sistema y no tienen documento registrado.
  def crear(codigo, nombre, zona, capacidad, ocupacion_base \\ 0) do
    with :ok <- validar_texto(codigo, "código"),
         :ok <- validar_texto(nombre, "nombre"),
         :ok <- validar_texto(zona, "zona"),
         :ok <- validar_capacidad(capacidad),
         :ok <- validar_ocupacion_base(ocupacion_base, capacidad) do
      {:ok,
       %Albergue{
         codigo: codigo,
         nombre: nombre,
         zona: zona,
         capacidad: capacidad,
         ocupacion_base: ocupacion_base
       }}
    end
  end

  # -----------------------------------
  # Consultas (funciones puras)
  # -----------------------------------

  def ocupacion(%Albergue{ocupacion_base: base, personas: personas}) do
    base + MapSet.size(personas)
  end

  def cupos_disponibles(%Albergue{capacidad: capacidad} = albergue) do
    capacidad - ocupacion(albergue)
  end

  def porcentaje_ocupacion(%Albergue{capacidad: capacidad} = albergue) do
    Float.round(ocupacion(albergue) * 100 / capacidad, 1)
  end

  # -----------------------------------
  # Ingreso y salida de personas
  # -----------------------------------

  def registrar_ingreso(%Albergue{} = albergue, documento) do
    with :ok <- validar_texto(documento, "documento"),
         :ok <- validar_no_alojada(albergue, documento),
         :ok <- validar_cupo(albergue) do
      {:ok,
       %Albergue{
         albergue
         | personas: MapSet.put(albergue.personas, documento),
           historial: [movimiento(:ingreso, documento) | albergue.historial]
       }}
    end
  end

  def registrar_salida(%Albergue{} = albergue, documento) do
    with :ok <- validar_texto(documento, "documento") do
      if MapSet.member?(albergue.personas, documento) do
        {:ok,
         %Albergue{
           albergue
           | personas: MapSet.delete(albergue.personas, documento),
             historial: [movimiento(:salida, documento) | albergue.historial]
         }}
      else
        {:error, "La persona #{documento} no está alojada en el albergue #{albergue.codigo}"}
      end
    end
  end

  # -----------------------------------
  # Recursos y necesidades asociados
  # -----------------------------------

  def asociar_recurso(%Albergue{} = albergue, codigo_recurso) do
    with :ok <- validar_texto(codigo_recurso, "código del recurso") do
      if MapSet.member?(albergue.recursos, codigo_recurso) do
        {:error, "El recurso #{codigo_recurso} ya está asociado al albergue #{albergue.codigo}"}
      else
        {:ok, %Albergue{albergue | recursos: MapSet.put(albergue.recursos, codigo_recurso)}}
      end
    end
  end

  def asociar_necesidad(%Albergue{} = albergue, id_necesidad) do
    with :ok <- validar_texto(id_necesidad, "id de la necesidad") do
      if MapSet.member?(albergue.necesidades, id_necesidad) do
        {:error, "La necesidad #{id_necesidad} ya está asociada al albergue #{albergue.codigo}"}
      else
        {:ok, %Albergue{albergue | necesidades: MapSet.put(albergue.necesidades, id_necesidad)}}
      end
    end
  end

  # -----------------------------------
  # Resumen
  # -----------------------------------

  def generar_resumen(%Albergue{} = albergue) do
    "Albergue #{albergue.codigo} (#{albergue.nombre}) - #{albergue.zona}\n" <>
      " - Capacidad máxima: #{albergue.capacidad}\n" <>
      " - Ocupación actual: #{ocupacion(albergue)} (#{porcentaje_ocupacion(albergue)}%)\n" <>
      " - Cupos disponibles: #{cupos_disponibles(albergue)}\n" <>
      " - Recursos asociados: #{unir(albergue.recursos)}\n" <>
      " - Necesidades asociadas: #{unir(albergue.necesidades)}\n"
  end

  defp unir(conjunto) do
    case conjunto |> MapSet.to_list() |> Enum.sort() do
      [] -> "ninguno"
      lista -> Enum.join(lista, ", ")
    end
  end

  # -----------------------------------
  # Funciones auxiliares
  # -----------------------------------

  defp movimiento(tipo, documento) do
    {DateTime.utc_now() |> DateTime.to_string(), tipo, documento}
  end

  defp validar_no_alojada(%Albergue{personas: personas, codigo: codigo}, documento) do
    if MapSet.member?(personas, documento) do
      {:error, "La persona #{documento} ya está alojada en el albergue #{codigo}"}
    else
      :ok
    end
  end

  # Regla de capacidad: la ocupación nunca puede superar la capacidad máxima
  defp validar_cupo(%Albergue{codigo: codigo, capacidad: capacidad} = albergue) do
    if cupos_disponibles(albergue) > 0 do
      :ok
    else
      {:error, "El albergue #{codigo} alcanzó su capacidad máxima (#{capacidad})"}
    end
  end

  defp validar_texto(texto, campo) when is_binary(texto) do
    case String.trim(texto) do
      "" -> {:error, "El campo #{campo} no puede estar vacío"}
      _ -> :ok
    end
  end

  defp validar_texto(_, campo), do: {:error, "El campo #{campo} debe ser texto"}

  defp validar_capacidad(capacidad) when is_integer(capacidad) and capacidad > 0, do: :ok
  defp validar_capacidad(_), do: {:error, "La capacidad debe ser un entero mayor que cero"}

  defp validar_ocupacion_base(base, capacidad)
       when is_integer(base) and base >= 0 and base <= capacidad,
       do: :ok

  defp validar_ocupacion_base(_, _) do
    {:error, "La ocupación actual debe ser un entero entre 0 y la capacidad máxima"}
  end

  defimpl String.Chars, for: Albergue do
    def to_string(%Albergue{} = a) do
      "#{a.codigo} | #{a.nombre} | #{a.zona} | " <>
        "#{Albergue.ocupacion(a)}/#{a.capacidad} (#{Albergue.porcentaje_ocupacion(a)}%)"
    end
  end
end
