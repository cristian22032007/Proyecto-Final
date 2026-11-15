defmodule ServidorAlbergues do
  use GenServer


  # API pública


  def start_link(_opciones \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def registrar(codigo, nombre, zona, capacidad, ocupacion \\ 0) do
    GenServer.call(__MODULE__, {:registrar, codigo, nombre, zona, capacidad, ocupacion})
  end

  def ingreso(codigo, documento), do: GenServer.call(__MODULE__, {:ingreso, codigo, documento})

  def salida(codigo, documento), do: GenServer.call(__MODULE__, {:salida, codigo, documento})

  def consultar(codigo), do: GenServer.call(__MODULE__, {:consultar, codigo})

  def cupos(codigo), do: GenServer.call(__MODULE__, {:cupos, codigo})

  def asociar_recurso(codigo, codigo_recurso),
    do: GenServer.call(__MODULE__, {:asociar_recurso, codigo, codigo_recurso})

  def asociar_necesidad(codigo, id_necesidad),
    do: GenServer.call(__MODULE__, {:asociar_necesidad, codigo, id_necesidad})

  def listar, do: GenServer.call(__MODULE__, :listar)

  # Albergues con mayor porcentaje de ocupación (de mayor a menor)
  def reporte_ocupacion(limite \\ 3), do: GenServer.call(__MODULE__, {:reporte, limite})


  # Callbacks


  @impl true
  def init(_estado), do: {:ok, cargar()}

   @impl true
  def handle_call(mensaje, desde, estado) do
    {:reply, respuesta, nuevo} = procesar(mensaje, desde, estado)
    if nuevo != estado, do:  if(nuevo != estado, do: guardar(nuevo))
    {:reply, respuesta, nuevo}
  end


  defp procesar({:registrar, codigo, nombre, zona, capacidad, ocupacion}, _from, albergues) do
    if Map.has_key?(albergues, codigo) do
      {:reply, {:error, "Ya existe el albergue #{codigo}"}, albergues}
    else
      case Albergue.crear(codigo, nombre, zona, capacidad, ocupacion) do
        {:ok, albergue} -> {:reply, {:ok, albergue}, Map.put(albergues, codigo, albergue)}
        {:error, razon} -> {:reply, {:error, razon}, albergues}
      end
    end
  end

  # Verificar el cupo y ocupar el lugar ocurre en un solo mensaje del GenServer,
  # por eso la ocupación nunca supera la capacidad máxima.
  defp procesar({:ingreso, codigo, documento}, _from, albergues) do
    modificar(albergues, codigo, &Albergue.registrar_ingreso(&1, documento))
  end

  defp procesar({:salida, codigo, documento}, _from, albergues) do
    modificar(albergues, codigo, &Albergue.registrar_salida(&1, documento))
  end

  defp procesar({:consultar, codigo}, _from, albergues) do
    {:reply, buscar(albergues, codigo), albergues}
  end

  defp procesar({:cupos, codigo}, _from, albergues) do
    respuesta =
      case buscar(albergues, codigo) do
        {:ok, albergue} -> {:ok, Albergue.cupos_disponibles(albergue)}
        error -> error
      end

    {:reply, respuesta, albergues}
  end

  defp procesar({:asociar_recurso, codigo, codigo_recurso}, _from, albergues) do
    modificar(albergues, codigo, &Albergue.asociar_recurso(&1, codigo_recurso))
  end

  defp procesar({:asociar_necesidad, codigo, id_necesidad}, _from, albergues) do
    modificar(albergues, codigo, &Albergue.asociar_necesidad(&1, id_necesidad))
  end

  defp procesar(:listar, _from, albergues) do
    lista = albergues |> Map.values() |> Util2.ordenar(:asc, & &1.codigo)
    {:reply, lista, albergues}
  end

  defp procesar({:reporte, limite}, _from, albergues) do
    lista =
      albergues
      |> Map.values()
      |> Util2.ordenar(:desc, &{Albergue.porcentaje_ocupacion(&1), &1.codigo})
      |> Enum.take(limite)

    {:reply, lista, albergues}
  end


  # Funciones privadas


  defp buscar(albergues, codigo) do
    case Map.fetch(albergues, codigo) do
      {:ok, albergue} -> {:ok, albergue}
      :error -> {:error, "No existe el albergue #{codigo}"}
    end
  end

  # Busca el albergue, aplica la operación pura y guarda el resultado solo si salió {:ok, ...}
  defp modificar(albergues, codigo, operacion) do
    with {:ok, albergue} <- buscar(albergues, codigo),
         {:ok, nuevo} <- operacion.(albergue) do
      {:reply, {:ok, nuevo}, Map.put(albergues, codigo, nuevo)}
    else
      {:error, razon} -> {:reply, {:error, razon}, albergues}
    end
  end

  # Persistencia: albergues.txt y sus archivos asociados


  defp guardar(albergues) do
    lista = albergues |> Map.values() |> Util2.ordenar(:asc, & &1.codigo)

    filas =
      Enum.map(lista, fn a -> [a.codigo, a.nombre, a.zona, a.capacidad, a.ocupacion_base] end)

    # MapSet -> lista ordenada -> filas [codigo, valor]
    alojados = filas_conjunto(lista, fn a -> a.personas end)
    recursos = filas_conjunto(lista, fn a -> a.recursos end)
    necesidades = filas_conjunto(lista, fn a -> a.necesidades end)

    movimientos =
      Enum.flat_map(lista, fn a ->
        a.historial
        |> Enum.reverse()
        |> Enum.map(fn {fecha, tipo, documento} -> [a.codigo, fecha, tipo, documento] end)
      end)

    Almacen.guardar("albergues.txt", filas)
    Almacen.guardar("alojados_albergues.txt", alojados)
    Almacen.guardar("recursos_albergues.txt", recursos)
    Almacen.guardar("necesidades_albergues.txt", necesidades)
    Almacen.guardar("movimientos_albergues.txt", movimientos)
  end

  defp filas_conjunto(albergues, obtener_conjunto) do
    Enum.flat_map(albergues, fn a ->
      a
      |> obtener_conjunto.()
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.map(fn valor -> [a.codigo, valor] end)
    end)
  end

  defp cargar do
    %{}
    |> Almacen.cargar("albergues.txt", &leer_albergue/2)
    |> Almacen.cargar("alojados_albergues.txt", &leer_alojado/2)
    |> Almacen.cargar("recursos_albergues.txt", &leer_recurso/2)
    |> Almacen.cargar("necesidades_albergues.txt", &leer_necesidad/2)
    |> Almacen.cargar("movimientos_albergues.txt", &leer_movimiento/2)
  end

  defp leer_albergue([codigo, nombre, zona, capacidad, base], albergues) do
    with {:ok, capacidad_entera} <- Almacen.entero(capacidad),
         {:ok, base_entera} <- Almacen.entero(base),
         {:ok, albergue} <- Albergue.crear(codigo, nombre, zona, capacidad_entera, base_entera) do
      {:ok, Map.put(albergues, codigo, albergue)}
    end
  end

  defp leer_albergue(_campos, _albergues), do: {:error, "formato no válido"}

  defp leer_alojado([codigo, documento], albergues) do
    actualizar(albergues, codigo, fn %Albergue{} = a ->
      %Albergue{a | personas: MapSet.put(a.personas, documento)}
    end)
  end

  defp leer_alojado(_campos, _albergues), do: {:error, "formato no válido"}

  defp leer_recurso([codigo, recurso], albergues) do
    actualizar(albergues, codigo, fn %Albergue{} = a ->
      %Albergue{a | recursos: MapSet.put(a.recursos, recurso)}
    end)
  end

  defp leer_recurso(_campos, _albergues), do: {:error, "formato no válido"}

  defp leer_necesidad([codigo, necesidad], albergues) do
    actualizar(albergues, codigo, fn %Albergue{} = a ->
      %Albergue{a | necesidades: MapSet.put(a.necesidades, necesidad)}
    end)
  end

  defp leer_necesidad(_campos, _albergues), do: {:error, "formato no válido"}

  defp leer_movimiento([codigo, fecha, tipo, documento], albergues) do
    actualizar(albergues, codigo, fn %Albergue{} = a ->
      movimiento = {fecha, String.to_atom(tipo), documento}
      %Albergue{a | historial: [movimiento | a.historial]}
    end)
  end

  defp leer_movimiento(_campos, _albergues), do: {:error, "formato no válido"}

  # Busca el albergue y le aplica el cambio
  defp actualizar(albergues, codigo, cambio) do
    case Map.fetch(albergues, codigo) do
      {:ok, albergue} -> {:ok, Map.put(albergues, codigo, cambio.(albergue))}
      :error -> {:error, "no existe el albergue #{codigo}"}
    end
  end
end
