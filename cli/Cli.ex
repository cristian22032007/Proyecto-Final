defmodule Cli do
  @moduledoc """
  Consola de comandos. Valida la sesión y el permiso del rol y delega
  cada comando en el módulo de su dominio. No guarda estado.
  """

  @uso_connect "connect usuario contraseña [tipo zona]"

  # comando => {módulo que lo ejecuta, permiso requerido, uso}
  @comandos %{
    "register_zone" => {CliZonas, :registrar_zona, "register_zone codigo nombre nivel [personas]"},
    "register_sector" => {CliZonas, :registrar_zona, "register_sector zona nombre nivel personas"},
    "register_point" => {CliZonas, :registrar_zona, "register_point zona sector nombre [atendidas]"},
    "zone_status" => {CliZonas, :consultar, "zone_status zona"},
    "register_need" => {CliNecesidades, :registrar_necesidad, "register_need tipo cantidad prioridad zona descripcion"},
    "list_needs" => {CliNecesidades, :consultar, "list_needs [zona=x] [tipo=x] [prioridad=x] [estado=x]"},
    "pending_needs" => {CliNecesidades, :consultar, "pending_needs"},
    "assign_resource" => {CliNecesidades, :asignar_recurso, "assign_resource idNecesidad codigoRecurso"},
    "change_need_status" => {CliNecesidades, :asignar_recurso, "change_need_status idNecesidad estado"},
    "register_resource" => {CliRecursos, :registrar_recurso, "register_resource codigo nombre cantidad unidad ubicacion"},
    "list_resources" => {CliRecursos, :consultar, "list_resources"},
    "availability" => {CliRecursos, :consultar, "availability nombre [ubicacion]"},
    "transfer_resource" => {CliRecursos, :transferir_recurso, "transfer_resource codigo origen destino cantidad"},
    "critical_resources" => {CliRecursos, :consultar, "critical_resources"},
    "report_person" => {CliPersonas, :reportar_persona, "report_person documento nombre edad zona [estado]"},
    "find_person" => {CliPersonas, :consultar, "find_person documento | find_person [nombre=x] [zona=x] [estado=x]"},
    "send_family_message" => {CliPersonas, :enviar_mensaje, "send_family_message documento mensaje"},
    "list_family_messages" => {CliPersonas, :consultar, "list_family_messages documento"},
    "mark_message" => {CliPersonas, :enviar_mensaje, "mark_message idMensaje pendiente|entregado"},
    "report_pet" => {CliMascotas, :reportar_mascota, "report_pet lost|found especie nombre color tamano zona contacto [caracteristicas]"},
    "match_pets" => {CliMascotas, :reportar_mascota, "match_pets"},
    "confirm_match" => {CliMascotas, :confirmar_coincidencia, "confirm_match idPerdida idEncontrada"},
    "list_pets" => {CliMascotas, :consultar, "list_pets [especie=x] [zona=x] [estado=x] [tipo=x]"},
    "register_shelter" => {CliAlbergues, :registrar_albergue, "register_shelter codigo nombre zona capacidad [ocupacion]"},
    "check_shelter" => {CliAlbergues, :consultar, "check_shelter codigo"},
    "register_entry" => {CliAlbergues, :registrar_ingreso, "register_entry codigoAlbergue documento"},
    "register_exit" => {CliAlbergues, :registrar_salida, "register_exit codigoAlbergue documento"},
    "shelter_resource" => {CliAlbergues, :registrar_albergue, "shelter_resource codigoAlbergue codigoRecurso"},
    "shelter_need" => {CliAlbergues, :registrar_albergue, "shelter_need codigoAlbergue idNecesidad"},
    "shelter_report" => {CliAlbergues, :consultar, "shelter_report [limite]"},
    "summary" => {CliResumen, :consultar, "summary"}
  }


  # Ciclo principal


  def main do
    Util2.mostrar(" SISTEMA DE GESTIÓN DE EMERGENCIAS ", :mensaje)
    Util2.mostrar("Escriba help para ver los comandos y exit para salir.\n", :mensaje)
    ciclo(nil)
  end

  # La sesión (nil o el usuario conectado) viaja como argumento de la recursión
  defp ciclo(sesion) do
    linea = Util2.ingresar(prompt(sesion), :texto)

    case procesar_linea(sesion, linea) do
      :salir ->
        cerrar_sesion(sesion)
        Util2.mostrar("Hasta pronto.", :mensaje)

      {:continuar, nueva_sesion} ->
        ciclo(nueva_sesion)
    end
  end

  defp prompt(nil), do: "emergencias> "
  defp prompt(%Usuario{usuario: usuario, zona: zona}), do: "#{usuario}@#{zona}> "

  defp cerrar_sesion(nil), do: :ok
  defp cerrar_sesion(%Usuario{usuario: usuario}), do: ServidorUsuarios.disconnect(usuario)

  # Pública para poder probar el CLI sin teclado
  def procesar_linea(sesion, linea) do
    case CliAnalisis.dividir(linea) do
      {:ok, []} ->
        {:continuar, sesion}

      {:ok, [comando | argumentos]} ->
        despachar(String.downcase(comando), argumentos, sesion, linea)

      {:error, razon} ->
        mostrar_resultado({:error, razon})
        {:continuar, sesion}
    end
  end

  def dividir(texto), do: CliAnalisis.dividir(texto)


  # Despacho


  defp despachar("exit", _argumentos, _sesion, _linea), do: :salir

  defp despachar("help", _argumentos, sesion, _linea) do
    mostrar_ayuda()
    {:continuar, sesion}
  end

  defp despachar("connect", argumentos, sesion, _linea), do: conectar(argumentos, sesion)

  defp despachar("disconnect", _argumentos, nil, _linea) do
    mostrar_resultado({:error, "No hay una sesión activa"})
    {:continuar, nil}
  end

  defp despachar("disconnect", _argumentos, %Usuario{usuario: usuario}, _linea) do
    usuario |> ServidorUsuarios.disconnect() |> mostrar_resultado()
    {:continuar, nil}
  end

  defp despachar(comando, argumentos, sesion, linea) do
    comando
    |> ejecutar_autorizado(argumentos, sesion, linea)
    |> mostrar_resultado()

    {:continuar, sesion}
  end

  # Comando conocido -> sesión activa -> permiso del rol -> ejecución
  defp ejecutar_autorizado(comando, argumentos, sesion, linea) do
    with {:ok, {modulo, accion, uso}} <- buscar_comando(comando),
         {:ok, usuario} <- verificar_sesion(sesion),
         {:ok, datos} <- ServidorUsuarios.autorizar(usuario.usuario, accion) do
      case modulo.ejecutar(comando, argumentos, datos) do
        {:ok, texto} ->
          ServidorUsuarios.registrar_actividad(usuario.usuario, linea)
          {:ok, texto}

        {:error, :uso} ->
          {:error, "Uso: " <> uso}

        error ->
          error
      end
    end
  end

  defp buscar_comando(comando) do
    case Map.fetch(@comandos, comando) do
      {:ok, datos} -> {:ok, datos}
      :error -> {:error, "Comando desconocido: #{comando} (escriba help)"}
    end
  end

  defp verificar_sesion(nil), do: {:error, "Debe conectarse primero: " <> @uso_connect}
  defp verificar_sesion(usuario), do: {:ok, usuario}


  # Conexión


  defp conectar(_argumentos, %Usuario{usuario: usuario} = sesion) do
    mostrar_resultado({:error, "Ya hay una sesión activa (#{usuario}). Use disconnect primero."})
    {:continuar, sesion}
  end

  defp conectar([usuario, contrasena | resto], nil) when length(resto) <= 2 do
    tipo = Enum.at(resto, 0, "")
    zona = Enum.at(resto, 1, "")

    with {:ok, mensaje} <- ServidorUsuarios.connect(usuario, contrasena, tipo, zona),
         {:ok, datos} <- ServidorUsuarios.autorizar(usuario, :consultar) do
      mostrar_resultado({:ok, mensaje})
      {:continuar, datos}
    else
      {:error, razon} ->
        mostrar_resultado({:error, razon})
        {:continuar, nil}
    end
  end

  defp conectar(_argumentos, nil) do
    mostrar_resultado({:error, "Uso: " <> @uso_connect})
    {:continuar, nil}
  end


  # Salida por pantalla


  defp mostrar_resultado({:ok, texto}), do: Util2.mostrar(texto, :mensaje)
  defp mostrar_resultado({:error, razon}), do: Util2.mostrar("Error: #{razon}", :mensaje)

  defp mostrar_ayuda do
    Util2.mostrar("Comandos disponibles:", :mensaje)
    Util2.mostrar("  #{@uso_connect}\n  disconnect\n  help\n  exit", :mensaje)

    @comandos
    |> Map.values()
    |> Util2.ordenar(:asc, fn {_modulo, _accion, uso} -> uso end)
    |> Util2.convertir_coleccion_mensaje(fn {_modulo, _accion, uso} -> "  #{uso}\n" end)
    |> Util2.mostrar(:mensaje)

    Util2.mostrar("Los textos con espacios van entre comillas dobles.", :mensaje)
  end
end
