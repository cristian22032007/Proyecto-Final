defmodule Usuario do
  defstruct usuario: "", contrasena: "", nombre_completo: "", tipo: :ciudadano, zona: ""

  # Acciones permitidas por tipo de usuario (:todas = sin restricción)
  @permisos %{
    ciudadano: [:registrar_necesidad, :reportar_persona, :enviar_mensaje, :reportar_mascota, :consultar],
    voluntario: [
      :registrar_necesidad, :reportar_persona, :enviar_mensaje, :reportar_mascota,
      :consultar, :registrar_ingreso, :registrar_salida
    ],
    coordinador: [
      :registrar_necesidad, :reportar_persona, :enviar_mensaje, :reportar_mascota,
      :consultar, :registrar_ingreso, :registrar_salida, :registrar_zona,
      :registrar_recurso, :asignar_recurso, :transferir_recurso, :registrar_albergue,
      :confirmar_coincidencia
    ],
    administrador: :todas
  }

  def crear(usuario, contrasena, nombre_completo, tipo, zona) do
    with :ok <- validar_texto(usuario, "usuario"),
         :ok <- validar_texto(contrasena, "contraseña"),
         :ok <- validar_texto(nombre_completo, "nombre completo"),
         :ok <- validar_texto(zona, "zona"),
         {:ok, tipo_atomo} <- convertir_tipo(tipo) do
      {:ok,
       %Usuario{
         usuario: usuario,
         contrasena: cifrar(contrasena),
         nombre_completo: nombre_completo,
         tipo: tipo_atomo,
         zona: zona
       }}
    end
  end

  def convertir_tipo(texto) when is_binary(texto) do
    case String.downcase(texto) do
      "ciudadano" -> {:ok, :ciudadano}
      "voluntario" -> {:ok, :voluntario}
      "coordinador" -> {:ok, :coordinador}
      "administrador" -> {:ok, :administrador}
      _ -> {:error, "Tipo de usuario no válido: #{texto}"}
    end
  end

  def convertir_tipo(tipo) when is_atom(tipo), do: convertir_tipo(Atom.to_string(tipo))

  def validar_contrasena(%Usuario{contrasena: guardada}, intento) do
    guardada == cifrar(intento)
  end

  def tiene_permiso?(%Usuario{tipo: tipo}, accion) do
    case Map.fetch!(@permisos, tipo) do
      :todas -> true
      acciones -> accion in acciones
    end
  end

  defp validar_texto(texto, campo) when is_binary(texto) do
    case String.trim(texto) do
      "" -> {:error, "El campo #{campo} no puede estar vacío"}
      _ -> :ok
    end
  end

  defp validar_texto(_, campo), do: {:error, "El campo #{campo} debe ser texto"}

  defp cifrar(texto) do
    :crypto.hash(:sha256, texto) |> Base.encode16()
  end

  defimpl String.Chars, for: Usuario do
    def to_string(%Usuario{usuario: usuario, nombre_completo: nombre, tipo: tipo, zona: zona}) do
      "#{usuario} (#{nombre}), #{tipo}, zona #{zona}"
    end
  end
end
