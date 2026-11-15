defmodule ServidorUsuarios do
  use GenServer

  # -----------------------------------
  # API pública (lo que usa el resto del sistema)
  # -----------------------------------

  def start_link(_opciones \\ []) do
    estado_inicial = %{usuarios: %{}, conectados: MapSet.new(), actividad: []}
    GenServer.start_link(__MODULE__, estado_inicial, name: __MODULE__)
  end

  def connect(usuario, contrasena, tipo, zona) do
    GenServer.call(__MODULE__, {:connect, usuario, contrasena, tipo, zona})
  end

  def disconnect(usuario), do: GenServer.call(__MODULE__, {:disconnect, usuario})

  def autorizar(usuario, accion), do: GenServer.call(__MODULE__, {:autorizar, usuario, accion})

  def registrar_actividad(usuario, accion) do
    GenServer.cast(__MODULE__, {:actividad, usuario, accion})
  end

  def listar_actividad(usuario), do: GenServer.call(__MODULE__, {:listar_actividad, usuario})

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


  defp procesar({:connect, usuario, contrasena, tipo, zona}, _from, estado) do
    case Map.fetch(estado.usuarios, usuario) do
      :error -> registrar_y_conectar(estado, usuario, contrasena, tipo, zona)
      {:ok, existente} -> validar_y_conectar(estado, existente, contrasena)
    end
  end

  defp procesar({:disconnect, usuario}, _from, estado) do
    if MapSet.member?(estado.conectados, usuario) do
      nuevo = %{estado | conectados: MapSet.delete(estado.conectados, usuario)}

      {:reply, {:ok, "Usuario #{usuario} desconectado"},
       agregar_actividad(nuevo, usuario, "disconnect")}
    else
      {:reply, {:error, "El usuario #{usuario} no está conectado"}, estado}
    end
  end

  defp procesar({:autorizar, usuario, accion}, _from, estado) do
    respuesta =
      with true <- MapSet.member?(estado.conectados, usuario),
           {:ok, datos} <- Map.fetch(estado.usuarios, usuario),
           true <- Usuario.tiene_permiso?(datos, accion) do
        {:ok, datos}
      else
        _ -> {:error, "Usuario no conectado o sin permiso para #{accion}"}
      end

    {:reply, respuesta, estado}
  end

  defp procesar({:listar_actividad, usuario}, _from, estado) do
    actividad = Enum.filter(estado.actividad, fn {_fecha, u, _accion} -> u == usuario end)
    {:reply, Enum.reverse(actividad), estado}
  end

  def procesar_cast({:actividad, usuario, accion}, estado) do
    {:noreply, agregar_actividad(estado, usuario, accion)}
  end

  @impl true
  def handle_cast(mensaje, estado) do
    {:noreply, nuevo} = procesar_cast(mensaje, estado)
    if nuevo != estado, do:  if(nuevo != estado, do: guardar(nuevo))
    {:noreply, nuevo}
  end

  # -----------------------------------
  # Funciones privadas
  # -----------------------------------

  # Si el usuario no existe se registra automáticamente
  defp registrar_y_conectar(estado, usuario, contrasena, tipo, zona) do
    case Usuario.crear(usuario, contrasena, usuario, tipo, zona) do
      {:ok, nuevo} ->
        nuevo_estado =
          %{
            estado
            | usuarios: Map.put(estado.usuarios, usuario, nuevo),
              conectados: MapSet.put(estado.conectados, usuario)
          }
          |> agregar_actividad(usuario, "connect (registro automático)")

        {:reply, {:ok, "Usuario #{usuario} registrado y conectado"}, nuevo_estado}

      {:error, razon} ->
        {:reply, {:error, razon}, estado}
    end
  end

  # Si ya existe se valida la contraseña
  defp validar_y_conectar(estado, existente, contrasena) do
    if Usuario.validar_contrasena(existente, contrasena) do
      nuevo_estado =
        %{estado | conectados: MapSet.put(estado.conectados, existente.usuario)}
        |> agregar_actividad(existente.usuario, "connect")

      {:reply, {:ok, "Usuario #{existente.usuario} conectado"}, nuevo_estado}
    else
      {:reply, {:error, "Contraseña incorrecta"}, estado}
    end
  end

  defp agregar_actividad(estado, usuario, accion) do
    registro = {DateTime.utc_now() |> DateTime.to_string(), usuario, accion}
    %{estado | actividad: [registro | estado.actividad]}
  end
    # -----------------------------------
  # Persistencia: usuarios.txt y actividad.txt
  # -----------------------------------

  defp guardar(estado) do
    usuarios =
      estado.usuarios
      |> Map.values()
      |> Util2.ordenar(:asc, & &1.usuario)
      |> Enum.map(fn u -> [u.usuario, u.contrasena, u.nombre_completo, u.tipo, u.zona] end)

    # La actividad se guarda de la más antigua a la más reciente
    actividad =
      estado.actividad
      |> Enum.reverse()
      |> Enum.map(fn {fecha, usuario, accion} -> [fecha, usuario, accion] end)

    Almacen.guardar("usuarios.txt", usuarios)
    Almacen.guardar("actividad.txt", actividad)
  end

  defp cargar do
    %{usuarios: %{}, conectados: MapSet.new(), actividad: []}
    |> Almacen.cargar("usuarios.txt", &leer_usuario/2)
    |> Almacen.cargar("actividad.txt", &leer_actividad/2)
  end

  # La contraseña ya está cifrada: se carga tal cual
  defp leer_usuario([usuario, contrasena, nombre, tipo, zona], estado) do
    with {:ok, tipo_atomo} <- Usuario.convertir_tipo(tipo) do
      datos = %Usuario{
        usuario: usuario,
        contrasena: contrasena,
        nombre_completo: nombre,
        tipo: tipo_atomo,
        zona: zona
      }

      {:ok, %{estado | usuarios: Map.put(estado.usuarios, usuario, datos)}}
    end
  end

  defp leer_usuario(_campos, _estado), do: {:error, "formato no válido"}

  defp leer_actividad([fecha, usuario, accion], estado) do
    {:ok, %{estado | actividad: [{fecha, usuario, accion} | estado.actividad]}}
  end

  defp leer_actividad(_campos, _estado), do: {:error, "formato no válido"}

end
