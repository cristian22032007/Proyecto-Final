defmodule PruebaUsuarios do
  def main do
    Almacen.usar_directorio_temporal()
    {:ok, _pid} = ServidorUsuarios.start_link()

    ServidorUsuarios.connect("laura", "1234", "coordinador", "centro") |> IO.inspect()
    ServidorUsuarios.connect("laura", "mala", "coordinador", "centro") |> IO.inspect()
    ServidorUsuarios.connect("laura", "1234", "coordinador", "centro") |> IO.inspect()
    ServidorUsuarios.connect("pedro", "abc", "invitado", "norte") |> IO.inspect()

    ServidorUsuarios.autorizar("laura", :asignar_recurso) |> IO.inspect()

    ServidorUsuarios.connect("ana", "xyz", "ciudadano", "centro") |> IO.inspect()
    ServidorUsuarios.autorizar("ana", :asignar_recurso) |> IO.inspect()

    ServidorUsuarios.disconnect("laura") |> IO.inspect()
    ServidorUsuarios.listar_actividad("laura") |> IO.inspect()
  end
end

PruebaUsuarios.main()
