defmodule ServidorZonas do
  use GenServer


  # API pública


  def start_link(_opciones \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def registrar_zona(codigo, nombre, nivel, personas \\ 0) do
    GenServer.call(__MODULE__, {:registrar_zona, codigo, nombre, nivel, personas})
  end

  def registrar_sector(codigo_zona, nombre, nivel, personas) do
    GenServer.call(__MODULE__, {:registrar_sector, codigo_zona, nombre, nivel, personas})
  end

  def registrar_punto(codigo_zona, sector, nombre, atendidas \\ 0) do
    GenServer.call(__MODULE__, {:registrar_punto, codigo_zona, sector, nombre, atendidas})
  end

  def consultar(codigo_zona), do: GenServer.call(__MODULE__, {:consultar, codigo_zona})

  def estadisticas(codigo_zona), do: GenServer.call(__MODULE__, {:estadisticas, codigo_zona})

  def listar, do: GenServer.call(__MODULE__, :listar)


  # Callbacks


  @impl true
  def init(_estado), do: {:ok, cargar()}

  @impl true
  def handle_call(mensaje, desde, estado) do
    {:reply, respuesta, nuevo} = procesar(mensaje, desde, estado)
    if nuevo != estado, do:  if(nuevo != estado, do: guardar(nuevo))
    {:reply, respuesta, nuevo}
  end


  defp procesar({:registrar_zona, codigo, nombre, nivel, personas}, _from, zonas) do
    if Map.has_key?(zonas, codigo) do
      {:reply, {:error, "Ya existe la zona #{codigo}"}, zonas}
    else
      case Zona.crear(codigo, nombre, nivel, personas) do
        {:ok, zona} -> {:reply, {:ok, zona}, Map.put(zonas, codigo, zona)}
        {:error, razon} -> {:reply, {:error, razon}, zonas}
      end
    end
  end

  defp procesar({:registrar_sector, codigo, nombre, nivel, personas}, _from, zonas) do
    modificar_zona(zonas, codigo, &Zona.agregar_sector(&1, nombre, nivel, personas))
  end

  defp procesar({:registrar_punto, codigo, sector, nombre, atendidas}, _from, zonas) do
    modificar_zona(zonas, codigo, &Zona.agregar_punto(&1, sector, nombre, atendidas))
  end

  defp procesar({:consultar, codigo}, _from, zonas) do
    {:reply, buscar_zona(zonas, codigo), zonas}
  end

  defp procesar({:estadisticas, codigo}, _from, zonas) do
    respuesta =
      case buscar_zona(zonas, codigo) do
        {:ok, zona} -> {:ok, Zona.estadisticas(zona)}
        error -> error
      end

    {:reply, respuesta, zonas}
  end

  defp procesar(:listar, _from, zonas) do
    {:reply, Map.values(zonas), zonas}
  end


  # Funciones privadas


  defp buscar_zona(zonas, codigo) do
    case Map.fetch(zonas, codigo) do
      {:ok, zona} -> {:ok, zona}
      :error -> {:error, "No existe la zona #{codigo}"}
    end
  end

  # Busca la zona, aplica la modificación pura y guarda el resultado
  defp modificar_zona(zonas, codigo, modificacion) do
    with {:ok, zona} <- buscar_zona(zonas, codigo),
         {:ok, nueva} <- modificacion.(zona) do
      {:reply, {:ok, nueva}, Map.put(zonas, codigo, nueva)}
    else
      {:error, razon} -> {:reply, {:error, razon}, zonas}
    end
  end

  # Persistencia: zonas.txt, sectores_zonas.txt y puntos_zonas.txt


  defp guardar(zonas) do
    lista = zonas |> Map.values() |> Util2.ordenar(:asc, & &1.codigo)

    filas_zonas =
      Enum.map(lista, fn z -> [z.codigo, z.nombre, z.nivel, z.personas_afectadas] end)

    filas_sectores =
      Enum.flat_map(lista, fn z ->
        Enum.map(z.sectores, fn s -> [z.codigo, s.nombre, s.nivel, s.personas_afectadas] end)
      end)

    filas_puntos =
      Enum.flat_map(lista, fn z ->
        Enum.flat_map(z.sectores, fn s ->
          Enum.map(s.puntos, fn p -> [z.codigo, s.nombre, p.nombre, p.personas_atendidas] end)
        end)
      end)

    Almacen.guardar("zonas.txt", filas_zonas)
    Almacen.guardar("sectores_zonas.txt", filas_sectores)
    Almacen.guardar("puntos_zonas.txt", filas_puntos)
  end

  defp cargar do
    %{}
    |> Almacen.cargar("zonas.txt", &leer_zona/2)
    |> Almacen.cargar("sectores_zonas.txt", &leer_sector/2)
    |> Almacen.cargar("puntos_zonas.txt", &leer_punto/2)
  end

  defp leer_zona([codigo, nombre, nivel, personas], zonas) do
    with {:ok, cantidad} <- Almacen.entero(personas),
         {:ok, zona} <- Zona.crear(codigo, nombre, nivel, cantidad) do
      {:ok, Map.put(zonas, codigo, zona)}
    end
  end

  defp leer_zona(_campos, _zonas), do: {:error, "formato no válido"}

  defp leer_sector([codigo, nombre, nivel, personas], zonas) do
    with {:ok, cantidad} <- Almacen.entero(personas),
         {:ok, zona} <- buscar_zona(zonas, codigo),
         {:ok, nueva} <- Zona.agregar_sector(zona, nombre, nivel, cantidad) do
      {:ok, Map.put(zonas, codigo, nueva)}
    end
  end

  defp leer_sector(_campos, _zonas), do: {:error, "formato no válido"}

  defp leer_punto([codigo, sector, nombre, atendidas], zonas) do
    with {:ok, cantidad} <- Almacen.entero(atendidas),
         {:ok, zona} <- buscar_zona(zonas, codigo),
         {:ok, nueva} <- Zona.agregar_punto(zona, sector, nombre, cantidad) do
      {:ok, Map.put(zonas, codigo, nueva)}
    end
  end

  defp leer_punto(_campos, _zonas), do: {:error, "formato no válido"}
end
