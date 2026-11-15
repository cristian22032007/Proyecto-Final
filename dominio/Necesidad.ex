defmodule Necesidad do
  defstruct id: "",
            tipo: :otra,
            descripcion: "",
            cantidad: 0,
            zona: "",
            prioridad: :baja,
            responsable: "",
            estado: :pendiente,
            recurso: nil,
            historial: []

  @tipos [
    "agua", "alimentos", "medicamentos", "primeros_auxilios",
    "refugio", "transporte", "rescate", "otra"
  ]

  # Menor número = más urgente (se usa para ordenar la atención)
  @prioridades %{critica: 1, alta: 2, media: 3, baja: 4}

  @estados %{
    "pendiente" => :pendiente,
    "asignada" => :asignada,
    "en_atencion" => :en_atencion,
    "atendida" => :atendida,
    "cancelada" => :cancelada
  }

  # Transiciones válidas de estado
  @transiciones %{
    pendiente: [:asignada, :cancelada],
    asignada: [:en_atencion, :cancelada],
    en_atencion: [:atendida, :cancelada],
    atendida: [],
    cancelada: []
  }


  # Creación


  def crear(id, tipo, cantidad, prioridad, zona, descripcion, responsable) do
    with :ok <- validar_texto(zona, "zona"),
         :ok <- validar_texto(descripcion, "descripción"),
         :ok <- validar_texto(responsable, "responsable"),
         :ok <- validar_cantidad(cantidad),
         {:ok, tipo_atomo} <- convertir_tipo(tipo),
         {:ok, prioridad_atomo} <- convertir_prioridad(prioridad) do
      {:ok,
       %Necesidad{
         id: id,
         tipo: tipo_atomo,
         descripcion: descripcion,
         cantidad: cantidad,
         zona: zona,
         prioridad: prioridad_atomo,
         responsable: responsable
       }}
    end
  end


  # Conversiones


  def convertir_tipo(tipo) when is_atom(tipo), do: convertir_tipo(Atom.to_string(tipo))

  def convertir_tipo(tipo) when is_binary(tipo) do
    texto = String.downcase(tipo)

    if texto in @tipos do
      {:ok, String.to_atom(texto)}
    else
      {:error, "Tipo de necesidad no válido: #{tipo}"}
    end
  end

  def convertir_prioridad(prioridad) when is_atom(prioridad),
    do: convertir_prioridad(Atom.to_string(prioridad))

  def convertir_prioridad(prioridad) when is_binary(prioridad) do
    case String.downcase(prioridad) do
      p when p in ["critica", "crítica", "critico", "crítico"] -> {:ok, :critica}
      "alta" -> {:ok, :alta}
      "media" -> {:ok, :media}
      "baja" -> {:ok, :baja}
      _ -> {:error, "Prioridad no válida: #{prioridad}"}
    end
  end

  def convertir_estado(estado) when is_atom(estado), do: convertir_estado(Atom.to_string(estado))

  def convertir_estado(estado) when is_binary(estado) do
    case Map.fetch(@estados, String.downcase(estado)) do
      {:ok, atomo} -> {:ok, atomo}
      :error -> {:error, "Estado no válido: #{estado}"}
    end
  end

  def valor_prioridad(prioridad), do: Map.fetch!(@prioridades, prioridad)


  # Cambios de estado


  # Una necesidad cerrada ya no admite cambios
  def cambiar_estado(%Necesidad{id: id, estado: estado}, _nuevo)
      when estado in [:atendida, :cancelada] do
    {:error, "La necesidad #{id} ya está #{estado} y no admite más cambios"}
  end

  def cambiar_estado(%Necesidad{estado: actual} = necesidad, nuevo) do
    if nuevo in Map.fetch!(@transiciones, actual) do
      registro = {DateTime.utc_now() |> DateTime.to_string(), actual, nuevo}
      {:ok, %Necesidad{necesidad | estado: nuevo, historial: [registro | necesidad.historial]}}
    else
      {:error, "Transición no válida: #{actual} -> #{nuevo}"}
    end
  end

  def asignar(%Necesidad{} = necesidad, codigo_recurso) do
    with {:ok, asignada} <- cambiar_estado(necesidad, :asignada) do
      {:ok, %Necesidad{asignada | recurso: codigo_recurso}}
    end
  end


  # Validaciones


  defp validar_texto(texto, campo) when is_binary(texto) do
    case String.trim(texto) do
      "" -> {:error, "El campo #{campo} no puede estar vacío"}
      _ -> :ok
    end
  end

  defp validar_texto(_, campo), do: {:error, "El campo #{campo} debe ser texto"}

  defp validar_cantidad(cantidad) when is_integer(cantidad) and cantidad > 0, do: :ok
  defp validar_cantidad(_), do: {:error, "La cantidad debe ser un entero mayor que cero"}

  defimpl String.Chars, for: Necesidad do
    def to_string(%Necesidad{} = n) do
      "#{n.id} | #{n.tipo} x#{n.cantidad} | #{n.prioridad} | #{n.zona} | #{n.estado} | #{n.descripcion}"
    end
  end
end
