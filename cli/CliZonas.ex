defmodule CliZonas do
  @moduledoc "Comandos del CLI sobre zonas, sectores y puntos de atención."

  def ejecutar("register_zone", [codigo, nombre, nivel | resto], _usuario)
      when length(resto) <= 1 do
    with {:ok, personas} <- CliAnalisis.entero_opcional(resto, "personas afectadas"),
         {:ok, zona} <- ServidorZonas.registrar_zona(codigo, nombre, nivel, personas) do
      {:ok, "Zona #{zona.codigo} registrada (#{zona.nombre}, nivel #{zona.nivel})"}
    end
  end

  def ejecutar("register_sector", [zona, nombre, nivel, personas], _usuario) do
    with {:ok, cantidad} <- CliAnalisis.entero(personas, "personas afectadas"),
         {:ok, _zona} <- ServidorZonas.registrar_sector(zona, nombre, nivel, cantidad) do
      {:ok, "Sector #{nombre} registrado en la zona #{zona}"}
    end
  end

  def ejecutar("register_point", [zona, sector, nombre | resto], _usuario)
      when length(resto) <= 1 do
    with {:ok, atendidas} <- CliAnalisis.entero_opcional(resto, "personas atendidas"),
         {:ok, _zona} <- ServidorZonas.registrar_punto(zona, sector, nombre, atendidas) do
      {:ok, "Punto de atención #{nombre} registrado en #{zona}/#{sector}"}
    end
  end

  def ejecutar("zone_status", [codigo], _usuario) do
    with {:ok, zona} <- ServidorZonas.consultar(codigo) do
      {:ok, String.trim_trailing(Zona.generar_resumen(zona))}
    end
  end

  # Argumentos que no coinciden: Cli muestra el uso del comando
  def ejecutar(_comando, _argumentos, _usuario), do: {:error, :uso}
end
