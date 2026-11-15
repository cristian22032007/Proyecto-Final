defmodule Recurso do
  defstruct codigo: "", nombre: "", categoria: "", cantidad: 0, unidad: "", ubicacion: "", historial: []

  def crear(codigo, nombre, cantidad, unidad, ubicacion) do
    with :ok <- validar_texto(codigo, "código"),
         :ok <- validar_texto(nombre, "nombre"),
         :ok <- validar_texto(unidad, "unidad"),
         :ok <- validar_texto(ubicacion, "ubicación"),
         :ok <- validar_cantidad(cantidad) do
      {:ok,
       %Recurso{
         codigo: codigo,
         nombre: nombre,
         categoria: nombre,
         cantidad: cantidad,
         unidad: unidad,
         ubicacion: ubicacion,
         historial: [movimiento(:entrada, cantidad, "registro inicial")]
       }}
    end
  end

  def registrar_entrada(%Recurso{} = recurso, cantidad, motivo) do
    with :ok <- validar_cantidad(cantidad) do
      {:ok,
       %Recurso{
         recurso
         | cantidad: recurso.cantidad + cantidad,
           historial: [movimiento(:entrada, cantidad, motivo) | recurso.historial]
       }}
    end
  end

  def registrar_salida(%Recurso{} = recurso, cantidad, motivo) do
    with :ok <- validar_cantidad(cantidad),
         :ok <- validar_disponible(recurso, cantidad) do
      {:ok,
       %Recurso{
         recurso
         | cantidad: recurso.cantidad - cantidad,
           historial: [movimiento(:salida, cantidad, motivo) | recurso.historial]
       }}
    end
  end

  defp validar_disponible(%Recurso{cantidad: disponible}, cantidad) when cantidad <= disponible,
    do: :ok

  defp validar_disponible(%Recurso{codigo: codigo, cantidad: disponible, unidad: unidad}, cantidad) do
    {:error, "Inventario insuficiente en #{codigo}: se piden #{cantidad} y hay #{disponible} #{unidad}"}
  end

  defp movimiento(tipo, cantidad, motivo) do
    {DateTime.utc_now() |> DateTime.to_string(), tipo, cantidad, motivo}
  end

  defp validar_texto(texto, campo) when is_binary(texto) do
    case String.trim(texto) do
      "" -> {:error, "El campo #{campo} no puede estar vacío"}
      _ -> :ok
    end
  end

  defp validar_texto(_, campo), do: {:error, "El campo #{campo} debe ser texto"}

  defp validar_cantidad(cantidad) when is_integer(cantidad) and cantidad > 0, do: :ok
  defp validar_cantidad(_), do: {:error, "La cantidad debe ser un entero mayor que cero"}
end
