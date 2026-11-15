defmodule Mensaje do
  defstruct id: "", fecha: "", remitente: "", destinatario: "", contenido: "", estado: :pendiente

  def crear(id, remitente, destinatario, contenido) do
    with :ok <- validar_texto(remitente, "remitente"),
         :ok <- validar_texto(destinatario, "destinatario"),
         :ok <- validar_texto(contenido, "contenido") do
      {:ok,
       %Mensaje{
         id: id,
         fecha: DateTime.utc_now() |> DateTime.to_string(),
         remitente: remitente,
         destinatario: destinatario,
         contenido: contenido
       }}
    end
  end

  def convertir_estado(estado) when is_atom(estado), do: convertir_estado(Atom.to_string(estado))

  def convertir_estado(estado) when is_binary(estado) do
    case String.downcase(String.trim(estado)) do
      "pendiente" -> {:ok, :pendiente}
      "entregado" -> {:ok, :entregado}
      _ -> {:error, "Estado de mensaje no válido: #{estado}"}
    end
  end

    def marcar(%Mensaje{id: id, estado: actual} = mensaje, nuevo) do
    with {:ok, nuevo_atomo} <- convertir_estado(nuevo) do
      if nuevo_atomo == actual do
        {:error, "El mensaje #{id} ya está #{actual}"}
      else
        {:ok, %Mensaje{mensaje | estado: nuevo_atomo}}
      end
    end
  end

  defp validar_texto(texto, campo) when is_binary(texto) do
    case String.trim(texto) do
      "" -> {:error, "El campo #{campo} no puede estar vacío"}
      _ -> :ok
    end
  end

  defp validar_texto(_, campo), do: {:error, "El campo #{campo} debe ser texto"}

  defimpl String.Chars, for: Mensaje do
    def to_string(%Mensaje{} = m) do
      "#{m.id} | #{m.fecha} | de #{m.remitente} para #{m.destinatario} | #{m.estado} | #{m.contenido}"
    end
  end
end
