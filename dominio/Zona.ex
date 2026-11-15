defmodule Zona do
  defstruct codigo: "", nombre: "", nivel: :bajo, personas_afectadas: 0, sectores: []

  defmodule Sector do
    defstruct nombre: "", nivel: :bajo, personas_afectadas: 0, puntos: []
  end

  defmodule Punto do
    defstruct nombre: "", personas_atendidas: 0
  end

  # -----------------------------------
  # Creación y modificación (retornan {:ok, ...} o {:error, ...})
  # -----------------------------------

  def crear(codigo, nombre, nivel, personas \\ 0) do
    with :ok <- validar_texto(codigo, "código"),
         :ok <- validar_texto(nombre, "nombre"),
         :ok <- validar_cantidad(personas, "personas afectadas"),
         {:ok, nivel_atomo} <- convertir_nivel(nivel) do
      {:ok,
       %Zona{
         codigo: codigo,
         nombre: nombre,
         nivel: nivel_atomo,
         personas_afectadas: personas
       }}
    end
  end

  def agregar_sector(%Zona{} = zona, nombre, nivel, personas) do
    with :ok <- validar_texto(nombre, "sector"),
         :ok <- validar_cantidad(personas, "personas afectadas"),
         {:ok, nivel_atomo} <- convertir_nivel(nivel),
         false <- existe_sector?(zona.sectores, nombre) do
      sector = %Sector{nombre: nombre, nivel: nivel_atomo, personas_afectadas: personas}
      {:ok, %Zona{zona | sectores: zona.sectores ++ [sector]}}
    else
      true -> {:error, "El sector #{nombre} ya existe en la zona #{zona.codigo}"}
      error -> error
    end
  end

  def agregar_punto(%Zona{} = zona, nombre_sector, nombre_punto, atendidas \\ 0) do
    with :ok <- validar_texto(nombre_punto, "punto de atención"),
         :ok <- validar_cantidad(atendidas, "personas atendidas"),
         {:ok, sectores} <-
           insertar_punto(
             zona.sectores,
             nombre_sector,
             %Punto{nombre: nombre_punto, personas_atendidas: atendidas}
           ) do
      {:ok, %Zona{zona | sectores: sectores}}
    end
  end

  def convertir_nivel(nivel) when is_atom(nivel), do: convertir_nivel(Atom.to_string(nivel))

  def convertir_nivel(nivel) when is_binary(nivel) do
    case String.downcase(nivel) do
      n when n in ["critico", "crítico", "critica", "crítica"] -> {:ok, :critico}
      "alto" -> {:ok, :alto}
      "medio" -> {:ok, :medio}
      "bajo" -> {:ok, :bajo}
      _ -> {:error, "Nivel de afectación no válido: #{nivel}"}
    end
  end

  # -----------------------------------
  # Estadísticas (recursivas sobre zona -> sectores -> puntos)
  # -----------------------------------

  def total_en_sectores(%Zona{sectores: sectores}), do: sumar_afectadas(sectores)
  def total_atendidas(%Zona{sectores: sectores}), do: sumar_atendidas(sectores)
  def contar_puntos(%Zona{sectores: sectores}), do: contar_puntos_sectores(sectores)

  def estadisticas(%Zona{} = zona) do
    %{
      codigo: zona.codigo,
      nombre: zona.nombre,
      nivel: zona.nivel,
      estimadas: zona.personas_afectadas,
      en_sectores: total_en_sectores(zona),
      sectores: length(zona.sectores),
      puntos: contar_puntos(zona),
      atendidas: total_atendidas(zona)
    }
  end

  def generar_resumen(%Zona{} = zona) do
    e = estadisticas(zona)

    "Zona #{e.codigo} (#{e.nombre}) - nivel #{e.nivel}\n" <>
      " - Personas afectadas estimadas: #{e.estimadas}\n" <>
      " - Personas afectadas en sectores: #{e.en_sectores}\n" <>
      " - Sectores: #{e.sectores}\n" <>
      " - Puntos de atención: #{e.puntos}\n" <>
      " - Personas atendidas: #{e.atendidas}\n"
  end

  # -----------------------------------
  # Funciones recursivas privadas
  # -----------------------------------

  # Recorre la lista de sectores buscando el nombre
  defp existe_sector?([], _nombre), do: false
  defp existe_sector?([%Sector{nombre: nombre} | _resto], nombre), do: true
  defp existe_sector?([_sector | resto], nombre), do: existe_sector?(resto, nombre)

  # Recorre la lista de puntos buscando el nombre
  defp existe_punto?([], _nombre), do: false
  defp existe_punto?([%Punto{nombre: nombre} | _resto], nombre), do: true
  defp existe_punto?([_punto | resto], nombre), do: existe_punto?(resto, nombre)

  # Caso base: no se encontró el sector
  defp insertar_punto([], nombre_sector, _punto) do
    {:error, "No existe el sector #{nombre_sector}"}
  end

  # Caso: es el sector buscado
  defp insertar_punto([%Sector{nombre: nombre} = sector | resto], nombre, punto) do
    if existe_punto?(sector.puntos, punto.nombre) do
      {:error, "El punto #{punto.nombre} ya existe en el sector #{nombre}"}
    else
      {:ok, [%Sector{sector | puntos: sector.puntos ++ [punto]} | resto]}
    end
  end

  # Caso recursivo: seguir buscando en el resto
  defp insertar_punto([sector | resto], nombre_sector, punto) do
    case insertar_punto(resto, nombre_sector, punto) do
      {:ok, nuevos} -> {:ok, [sector | nuevos]}
      error -> error
    end
  end

  defp sumar_afectadas([]), do: 0
  defp sumar_afectadas([sector | resto]), do: sector.personas_afectadas + sumar_afectadas(resto)

  defp sumar_atendidas([]), do: 0

  defp sumar_atendidas([sector | resto]) do
    sumar_puntos(sector.puntos) + sumar_atendidas(resto)
  end

  defp sumar_puntos([]), do: 0
  defp sumar_puntos([punto | resto]), do: punto.personas_atendidas + sumar_puntos(resto)

  defp contar_puntos_sectores([]), do: 0

  defp contar_puntos_sectores([sector | resto]) do
    length(sector.puntos) + contar_puntos_sectores(resto)
  end

  # -----------------------------------
  # Validaciones
  # -----------------------------------

  defp validar_texto(texto, campo) when is_binary(texto) do
    case String.trim(texto) do
      "" -> {:error, "El campo #{campo} no puede estar vacío"}
      _ -> :ok
    end
  end

  defp validar_texto(_, campo), do: {:error, "El campo #{campo} debe ser texto"}

  defp validar_cantidad(cantidad, _campo) when is_integer(cantidad) and cantidad >= 0, do: :ok
  defp validar_cantidad(_, campo), do: {:error, "El campo #{campo} debe ser un entero no negativo"}
end
