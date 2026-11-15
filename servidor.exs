defmodule Servidor do
  def main do
    {:ok, _pid} = SupervisorEmergencias.start_link()
    Util2.mostrar("=== NODO SERVIDOR ===", :mensaje)
    Util2.mostrar("Nodo: #{node()}", :mensaje)
    Util2.mostrar("Servidores en marcha. Esperando clientes... (Ctrl+C dos veces para cerrar)", :mensaje)
    Process.sleep(:infinity)
  end
end

Servidor.main()
