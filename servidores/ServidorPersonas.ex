defmodule ServidorPersonas do
  use GenServer

  # -----------------------------------
  # API pública
  # -----------------------------------

  def start_link(_opciones \\ []) do
    estado_inicial = %{personas: %{}, mensajes: %{}, contador_personas: 0, contador_mensajes: 0}
    GenServer.start_link(__MODULE__, estado_inicial, name: __MODULE__)
  end

  def registrar(documento, nombre, edad, zona, estado \\ "reportada") do
    GenServer.call(__MODULE__, {:registrar, documento, nombre, edad, zona, estado})
  end

  def consultar(documento), do: GenServer.call(__MODULE__, {:consultar, documento})

  # Filtros opcionales (keyword): nombre: "ana", documento: "1001", zona: "norte", estado: :localizada
  def buscar(filtros \\ []), do: GenServer.call(__MODULE__, {:buscar, filtros})

  def cambiar_estado(documento, nuevo_estado),
    do: GenServer.call(__MODULE__, {:cambiar_estado, documento, nuevo_estado})

  def historial(documento), do: GenServer.call(__MODULE__, {:historial, documento})

  def contar_por_estado, do: GenServer.call(__MODULE__, :contar_por_estado)

  def enviar_mensaje(remitente, documento, contenido),
    do: GenServer.call(__MODULE__, {:enviar_mensaje, remitente, documento, contenido})

  def listar_mensajes(documento), do: GenServer.call(__MODULE__, {:listar_mensajes, documento})

  def marcar_mensaje(id, estado), do: GenServer.call(__MODULE__, {:marcar_mensaje, id, estado})

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


  defp procesar({:registrar, documento, nombre, edad, zona, estado_persona}, _from, estado) do
    id = generar_id("P", estado.contador_personas + 1)

    with false <- Map.has_key?(estado.personas, documento),
         {:ok, persona} <- Persona.crear(id, documento, nombre, edad, zona, estado_persona) do
      nuevo = %{
        estado
        | contador_personas: estado.contador_personas + 1,
          personas: Map.put(estado.personas, documento, persona)
      }

      {:reply, {:ok, persona}, nuevo}
    else
      true -> {:reply, {:error, "Ya existe una persona con el documento #{documento}"}, estado}
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  defp procesar({:consultar, documento}, _from, estado) do
    {:reply, buscar_persona(estado.personas, documento), estado}
  end

  defp procesar({:buscar, filtros}, _from, estado) do
    lista =
      estado.personas
      |> Map.values()
      |> filtrar(filtros)
      |> Util2.ordenar(:asc, & &1.id)

    {:reply, lista, estado}
  end

  defp procesar({:cambiar_estado, documento, nuevo}, _from, estado) do
    with {:ok, persona} <- buscar_persona(estado.personas, documento),
         {:ok, actualizada} <- Persona.cambiar_estado(persona, nuevo) do
      nuevo_estado = %{estado | personas: Map.put(estado.personas, documento, actualizada)}
      {:reply, {:ok, actualizada}, nuevo_estado}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  defp procesar({:historial, documento}, _from, estado) do
    respuesta =
      case buscar_persona(estado.personas, documento) do
        {:ok, persona} -> {:ok, Enum.reverse(persona.historial)}
        error -> error
      end

    {:reply, respuesta, estado}
  end

  defp procesar(:contar_por_estado, _from, estado) do
    conteo = estado.personas |> Map.values() |> Enum.frequencies_by(& &1.estado)
    {:reply, conteo, estado}
  end

  defp procesar({:enviar_mensaje, remitente, documento, contenido}, _from, estado) do
    id = generar_id("M", estado.contador_mensajes + 1)

    with {:ok, _persona} <- buscar_persona(estado.personas, documento),
         {:ok, mensaje} <- Mensaje.crear(id, remitente, documento, contenido) do
      nuevo = %{
        estado
        | contador_mensajes: estado.contador_mensajes + 1,
          mensajes: Map.put(estado.mensajes, id, mensaje)
      }

      {:reply, {:ok, mensaje}, nuevo}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  defp procesar({:listar_mensajes, documento}, _from, estado) do
    lista =
      estado.mensajes
      |> Map.values()
      |> Util2.aplicar_filtro(&(&1.destinatario == documento))
      |> Util2.ordenar(:asc, & &1.id)

    {:reply, lista, estado}
  end

  defp procesar({:marcar_mensaje, id, nuevo}, _from, estado) do
    with {:ok, mensaje} <- buscar_mensaje(estado.mensajes, id),
         {:ok, actualizado} <- Mensaje.marcar(mensaje, nuevo) do
      nuevo_estado = %{estado | mensajes: Map.put(estado.mensajes, id, actualizado)}
      {:reply, {:ok, actualizado}, nuevo_estado}
    else
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  # -----------------------------------
  # Funciones privadas
  # -----------------------------------

  defp generar_id(prefijo, numero) do
    prefijo <> (numero |> Integer.to_string() |> String.pad_leading(3, "0"))
  end

  defp buscar_persona(personas, documento) do
    case Map.fetch(personas, documento) do
      {:ok, persona} -> {:ok, persona}
      :error -> {:error, "No existe la persona con documento #{documento}"}
    end
  end

  defp buscar_mensaje(mensajes, id) do
    case Map.fetch(mensajes, id) do
      {:ok, mensaje} -> {:ok, mensaje}
      :error -> {:error, "No existe el mensaje #{id}"}
    end
  end

  defp filtrar(lista, filtros) do
    Enum.reduce(filtros, lista, fn
      {:nombre, texto}, acc ->
        Util2.aplicar_filtro(acc, fn persona ->
          String.contains?(String.downcase(persona.nombre), String.downcase(texto))
        end)

      {:documento, documento}, acc -> Util2.aplicar_filtro(acc, &(&1.documento == documento))
      {:zona, zona}, acc -> Util2.aplicar_filtro(acc, &(&1.zona == zona))
      {:estado, estado}, acc -> Util2.aplicar_filtro(acc, &(&1.estado == estado))
      _otro, acc -> acc
    end)
  end
  # -----------------------------------
  # Persistencia: personas.txt, cambios_personas.txt y mensajes.txt
  # -----------------------------------

  defp guardar(estado) do
    personas = estado.personas |> Map.values() |> Util2.ordenar(:asc, & &1.id)
    mensajes = estado.mensajes |> Map.values() |> Util2.ordenar(:asc, & &1.id)

    filas_personas =
      Enum.map(personas, fn p -> [p.id, p.documento, p.nombre, p.edad, p.zona, p.estado] end)

    # Los cambios se guardan del más antiguo al más reciente (nil queda como campo vacío)
    filas_cambios =
      Enum.flat_map(personas, fn p ->
        p.historial
        |> Enum.reverse()
        |> Enum.map(fn {fecha, anterior, nuevo} -> [p.documento, fecha, anterior, nuevo] end)
      end)

    filas_mensajes =
      Enum.map(mensajes, fn m -> [m.id, m.fecha, m.remitente, m.destinatario, m.contenido, m.estado] end)

    Almacen.guardar("personas.txt", filas_personas)
    Almacen.guardar("cambios_personas.txt", filas_cambios)
    Almacen.guardar("mensajes.txt", filas_mensajes)
  end

  defp cargar do
    estado =
      %{personas: %{}, mensajes: %{}, contador_personas: 0, contador_mensajes: 0}
      |> Almacen.cargar("personas.txt", &leer_persona/2)
      |> Almacen.cargar("cambios_personas.txt", &leer_cambio/2)
      |> Almacen.cargar("mensajes.txt", &leer_mensaje/2)

    %{
      estado
      | contador_personas: map_size(estado.personas),
        contador_mensajes: map_size(estado.mensajes)
    }
  end

  defp leer_persona([id, documento, nombre, edad, zona, estado_persona], estado) do
    with {:ok, edad_entera} <- Almacen.entero(edad),
         {:ok, estado_atomo} <- Persona.convertir_estado(estado_persona) do
      persona = %Persona{
        id: id,
        documento: documento,
        nombre: nombre,
        edad: edad_entera,
        zona: zona,
        estado: estado_atomo
      }

      {:ok, %{estado | personas: Map.put(estado.personas, documento, persona)}}
    end
  end

  defp leer_persona(_campos, _estado), do: {:error, "formato no válido"}

  defp leer_cambio([documento, fecha, anterior, nuevo], estado) do
    with {:ok, anterior_atomo} <- leer_estado_anterior(anterior),
         {:ok, nuevo_atomo} <- Persona.convertir_estado(nuevo),
         {:ok, %Persona{} = persona} <- buscar_persona(estado.personas, documento) do
      cambio = {fecha, anterior_atomo, nuevo_atomo}
      actualizada = %Persona{persona | historial: [cambio | persona.historial]}
      {:ok, %{estado | personas: Map.put(estado.personas, documento, actualizada)}}
    end
  end

  defp leer_cambio(_campos, _estado), do: {:error, "formato no válido"}

  # El primer cambio de una persona no tiene estado anterior
  defp leer_estado_anterior(""), do: {:ok, nil}
  defp leer_estado_anterior(texto), do: Persona.convertir_estado(texto)

  defp leer_mensaje([id, fecha, remitente, destinatario, contenido, estado_mensaje], estado) do
    with {:ok, estado_atomo} <- Mensaje.convertir_estado(estado_mensaje) do
      mensaje = %Mensaje{
        id: id,
        fecha: fecha,
        remitente: remitente,
        destinatario: destinatario,
        contenido: contenido,
        estado: estado_atomo
      }

      {:ok, %{estado | mensajes: Map.put(estado.mensajes, id, mensaje)}}
    end
  end

  defp leer_mensaje(_campos, _estado), do: {:error, "formato no válido"}
end
