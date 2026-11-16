defmodule Almacen do
  @moduledoc """
  Persistencia en archivos de texto plano.

  Formato: un registro por línea, con los campos separados por `|`.
  Escapes: `\\` -> `\\\\`, `|` -> `\\p`, salto de línea -> `\\n`.
  """

  def directorio, do: System.get_env("DATA_EMERGENCIAS") || "data"

  # Para las pruebas: cada ejecución trabaja en una carpeta nueva y vacía
  def usar_directorio_temporal do
    carpeta =
      Path.join(
        System.tmp_dir!(),
        "emergencias_#{System.os_time()}_#{System.unique_integer([:positive])}"
      )

    System.put_env("DATA_EMERGENCIAS", carpeta)
    carpeta
  end

  # Cada registro es una lista de campos. Se escribe en un archivo temporal
  # y luego se renombra, para no dejar el archivo a medias si algo falla.
  def guardar(nombre, registros) do
    ruta = Path.join(directorio(), nombre)
    temporal = ruta <> ".tmp"
    contenido = Enum.map_join(registros, "", fn campos -> codificar(campos) <> "\n" end)

    with :ok <- File.mkdir_p(directorio()),
         :ok <- File.write(temporal, contenido),
         :ok <- File.rename(temporal, ruta) do
      :ok
    else
      {:error, razon} ->
        Util2.mostrar("No se pudo guardar #{ruta}: #{inspect(razon)}", :error)
        {:error, razon}
    end
  end

  # Retorna una lista de {campos, numero_de_linea}. Si el archivo no existe, []
  def leer(nombre) do
    ruta = Path.join(directorio(), nombre)

    if File.exists?(ruta) do
      ruta
      |> Util2.lineas_utiles()
      |> Enum.map(fn {linea, numero} -> {decodificar(linea), numero} end)
    else
      []
    end
  end

  # Aplica `interpretar` a cada línea del archivo, acumulando el estado.
  # Si una línea es inválida se informa con su número y se omite.
  def cargar(estado, nombre, interpretar) do
    nombre
    |> leer()
    |> Enum.reduce(estado, fn {campos, numero}, acumulado ->
      case interpretar.(campos, acumulado) do
        {:ok, nuevo} ->
          nuevo

        {:error, razon} ->
          Util2.mostrar("#{nombre}, línea #{numero}: #{razon}", :error)
          acumulado
      end
    end)
  end

  def entero(texto) do
    case Integer.parse(texto) do
      {valor, ""} -> {:ok, valor}
      _ -> {:error, "no es un entero: #{texto}"}
    end
  end


  # Escapes


  def codificar(campos) do
    campos
    |> Enum.map(&escapar/1)
    |> Enum.join("|")
  end

  def decodificar(linea) do
    linea
    |> String.split("|")
    |> Enum.map(&desescapar/1)
  end

  # to_string convierte átomos, enteros y nil (nil queda como "")
  defp escapar(valor) do
    valor
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("|", "\\p")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "")
  end

  # Se protegen primero las barras dobles para no confundirlas con \p o \n
  defp desescapar(texto) do
    texto
    |> String.replace("\\\\", "\0")
    |> String.replace("\\p", "|")
    |> String.replace("\\n", "\n")
    |> String.replace("\0", "\\")
  end
end
