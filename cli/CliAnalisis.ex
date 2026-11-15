defmodule CliAnalisis do
  @moduledoc """
  Herramientas compartidas por los módulos del CLI: dividir la línea,
  leer filtros clave=valor y convertir números.
  """

  @doc """
  Divide una línea en palabras. Lo que va entre comillas dobles es una sola palabra.
  Retorna `{:ok, lista}` o `{:error, razon}`.
  """
  def dividir(texto), do: dividir(String.graphemes(texto), nil, false, [])

  # Recursiva sobre los caracteres. `actual` es la palabra en construcción (nil si no hay)
  defp dividir([], nil, _comillas, acumulado), do: {:ok, Enum.reverse(acumulado)}
  defp dividir([], _actual, true, _acumulado), do: {:error, "Hay comillas sin cerrar"}
  defp dividir([], actual, false, acumulado), do: {:ok, Enum.reverse([actual | acumulado])}

  defp dividir(["\"" | resto], actual, comillas, acumulado),
    do: dividir(resto, actual || "", not comillas, acumulado)

  defp dividir([espacio | resto], actual, false, acumulado) when espacio in [" ", "\t"] do
    case actual do
      nil -> dividir(resto, nil, false, acumulado)
      _ -> dividir(resto, nil, false, [actual | acumulado])
    end
  end

  defp dividir([caracter | resto], actual, comillas, acumulado),
    do: dividir(resto, (actual || "") <> caracter, comillas, acumulado)

  @doc """
  Convierte cada "clave=valor" en un filtro usando la función `convertir`,
  que recibe (clave, valor) y retorna `{:ok, filtro}` o `{:error, razon}`.
  """
  def leer_filtros([], _convertir), do: {:ok, []}

  def leer_filtros([argumento | resto], convertir) do
    with [clave, valor] <- String.split(argumento, "=", parts: 2),
         {:ok, filtro} <- convertir.(String.downcase(clave), valor),
         {:ok, otros} <- leer_filtros(resto, convertir) do
      {:ok, [filtro | otros]}
    else
      {:error, razon} -> {:error, razon}
      _ -> {:error, "Filtro no válido: #{argumento} (use clave=valor)"}
    end
  end

  # Convierte {:ok, valor} en {:ok, {clave, valor}}
  def con_atomo(clave, {:ok, valor}), do: {:ok, {clave, valor}}
  def con_atomo(_clave, error), do: error

  def entero(texto, campo) do
    case Integer.parse(texto) do
      {valor, ""} -> {:ok, valor}
      _ -> {:error, "El campo #{campo} debe ser un número entero: #{texto}"}
    end
  end

  # Argumento opcional: sin valor es 0
  def entero_opcional([], _campo), do: {:ok, 0}
  def entero_opcional([texto], campo), do: entero(texto, campo)

  # Convierte un booleano en {:ok} / {:error, mensaje}
  def verificar(true, _mensaje), do: :ok
  def verificar(false, mensaje), do: {:error, mensaje}

  # Lista de elementos -> texto con un elemento por línea
  def lista_texto([], vacio), do: vacio

  def lista_texto(lista, _vacio) do
    lista
    |> Util2.convertir_coleccion_mensaje()
    |> Enum.join()
    |> String.trim_trailing()
  end
end
