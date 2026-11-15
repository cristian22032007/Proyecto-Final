defmodule Persona do
  defstruct id: "",
            documento: "",
            nombre: "",
            edad: 0,
            zona: "",
            estado: :sin_informacion,
            historial: []

  @estados %{
    "sin_informacion" => :sin_informacion,
    "reportada" => :reportada,
    "localizada" => :localizada,
    "trasladada" => :trasladada,
    "en_albergue" => :en_albergue,
    "reunificada" => :reunificada
  }

  # Transiciones válidas de estado ("reunificada" es un estado final)
  @transiciones %{
    sin_informacion: [:reportada, :localizada, :trasladada, :en_albergue],
    reportada: [:localizada, :trasladada, :en_albergue, :reunificada],
    localizada: [:trasladada, :en_albergue, :reunificada],
    trasladada: [:localizada, :en_albergue, :reunificada],
    en_albergue: [:localizada, :trasladada, :reunificada],
    reunificada: []
  }


  # Creación


  def crear(id, documento, nombre, edad, zona, estado \\ "reportada") do
    with :ok <- validar_texto(documento, "documento"),
         :ok <- validar_texto(nombre, "nombre"),
         :ok <- validar_texto(zona, "zona"),
         :ok <- validar_edad(edad),
         {:ok, estado_atomo} <- convertir_estado(estado) do
      {:ok,
       %Persona{
         id: id,
         documento: documento,
         nombre: nombre,
         edad: edad,
         zona: zona,
         estado: estado_atomo,
         historial: [registrar_cambio(nil, estado_atomo)]
       }}
    end
  end


  # Estados


  def convertir_estado(estado) when is_atom(estado), do: convertir_estado(Atom.to_string(estado))

  def convertir_estado(estado) when is_binary(estado) do
    clave = estado |> String.trim() |> String.downcase() |> String.replace(" ", "_")

    case Map.fetch(@estados, clave) do
      {:ok, atomo} -> {:ok, atomo}
      :error -> {:error, "Estado de persona no válido: #{estado}"}
    end
  end

  def cambiar_estado(%Persona{documento: documento, estado: :reunificada}, _nuevo) do
    {:error, "La persona #{documento} ya está reunificada y no admite más cambios"}
  end

  def cambiar_estado(%Persona{estado: actual} = persona, nuevo) do
    with {:ok, nuevo_atomo} <- convertir_estado(nuevo) do
      if nuevo_atomo in Map.fetch!(@transiciones, actual) do
        {:ok,
         %Persona{
           persona
           | estado: nuevo_atomo,
             historial: [registrar_cambio(actual, nuevo_atomo) | persona.historial]
         }}
      else
        {:error, "Transición no válida: #{actual} -> #{nuevo_atomo}"}
      end
    end
  end

  defp registrar_cambio(anterior, nuevo) do
    {DateTime.utc_now() |> DateTime.to_string(), anterior, nuevo}
  end


  # Validaciones


  defp validar_texto(texto, campo) when is_binary(texto) do
    case String.trim(texto) do
      "" -> {:error, "El campo #{campo} no puede estar vacío"}
      _ -> :ok
    end
  end

  defp validar_texto(_, campo), do: {:error, "El campo #{campo} debe ser texto"}

  defp validar_edad(edad) when is_integer(edad) and edad >= 0 and edad <= 120, do: :ok
  defp validar_edad(_), do: {:error, "La edad debe ser un entero entre 0 y 120"}

  defimpl String.Chars, for: Persona do
    def to_string(%Persona{} = p) do
      "#{p.id} | #{p.documento} | #{p.nombre} | #{p.edad} años | #{p.zona} | #{p.estado}"
    end
  end
end
