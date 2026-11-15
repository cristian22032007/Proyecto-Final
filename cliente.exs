defmodule Cliente do
  @servidor :servidor@localhost

  def main do
    Util2.mostrar("=== NODO CLIENTE ===", :mensaje)
    Util2.mostrar("Nodo: #{node()}", :mensaje)

    case Node.connect(@servidor) do
      true ->
        Util2.mostrar("Conectado a #{@servidor}. Escriba exit para salir.\n", :mensaje)
        ciclo(nil)

      false ->
        Util2.mostrar("ERROR: no se pudo conectar con #{@servidor}. ¿Está corriendo el servidor?", :error)

      :ignored ->
        Util2.mostrar("ERROR: este nodo no se inició como distribuido (falta --sname).", :error)
    end
  end

  # La sesión viaja como argumento de la recursión, igual que en Cli
  defp ciclo(sesion) do
    linea = Util2.ingresar(prompt(sesion), :texto)

    # La línea se procesa en el nodo servidor
    case :erpc.call(@servidor, Cli, :procesar_linea, [sesion, linea]) do
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

  defp cerrar_sesion(%Usuario{usuario: usuario}) do
    :erpc.call(@servidor, ServidorUsuarios, :disconnect, [usuario])
  end
end

Cliente.main()
