defmodule Principal do
  def main do
    {:ok, _pid} = SupervisorEmergencias.start_link()
    Cli.main()
  end
end

Principal.main()
