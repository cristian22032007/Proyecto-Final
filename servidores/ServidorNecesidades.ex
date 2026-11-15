defmodule ServidorNecesidades do
  use GenServer

  # -----------------------------------
  # API pública
  # -----------------------------------

  def start_link(_opciones \\ []) do
    estado_inicial = %{necesidades: %{}, contador: 0}
    GenServer.start_link(__MODULE__, estado_inicial, name: __MODULE__)
  end

  def registrar(tipo, cantidad, prioridad, zona, descripcion, responsable) do
    GenServer.call(
      __MODULE__,
      {:registrar, tipo, cantidad, prioridad, zona, descripcion, responsable}
    )
  end

  def consultar(id), do: GenServer.call(__MODULE__, {:consultar, id})

  # Filtros opcionales (keyword): zona: "centro", tipo: :agua, prioridad: :critica, estado: :pendiente
  def listar(filtros \\ []), do: GenServer.call(__MODULE__, {:listar, filtros})

  def pendientes, do: listar(estado: :pendiente)

  def asignar(id, codigo_recurso), do: GenServer.call(__MODULE__, {:asignar, id, codigo_recurso})

  def cambiar_estado(id, nuevo_estado),
    do: GenServer.call(__MODULE__, {:cambiar_estado, id, nuevo_estado})

  # -----------------------------------
  # Callbacks
  # -----------------------------------

  @impl true
  def init(_estado), do: {:ok, cargar()}

  @impl true
  def handle_call(mensaje, desde, estado) do
    {:reply, respuesta, nuevo} = procesar(mensaje, desde, estado)
    if nuevo != estado, do:  if(nuevo != estado, do: guardar(nuevo))
    {:reply, respuesta, nuevo}
  end


  defp procesar(
         {:registrar, tipo, cantidad, prioridad, zona, descripcion, responsable},
         _from,
         estado
       ) do
    id = generar_id(estado.contador + 1)

    case Necesidad.crear(id, tipo, cantidad, prioridad, zona, descripcion, responsable) do
      {:ok, necesidad} ->
        nuevo = %{estado | contador: estado.contador + 1} |> guardar(necesidad)
        {:reply, {:ok, necesidad}, nuevo}

      {:error, razon} ->
        {:reply, {:error, razon}, estado}
    end
  end

  defp procesar({:consultar, id}, _from, estado) do
    {:reply, buscar(estado.necesidades, id), estado}
  end

  defp procesar({:listar, filtros}, _from, estado) do
    lista =
      estado.necesidades
      |> Map.values()
      |> filtrar(filtros)
      |> Util2.ordenar(:asc, &{Necesidad.valor_prioridad(&1.prioridad), &1.id})

    {:reply, lista, estado}
  end

  # La necesidad se valida primero (función pura). Solo si la transición es válida
  # se descuenta del inventario, y solo si el descuento funciona se guarda el cambio.
  defp procesar({:asignar, id, codigo_recurso}, _from, estado) do
    with {:ok, necesidad} <- buscar(estado.necesidades, id),
         {:ok, asignada} <- Necesidad.asignar(necesidad, codigo_recurso),
         {:ok, recurso} <- ServidorRecursos.consultar(codigo_recurso),
         :ok <- validar_tipo(necesidad, recurso),
         {:ok, _recurso} <-
           ServidorRecursos.salida(codigo_recurso, necesidad.cantidad, "necesidad #{id}") do
      {:reply, {:ok, asignada}, guardar(estado, asignada)}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  defp procesar({:cambiar_estado, id, nuevo_estado}, _from, estado) do
    with {:ok, necesidad} <- buscar(estado.necesidades, id),
         {:ok, nueva} <- Necesidad.cambiar_estado(necesidad, nuevo_estado) do
      devolver_recurso(necesidad, nuevo_estado)
      {:reply, {:ok, nueva}, guardar(estado, nueva)}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  # -----------------------------------
  # Funciones privadas
  # -----------------------------------

  defp generar_id(numero) do
    "N" <> (numero |> Integer.to_string() |> String.pad_leading(3, "0"))
  end

  defp guardar(estado, necesidad) do
    %{estado | necesidades: Map.put(estado.necesidades, necesidad.id, necesidad)}
  end

  defp buscar(necesidades, id) do
    case Map.fetch(necesidades, id) do
      {:ok, necesidad} -> {:ok, necesidad}
      :error -> {:error, "No existe la necesidad #{id}"}
    end
  end

  defp filtrar(lista, filtros) do
    Enum.reduce(filtros, lista, fn
      {:zona, zona}, acc -> Util2.aplicar_filtro(acc, &(&1.zona == zona))
      {:tipo, tipo}, acc -> Util2.aplicar_filtro(acc, &(&1.tipo == tipo))
      {:prioridad, prioridad}, acc -> Util2.aplicar_filtro(acc, &(&1.prioridad == prioridad))
      {:estado, estado}, acc -> Util2.aplicar_filtro(acc, &(&1.estado == estado))
      _otro, acc -> acc
    end)
  end

  defp validar_tipo(%Necesidad{tipo: :otra}, _recurso), do: :ok

  defp validar_tipo(%Necesidad{tipo: tipo}, %Recurso{nombre: nombre}) do
    if Atom.to_string(tipo) == nombre do
      :ok
    else
      {:error, "El recurso #{nombre} no corresponde al tipo de necesidad #{tipo}"}
    end
  end

  # Si se cancela una necesidad que ya tenía recurso asignado, se devuelve al inventario
  defp devolver_recurso(%Necesidad{recurso: codigo, cantidad: cantidad, id: id}, :cancelada)
       when codigo != nil do
    ServidorRecursos.entrada(codigo, cantidad, "devolución por cancelación de #{id}")
  end

  defp devolver_recurso(_necesidad, _nuevo_estado), do: :ok

    # -----------------------------------
  # Persistencia: necesidades.txt y cambios_necesidades.txt
  # -----------------------------------

  defp guardar(estado) do
    lista = estado.necesidades |> Map.values() |> Util2.ordenar(:asc, & &1.id)

    filas =
      Enum.map(lista, fn n ->
        [n.id, n.tipo, n.descripcion, n.cantidad, n.zona, n.prioridad, n.responsable, n.estado, n.recurso]
      end)

    # Los cambios de estado se guardan del más antiguo al más reciente
    cambios =
      Enum.flat_map(lista, fn n ->
        n.historial
        |> Enum.reverse()
        |> Enum.map(fn {fecha, anterior, nuevo} -> [n.id, fecha, anterior, nuevo] end)
      end)

    Almacen.guardar("necesidades.txt", filas)
    Almacen.guardar("cambios_necesidades.txt", cambios)
  end

  defp cargar do
    estado =
      %{necesidades: %{}, contador: 0}
      |> Almacen.cargar("necesidades.txt", &leer_necesidad/2)
      |> Almacen.cargar("cambios_necesidades.txt", &leer_cambio/2)

    # Los IDs son consecutivos: el contador es la cantidad de necesidades
    %{estado | contador: map_size(estado.necesidades)}
  end

  defp leer_necesidad([id, tipo, descripcion, cantidad, zona, prioridad, responsable, estado_necesidad, recurso], estado) do
    with {:ok, tipo_atomo} <- Necesidad.convertir_tipo(tipo),
         {:ok, prioridad_atomo} <- Necesidad.convertir_prioridad(prioridad),
         {:ok, estado_atomo} <- Necesidad.convertir_estado(estado_necesidad),
         {:ok, cantidad_entera} <- Almacen.entero(cantidad) do
      necesidad = %Necesidad{
        id: id,
        tipo: tipo_atomo,
        descripcion: descripcion,
        cantidad: cantidad_entera,
        zona: zona,
        prioridad: prioridad_atomo,
        responsable: responsable,
        estado: estado_atomo,
        recurso: if(recurso == "", do: nil, else: recurso)
      }

      {:ok, %{estado | necesidades: Map.put(estado.necesidades, id, necesidad)}}
    end
  end

  defp leer_necesidad(_campos, _estado), do: {:error, "formato no válido"}

  defp leer_cambio([id, fecha, anterior, nuevo], estado) do
    with {:ok, anterior_atomo} <- Necesidad.convertir_estado(anterior),
         {:ok, nuevo_atomo} <- Necesidad.convertir_estado(nuevo),
         {:ok, %Necesidad{} = necesidad} <- buscar(estado.necesidades, id) do
      cambio = {fecha, anterior_atomo, nuevo_atomo}
      actualizada = %Necesidad{necesidad | historial: [cambio | necesidad.historial]}
      {:ok, %{estado | necesidades: Map.put(estado.necesidades, id, actualizada)}}
    end
  end

  defp leer_cambio(_campos, _estado), do: {:error, "formato no válido"}

end
