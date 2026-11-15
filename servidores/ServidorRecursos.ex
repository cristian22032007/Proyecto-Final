defmodule ServidorRecursos do
  use GenServer

  def start_link(_opciones \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def registrar(codigo, nombre, cantidad, unidad, ubicacion) do
    GenServer.call(__MODULE__, {:registrar, codigo, nombre, cantidad, unidad, ubicacion})
  end

  def entrada(codigo, cantidad, motivo \\ "entrada"),
    do: GenServer.call(__MODULE__, {:entrada, codigo, cantidad, motivo})

  def salida(codigo, cantidad, motivo \\ "salida"),
    do: GenServer.call(__MODULE__, {:salida, codigo, cantidad, motivo})

  def transferir(codigo, destino, cantidad),
    do: GenServer.call(__MODULE__, {:transferir, codigo, destino, cantidad})

  def consultar(codigo), do: GenServer.call(__MODULE__, {:consultar, codigo})

  def disponibilidad(nombre, ubicacion \\ :todas),
    do: GenServer.call(__MODULE__, {:disponibilidad, nombre, ubicacion})

  def listar, do: GenServer.call(__MODULE__, :listar)

  @impl true
  def init(_estado), do: {:ok, cargar()}

  @impl true
  def handle_call(mensaje, desde, estado) do
    {:reply, respuesta, nuevo} = procesar(mensaje, desde, estado)
    if nuevo != estado, do: if(nuevo != estado, do: guardar(nuevo))
    {:reply, respuesta, nuevo}
  end

  defp procesar({:registrar, codigo, nombre, cantidad, unidad, ubicacion}, _from, recursos) do
    if Map.has_key?(recursos, codigo) do
      {:reply, {:error, "Ya existe el recurso #{codigo}"}, recursos}
    else
      case Recurso.crear(codigo, nombre, cantidad, unidad, ubicacion) do
        {:ok, recurso} -> {:reply, {:ok, recurso}, Map.put(recursos, codigo, recurso)}
        {:error, razon} -> {:reply, {:error, razon}, recursos}
      end
    end
  end

  defp procesar({:entrada, codigo, cantidad, motivo}, _from, recursos) do
    modificar(recursos, codigo, &Recurso.registrar_entrada(&1, cantidad, motivo))
  end

  # Como el GenServer atiende un mensaje a la vez, esta operación es atómica:
  # nunca se puede entregar más de lo que hay en inventario.
  defp procesar({:salida, codigo, cantidad, motivo}, _from, recursos) do
    modificar(recursos, codigo, &Recurso.registrar_salida(&1, cantidad, motivo))
  end

  defp procesar({:transferir, codigo, destino, cantidad}, _from, recursos) do
    with {:ok, origen} <- buscar(recursos, codigo),
         :ok <- validar_destino(origen, destino),
         {:ok, origen_nuevo} <-
           Recurso.registrar_salida(origen, cantidad, "transferencia a #{destino}") do
      recursos
      |> Map.put(codigo, origen_nuevo)
      |> acreditar_destino(origen, destino, cantidad)
    else
      {:error, razon} -> {:reply, {:error, razon}, recursos}
    end
  end

  defp procesar({:consultar, codigo}, _from, recursos) do
    {:reply, buscar(recursos, codigo), recursos}
  end

  defp procesar({:disponibilidad, nombre, ubicacion}, _from, recursos) do
    total =
      recursos
      |> Map.values()
      |> Enum.filter(fn r ->
        r.nombre == nombre and (ubicacion == :todas or r.ubicacion == ubicacion)
      end)
      |> Enum.map(& &1.cantidad)
      |> Enum.sum()

    {:reply, total, recursos}
  end

  defp procesar(:listar, _from, recursos) do
    {:reply, Map.values(recursos), recursos}
  end


  # Funciones privadas


  defp buscar(recursos, codigo) do
    case Map.fetch(recursos, codigo) do
      {:ok, recurso} -> {:ok, recurso}
      :error -> {:error, "No existe el recurso #{codigo}"}
    end
  end

  defp modificar(recursos, codigo, operacion) do
    with {:ok, recurso} <- buscar(recursos, codigo),
         {:ok, nuevo} <- operacion.(recurso) do
      {:reply, {:ok, nuevo}, Map.put(recursos, codigo, nuevo)}
    else
      {:error, razon} -> {:reply, {:error, razon}, recursos}
    end
  end

  defp validar_destino(%Recurso{ubicacion: ubicacion}, destino) when ubicacion == destino,
    do: {:error, "El origen y el destino son el mismo centro"}

  defp validar_destino(_origen, _destino), do: :ok

  # Si en el destino ya existe un recurso del mismo nombre se suma; si no, se crea uno nuevo
  defp acreditar_destino(recursos, origen, destino, cantidad) do
    existente =
      recursos
      |> Map.values()
      |> Enum.find(fn r -> r.nombre == origen.nombre and r.ubicacion == destino end)

    case existente do
      nil ->
        codigo_nuevo = "#{origen.codigo}-#{destino}"

        {:ok, nuevo} =
          Recurso.crear(codigo_nuevo, origen.nombre, cantidad, origen.unidad, destino)

        {:reply, {:ok, :transferido}, Map.put(recursos, codigo_nuevo, nuevo)}

      destino_recurso ->
        {:ok, actualizado} =
          Recurso.registrar_entrada(
            destino_recurso,
            cantidad,
            "transferencia desde #{origen.ubicacion}"
          )

        {:reply, {:ok, :transferido}, Map.put(recursos, destino_recurso.codigo, actualizado)}
    end
  end


  # Persistencia: recursos.txt y movimientos_recursos.txt


  defp guardar(recursos) do
    lista = recursos |> Map.values() |> Util2.ordenar(:asc, & &1.codigo)

    filas =
      Enum.map(lista, fn r ->
        [r.codigo, r.nombre, r.categoria, r.cantidad, r.unidad, r.ubicacion]
      end)

    # El historial se guarda del movimiento más antiguo al más reciente
    movimientos =
      Enum.flat_map(lista, fn r ->
        r.historial
        |> Enum.reverse()
        |> Enum.map(fn {fecha, tipo, cantidad, motivo} ->
          [r.codigo, fecha, tipo, cantidad, motivo]
        end)
      end)

    Almacen.guardar("recursos.txt", filas)
    Almacen.guardar("movimientos_recursos.txt", movimientos)
  end

  defp cargar do
    %{}
    |> Almacen.cargar("recursos.txt", &leer_recurso/2)
    |> Almacen.cargar("movimientos_recursos.txt", &leer_movimiento/2)
  end

  defp leer_recurso([codigo, nombre, categoria, cantidad, unidad, ubicacion], recursos) do
    with {:ok, cantidad_entera} <- Almacen.entero(cantidad) do
      recurso = %Recurso{
        codigo: codigo,
        nombre: nombre,
        categoria: categoria,
        cantidad: cantidad_entera,
        unidad: unidad,
        ubicacion: ubicacion
      }

      {:ok, Map.put(recursos, codigo, recurso)}
    end
  end

  defp leer_recurso(_campos, _recursos), do: {:error, "formato no válido"}

  defp leer_movimiento([codigo, fecha, tipo, cantidad, motivo], recursos) do
    with {:ok, cantidad_entera} <- Almacen.entero(cantidad) do
      case Map.fetch(recursos, codigo) do
        {:ok,%Recurso{} = recurso} ->
          movimiento = {fecha, String.to_atom(tipo), cantidad_entera, motivo}
          nuevo = %Recurso{recurso | historial: [movimiento | recurso.historial]}
          {:ok, Map.put(recursos, codigo, nuevo)}

        :error ->
          {:error, "no existe el recurso #{codigo}"}
      end
    end
  end

  defp leer_movimiento(_campos, _recursos), do: {:error, "formato no válido"}
end
