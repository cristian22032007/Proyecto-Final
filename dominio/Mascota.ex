defmodule Mascota do
  defstruct id: "",
            tipo: :perdida,
            especie: "",
            nombre: "desconocido",
            caracteristicas: "",
            color: "",
            tamano: :mediana,
            zona: "",
            contacto: "",
            estado: :activa,
            coincidencia: nil

  # Pesos del puntaje de similitud (suman 100)
  @peso_zona 30
  @peso_color 25
  @peso_tamano 20
  @peso_nombre 15
  @peso_caracteristicas 10

  # Puntaje mínimo para considerar una posible coincidencia
  @umbral 50

  @tamanos [:pequena, :mediana, :grande]

  @transiciones %{
    activa: [:posible_coincidencia, :resuelta],
    posible_coincidencia: [:resuelta],
    resuelta: []
  }

  def umbral, do: @umbral


  # Creación


  def crear(id, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto) do
    with :ok <- validar_texto(especie, "especie"),
         :ok <- validar_texto(color, "color"),
         :ok <- validar_texto(zona, "zona"),
         :ok <- validar_texto(contacto, "contacto"),
         :ok <- validar_opcional(nombre, "nombre"),
         :ok <- validar_opcional(caracteristicas, "características"),
         {:ok, tipo_atomo} <- convertir_tipo(tipo),
         {:ok, tamano_atomo} <- convertir_tamano(tamano) do
      {:ok,
       %Mascota{
         id: id,
         tipo: tipo_atomo,
         especie: normalizar(especie),
         nombre: nombre_o_desconocido(nombre),
         caracteristicas: String.trim(caracteristicas),
         color: normalizar(color),
         tamano: tamano_atomo,
         zona: String.trim(zona),
         contacto: String.trim(contacto)
       }}
    end
  end


  # Conversiones


  def convertir_tipo(tipo) when is_atom(tipo), do: convertir_tipo(Atom.to_string(tipo))

  def convertir_tipo(tipo) when is_binary(tipo) do
    case normalizar(tipo) do
      t when t in ["lost", "perdida"] -> {:ok, :perdida}
      t when t in ["found", "encontrada"] -> {:ok, :encontrada}
      _ -> {:error, "Tipo de reporte no válido: #{tipo} (use lost/found)"}
    end
  end

  def convertir_tamano(tamano) when is_atom(tamano), do: convertir_tamano(Atom.to_string(tamano))

  def convertir_tamano(tamano) when is_binary(tamano) do
    case normalizar(tamano) do
      t when t in ["pequena", "pequeña", "pequeno", "pequeño"] -> {:ok, :pequena}
      t when t in ["mediana", "mediano"] -> {:ok, :mediana}
      "grande" -> {:ok, :grande}
      _ -> {:error, "Tamaño no válido: #{tamano}"}
    end
  end

  def convertir_estado(estado) when is_atom(estado), do: convertir_estado(Atom.to_string(estado))

  def convertir_estado(estado) when is_binary(estado) do
    case normalizar(estado) do
      "activa" -> {:ok, :activa}
      "posible_coincidencia" -> {:ok, :posible_coincidencia}
      "resuelta" -> {:ok, :resuelta}
      _ -> {:error, "Estado de mascota no válido: #{estado}"}
    end
  end


  # Cambios de estado


  def cambiar_estado(%Mascota{id: id, estado: :resuelta}, _nuevo) do
    {:error, "La mascota #{id} ya está resuelta y no se puede cerrar dos veces"}
  end

  def cambiar_estado(%Mascota{estado: actual} = mascota, nuevo) do
    if nuevo in Map.fetch!(@transiciones, actual) do
      {:ok, %Mascota{mascota | estado: nuevo}}
    else
      {:error, "Transición no válida: #{actual} -> #{nuevo}"}
    end
  end

  # Cierra el reporte y lo enlaza con el reporte con el que coincidió
  def resolver(%Mascota{} = mascota, id_otra) do
    with {:ok, resuelta} <- cambiar_estado(mascota, :resuelta) do
      {:ok, %Mascota{resuelta | coincidencia: id_otra}}
    end
  end


  # Algoritmo de similitud (0 a 100)


  # Si la especie es distinta, no puede haber coincidencia
  def calcular_similitud(%Mascota{especie: a}, %Mascota{especie: b}) when a != b, do: 0

  def calcular_similitud(%Mascota{} = a, %Mascota{} = b) do
    puntaje_zona(a, b) + puntaje_color(a, b) + puntaje_tamano(a, b) +
      puntaje_nombre(a, b) + puntaje_caracteristicas(a, b)
  end

  defp puntaje_zona(a, b) do
    if normalizar(a.zona) == normalizar(b.zona), do: @peso_zona, else: 0
  end

  defp puntaje_color(a, b) do
    if a.color == b.color, do: @peso_color, else: 0
  end

  # Mismo tamaño: puntaje completo. Tamaño adyacente: la mitad.
  defp puntaje_tamano(a, b) do
    distancia = abs(indice_tamano(a.tamano) - indice_tamano(b.tamano))

    case distancia do
      0 -> @peso_tamano
      1 -> div(@peso_tamano, 2)
      _ -> 0
    end
  end

  defp indice_tamano(tamano), do: Enum.find_index(@tamanos, &(&1 == tamano))

  defp puntaje_nombre(a, b) do
    nombre_a = normalizar(a.nombre)
    nombre_b = normalizar(b.nombre)

    if nombre_a == nombre_b and nombre_a != "desconocido", do: @peso_nombre, else: 0
  end

  # Proporción de palabras de las características que tienen en común
  defp puntaje_caracteristicas(a, b) do
    palabras_a = palabras(a.caracteristicas)
    palabras_b = palabras(b.caracteristicas)
    mayor = max(MapSet.size(palabras_a), MapSet.size(palabras_b))

    if mayor == 0 do
      0
    else
      comunes = contar_comunes(MapSet.to_list(palabras_a), palabras_b)
      round(@peso_caracteristicas * comunes / mayor)
    end
  end

  # Recursiva: cuenta cuántas palabras de la lista están en el conjunto
  defp contar_comunes([], _conjunto), do: 0

  defp contar_comunes([palabra | resto], conjunto) do
    if MapSet.member?(conjunto, palabra) do
      1 + contar_comunes(resto, conjunto)
    else
      contar_comunes(resto, conjunto)
    end
  end

  # Ignora palabras muy cortas ("de", "el", "y"...)
  defp palabras(texto) do
    texto
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.filter(&(String.length(&1) > 2))
    |> MapSet.new()
  end


  # Funciones auxiliares


  defp normalizar(texto), do: texto |> String.trim() |> String.downcase()

  defp nombre_o_desconocido(nombre) do
    case String.trim(nombre) do
      "" -> "desconocido"
      limpio -> limpio
    end
  end

  defp validar_texto(texto, campo) when is_binary(texto) do
    case String.trim(texto) do
      "" -> {:error, "El campo #{campo} no puede estar vacío"}
      _ -> :ok
    end
  end

  defp validar_texto(_, campo), do: {:error, "El campo #{campo} debe ser texto"}

  defp validar_opcional(texto, _campo) when is_binary(texto), do: :ok
  defp validar_opcional(_, campo), do: {:error, "El campo #{campo} debe ser texto"}

  defimpl String.Chars, for: Mascota do
    def to_string(%Mascota{} = m) do
      "#{m.id} | #{m.tipo} | #{m.especie} #{m.nombre} | #{m.color}, #{m.tamano} | " <>
        "#{m.zona} | #{m.estado}"
    end
  end
end
