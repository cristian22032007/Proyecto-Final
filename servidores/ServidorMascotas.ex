defmodule ServidorMascotas do
  use GenServer

  # -----------------------------------
  # API pública
  # -----------------------------------

  def start_link(_opciones \\ []) do
    estado_inicial = %{mascotas: %{}, contador: 0, coincidencias: []}
    GenServer.start_link(__MODULE__, estado_inicial, name: __MODULE__)
  end

  def reportar(tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto) do
    GenServer.call(
      __MODULE__,
      {:reportar, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto}
    )
  end

  def consultar(id), do: GenServer.call(__MODULE__, {:consultar, id})

  # Filtros opcionales (keyword): especie: "perro", zona: "zona_norte", estado: :activa, tipo: :perdida
  def buscar(filtros \\ []), do: GenServer.call(__MODULE__, {:buscar, filtros})

  # Calcula las posibles coincidencias y marca ambos reportes como "posible coincidencia"
  def buscar_coincidencias, do: GenServer.call(__MODULE__, :buscar_coincidencias)

  def confirmar_coincidencia(id_perdida, id_encontrada),
    do: GenServer.call(__MODULE__, {:confirmar, id_perdida, id_encontrada})

  def listar_coincidencias, do: GenServer.call(__MODULE__, :listar_coincidencias)

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
         {:reportar, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto},
         _from,
         estado
       ) do
    id = generar_id(estado.contador + 1)

    case Mascota.crear(id, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto) do
      {:ok, mascota} ->
        nuevo = %{
          estado
          | contador: estado.contador + 1,
            mascotas: Map.put(estado.mascotas, id, mascota)
        }

        {:reply, {:ok, mascota}, nuevo}

      {:error, razon} ->
        {:reply, {:error, razon}, estado}
    end
  end

  defp procesar({:consultar, id}, _from, estado) do
    {:reply, buscar_mascota(estado.mascotas, id), estado}
  end

  defp procesar({:buscar, filtros}, _from, estado) do
    lista =
      estado.mascotas
      |> Map.values()
      |> filtrar(filtros)
      |> Util2.ordenar(:asc, & &1.id)

    {:reply, lista, estado}
  end

  defp procesar(:buscar_coincidencias, _from, estado) do
    candidatas =
      for perdida <- abiertas(estado.mascotas, :perdida),
          encontrada <- abiertas(estado.mascotas, :encontrada),
          puntaje = Mascota.calcular_similitud(perdida, encontrada),
          puntaje >= Mascota.umbral(),
          do: {perdida.id, encontrada.id, puntaje}

    ordenadas = Util2.ordenar(candidatas, :desc, fn {_p, _e, puntaje} -> puntaje end)

    mascotas =
      Enum.reduce(ordenadas, estado.mascotas, fn {id_p, id_e, _puntaje}, acumulado ->
        acumulado
        |> marcar_posible(id_p)
        |> marcar_posible(id_e)
      end)

    resultado =
      Enum.map(ordenadas, fn {id_p, id_e, puntaje} ->
        {Map.fetch!(mascotas, id_p), Map.fetch!(mascotas, id_e), puntaje}
      end)

    {:reply, resultado, %{estado | mascotas: mascotas}}
  end

  # Todo se valida con funciones puras y el estado solo se guarda si ambos
  # cierres salen {:ok, ...}. Como el GenServer atiende un mensaje a la vez,
  # un mismo reporte nunca se resuelve dos veces.
  defp procesar({:confirmar, id_perdida, id_encontrada}, _from, estado) do
    with {:ok, perdida} <- buscar_mascota(estado.mascotas, id_perdida),
         {:ok, encontrada} <- buscar_mascota(estado.mascotas, id_encontrada),
         :ok <- validar_tipos(perdida, encontrada),
         :ok <- validar_especie(perdida, encontrada),
         {:ok, perdida_resuelta} <- Mascota.resolver(perdida, id_encontrada),
         {:ok, encontrada_resuelta} <- Mascota.resolver(encontrada, id_perdida) do
      puntaje = Mascota.calcular_similitud(perdida, encontrada)
      registro = {DateTime.utc_now() |> DateTime.to_string(), id_perdida, id_encontrada, puntaje}

      nuevo = %{
        estado
        | mascotas:
            estado.mascotas
            |> Map.put(id_perdida, perdida_resuelta)
            |> Map.put(id_encontrada, encontrada_resuelta),
          coincidencias: [registro | estado.coincidencias]
      }

      {:reply, {:ok, {perdida_resuelta, encontrada_resuelta, puntaje}}, nuevo}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  defp procesar(:listar_coincidencias, _from, estado) do
    {:reply, Enum.reverse(estado.coincidencias), estado}
  end

  # -----------------------------------
  # Funciones privadas
  # -----------------------------------

  defp generar_id(numero) do
    "MA" <> (numero |> Integer.to_string() |> String.pad_leading(3, "0"))
  end

  defp buscar_mascota(mascotas, id) do
    case Map.fetch(mascotas, id) do
      {:ok, mascota} -> {:ok, mascota}
      :error -> {:error, "No existe el reporte de mascota #{id}"}
    end
  end

  # Reportes de un tipo que todavía no están resueltos
  defp abiertas(mascotas, tipo) do
    mascotas
    |> Map.values()
    |> Util2.aplicar_filtro(&(&1.tipo == tipo and &1.estado in [:activa, :posible_coincidencia]))
    |> Util2.ordenar(:asc, & &1.id)
  end

  # Solo pasa de "activa" a "posible coincidencia"; si ya lo está, no cambia
  defp marcar_posible(mascotas, id) do
    case Map.fetch!(mascotas, id) do
      %Mascota{estado: :activa} = mascota ->
        {:ok, marcada} = Mascota.cambiar_estado(mascota, :posible_coincidencia)
        Map.put(mascotas, id, marcada)

      _otra ->
        mascotas
    end
  end

  defp validar_tipos(%Mascota{tipo: :perdida}, %Mascota{tipo: :encontrada}), do: :ok

  defp validar_tipos(_, _) do
    {:error,
     "La coincidencia debe ser entre un reporte perdido (primero) y uno encontrado (segundo)"}
  end

  defp validar_especie(%Mascota{especie: especie}, %Mascota{especie: especie}), do: :ok
  defp validar_especie(_, _), do: {:error, "Los reportes no son de la misma especie"}

  defp filtrar(lista, filtros) do
    Enum.reduce(filtros, lista, fn
      {:especie, especie}, acc ->
        Util2.aplicar_filtro(acc, &(&1.especie == String.downcase(especie)))

      {:zona, zona}, acc ->
        Util2.aplicar_filtro(acc, &(&1.zona == zona))

      {:estado, estado}, acc ->
        Util2.aplicar_filtro(acc, &(&1.estado == estado))

      {:tipo, tipo}, acc ->
        Util2.aplicar_filtro(acc, &(&1.tipo == tipo))

      _otro, acc ->
        acc
    end)
  end
  # -----------------------------------
  # Persistencia: mascotas.txt y coincidencias.txt
  # -----------------------------------

  defp guardar(estado) do
    lista = estado.mascotas |> Map.values() |> Util2.ordenar(:asc, & &1.id)

    filas =
      Enum.map(lista, fn m ->
        [m.id, m.tipo, m.especie, m.nombre, m.caracteristicas, m.color, m.tamano, m.zona, m.contacto, m.estado, m.coincidencia]
      end)

    # Las coincidencias se guardan de la más antigua a la más reciente
    coincidencias =
      estado.coincidencias
      |> Enum.reverse()
      |> Enum.map(fn {fecha, id_perdida, id_encontrada, puntaje} ->
        [fecha, id_perdida, id_encontrada, puntaje]
      end)

    Almacen.guardar("mascotas.txt", filas)
    Almacen.guardar("coincidencias.txt", coincidencias)
  end

  defp cargar do
    estado =
      %{mascotas: %{}, contador: 0, coincidencias: []}
      |> Almacen.cargar("mascotas.txt", &leer_mascota/2)
      |> Almacen.cargar("coincidencias.txt", &leer_coincidencia/2)

    %{estado | contador: map_size(estado.mascotas)}
  end

  defp leer_mascota([id, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto, estado_reporte, coincidencia], estado) do
    with {:ok, tipo_atomo} <- Mascota.convertir_tipo(tipo),
         {:ok, tamano_atomo} <- Mascota.convertir_tamano(tamano),
         {:ok, estado_atomo} <- Mascota.convertir_estado(estado_reporte) do
      mascota = %Mascota{
        id: id,
        tipo: tipo_atomo,
        especie: especie,
        nombre: nombre,
        caracteristicas: caracteristicas,
        color: color,
        tamano: tamano_atomo,
        zona: zona,
        contacto: contacto,
        estado: estado_atomo,
        coincidencia: if(coincidencia == "", do: nil, else: coincidencia)
      }

      {:ok, %{estado | mascotas: Map.put(estado.mascotas, id, mascota)}}
    end
  end

  defp leer_mascota(_campos, _estado), do: {:error, "formato no válido"}

  defp leer_coincidencia([fecha, id_perdida, id_encontrada, puntaje], estado) do
    with {:ok, puntaje_entero} <- Almacen.entero(puntaje) do
      registro = {fecha, id_perdida, id_encontrada, puntaje_entero}
      {:ok, %{estado | coincidencias: [registro | estado.coincidencias]}}
    end
  end

  defp leer_coincidencia(_campos, _estado), do: {:error, "formato no válido"}
end
