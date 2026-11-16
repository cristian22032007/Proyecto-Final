ExUnit.start()

defmodule PruebasEmergencias do
  # No pueden ser asíncronas: los servidores tienen nombre global
  use ExUnit.Case, async: false

  setup do
    Almacen.usar_directorio_temporal()
    start_supervised!(SupervisorEmergencias)
    :ok
  end


  # Usuarios


  describe "usuarios" do
    test "se registra automáticamente y valida la contraseña" do
      assert {:ok, "Usuario laura registrado y conectado"} =
               ServidorUsuarios.connect("laura", "1234", "coordinador", "centro")

      ServidorUsuarios.disconnect("laura")

      assert {:error, "Contraseña incorrecta"} =
               ServidorUsuarios.connect("laura", "mala", "coordinador", "centro")

      assert {:ok, "Usuario laura conectado"} =
               ServidorUsuarios.connect("laura", "1234", "coordinador", "centro")
    end

    test "rechaza un tipo de usuario inválido" do
      assert {:error, _} = ServidorUsuarios.connect("pedro", "abc", "invitado", "norte")
    end

    test "restringe operaciones según el rol" do
      ServidorUsuarios.connect("laura", "1234", "coordinador", "centro")
      ServidorUsuarios.connect("ana", "1234", "ciudadano", "centro")

      assert {:ok, _} = ServidorUsuarios.autorizar("laura", :asignar_recurso)
      assert {:error, _} = ServidorUsuarios.autorizar("ana", :asignar_recurso)
    end
  end


  # Zonas (recursividad sobre zona -> sectores -> puntos)


  describe "zonas" do
    test "las estadísticas recorren sectores y puntos" do
      {:ok, zona} = Zona.crear("Z1", "Centro", "critico", 100)
      {:ok, zona} = Zona.agregar_sector(zona, "S1", "alto", 40)
      {:ok, zona} = Zona.agregar_sector(zona, "S2", "medio", 30)
      {:ok, zona} = Zona.agregar_punto(zona, "S1", "P1", 10)
      {:ok, zona} = Zona.agregar_punto(zona, "S2", "P2", 5)

      estadisticas = Zona.estadisticas(zona)

      assert estadisticas.en_sectores == 70
      assert estadisticas.sectores == 2
      assert estadisticas.puntos == 2
      assert estadisticas.atendidas == 15
    end

    test "rechaza sectores repetidos, niveles inválidos y cantidades negativas" do
      {:ok, zona} = Zona.crear("Z1", "Centro", "critico", 100)
      {:ok, zona} = Zona.agregar_sector(zona, "S1", "alto", 40)

      assert {:error, _} = Zona.agregar_sector(zona, "S1", "bajo", 10)
      assert {:error, _} = Zona.crear("Z2", "Norte", "extremo", 10)
      assert {:error, _} = Zona.crear("Z3", "Sur", "medio", -5)
      assert {:error, _} = Zona.agregar_punto(zona, "S9", "P1", 0)
    end

    test "el servidor no permite códigos de zona repetidos" do
      assert {:ok, _} = ServidorZonas.registrar_zona("Z01", "Centro", "critico", 10)
      assert {:error, _} = ServidorZonas.registrar_zona("Z01", "Otra", "alto", 10)
    end
  end


  # Recursos (conflicto concurrente obligatorio)


  describe "recursos" do
    test "100 solicitudes simultáneas nunca superan el inventario" do
      {:ok, _} = ServidorRecursos.registrar("R001", "agua", 20, "litros", "centro")

      resultados =
        1..100
        |> Enum.map(fn _ -> Task.async(fn -> ServidorRecursos.salida("R001", 1) end) end)
        |> Enum.map(&Task.await/1)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 20
      assert {:ok, %Recurso{cantidad: 0}} = ServidorRecursos.consultar("R001")
    end

    test "no permite cantidades negativas ni salidas mayores al inventario" do
      {:ok, _} = ServidorRecursos.registrar("R001", "agua", 10, "litros", "centro")

      assert {:error, _} = ServidorRecursos.registrar("R002", "agua", -5, "litros", "centro")
      assert {:error, _} = ServidorRecursos.salida("R001", 11)
      assert {:error, _} = ServidorRecursos.entrada("R001", -3)
      assert {:ok, %Recurso{cantidad: 10}} = ServidorRecursos.consultar("R001")
    end

    test "conserva el historial de movimientos" do
      {:ok, _} = ServidorRecursos.registrar("R001", "agua", 10, "litros", "centro")
      ServidorRecursos.salida("R001", 4)
      ServidorRecursos.entrada("R001", 2)

      {:ok, recurso} = ServidorRecursos.consultar("R001")
      assert length(recurso.historial) == 3
      assert recurso.cantidad == 8
    end

    test "las transferencias conservan el total" do
      {:ok, _} = ServidorRecursos.registrar("R001", "agua", 50, "litros", "centro")

      assert {:ok, :transferido} = ServidorRecursos.transferir("R001", "albergue", 30)
      assert {:error, _} = ServidorRecursos.transferir("R001", "albergue", 5000)
      assert {:error, _} = ServidorRecursos.transferir("R001", "centro", 5)

      assert ServidorRecursos.disponibilidad("agua") == 50
      assert ServidorRecursos.disponibilidad("agua", "albergue") == 30
    end
  end


  # Necesidades


  describe "necesidades" do
    test "dos asignaciones simultáneas sobre 50 litros: solo una se confirma" do
      {:ok, _} = ServidorRecursos.registrar("R001", "agua", 50, "litros", "centro")
      {:ok, n1} = ServidorNecesidades.registrar("agua", 30, "critica", "centro", "A", "laura")
      {:ok, n2} = ServidorNecesidades.registrar("agua", 25, "alta", "centro", "B", "carlos")

      resultados =
        [n1.id, n2.id]
        |> Enum.map(fn id -> Task.async(fn -> ServidorNecesidades.asignar(id, "R001") end) end)
        |> Enum.map(&Task.await/1)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1

      {:ok, recurso} = ServidorRecursos.consultar("R001")
      assert recurso.cantidad in [20, 25]
    end

    test "una necesidad atendida no vuelve a consumir recursos" do
      {:ok, _} = ServidorRecursos.registrar("R001", "agua", 50, "litros", "centro")
      {:ok, n} = ServidorNecesidades.registrar("agua", 10, "alta", "centro", "A", "laura")

      assert {:ok, _} = ServidorNecesidades.asignar(n.id, "R001")
      assert {:ok, _} = ServidorNecesidades.cambiar_estado(n.id, :en_atencion)
      assert {:ok, _} = ServidorNecesidades.cambiar_estado(n.id, :atendida)

      assert {:error, _} = ServidorNecesidades.asignar(n.id, "R001")
      assert {:error, _} = ServidorNecesidades.cambiar_estado(n.id, :cancelada)
      assert {:ok, %Recurso{cantidad: 40}} = ServidorRecursos.consultar("R001")
    end

    test "las transiciones de estado deben ser válidas" do
      {:ok, n} = ServidorNecesidades.registrar("agua", 10, "alta", "centro", "A", "laura")

      assert {:error, _} = ServidorNecesidades.cambiar_estado(n.id, :atendida)
      assert {:ok, _} = ServidorNecesidades.cambiar_estado(n.id, :cancelada)
      assert {:error, _} = ServidorNecesidades.cambiar_estado(n.id, :cancelada)
    end

    test "la prioridad ordena la atención" do
      ServidorNecesidades.registrar("agua", 1, "baja", "centro", "A", "laura")
      ServidorNecesidades.registrar("agua", 1, "critica", "centro", "B", "laura")
      ServidorNecesidades.registrar("agua", 1, "alta", "centro", "C", "laura")

      prioridades = Enum.map(ServidorNecesidades.pendientes(), & &1.prioridad)
      assert prioridades == [:critica, :alta, :baja]
    end

    test "valida tipo, cantidad y prioridad" do
      assert {:error, _} = ServidorNecesidades.registrar("gasolina", 10, "alta", "centro", "A", "x")
      assert {:error, _} = ServidorNecesidades.registrar("agua", 0, "alta", "centro", "A", "x")
      assert {:error, _} = ServidorNecesidades.registrar("agua", 10, "urgente", "centro", "A", "x")
    end

    test "se pueden filtrar por zona y prioridad" do
      ServidorNecesidades.registrar("agua", 1, "critica", "centro", "A", "laura")
      ServidorNecesidades.registrar("agua", 1, "critica", "norte", "B", "laura")
      ServidorNecesidades.registrar("agua", 1, "baja", "centro", "C", "laura")

      assert [%Necesidad{descripcion: "A"}] =
               ServidorNecesidades.listar(zona: "centro", prioridad: :critica)
    end
  end


  # Personas y mensajes


  describe "personas y mensajes" do
    test "5 registros simultáneos del mismo documento: solo uno se acepta" do
      resultados =
        1..5
        |> Enum.map(fn _ ->
          Task.async(fn -> ServidorPersonas.registrar("2002", "Carlos", 40, "centro") end)
        end)
        |> Enum.map(&Task.await/1)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
    end

    test "valida las transiciones de estado y conserva el historial" do
      {:ok, _} = ServidorPersonas.registrar("1001", "Andrés", 34, "norte", "reportada")

      assert {:ok, _} = ServidorPersonas.cambiar_estado("1001", "localizada")
      assert {:ok, _} = ServidorPersonas.cambiar_estado("1001", "reunificada")
      assert {:error, _} = ServidorPersonas.cambiar_estado("1001", "localizada")

      assert {:ok, historial} = ServidorPersonas.historial("1001")
      assert length(historial) == 3
    end

    test "los mensajes se dirigen a personas existentes y cambian de estado" do
      {:ok, _} = ServidorPersonas.registrar("1001", "Andrés", 34, "norte")

      assert {:ok, mensaje} = ServidorPersonas.enviar_mensaje("laura", "1001", "Estoy bien")
      assert mensaje.estado == :pendiente
      assert {:error, _} = ServidorPersonas.enviar_mensaje("laura", "9999", "Hola")
      assert {:error, _} = ServidorPersonas.enviar_mensaje("laura", "1001", "   ")

      assert {:ok, %Mensaje{estado: :entregado}} =
               ServidorPersonas.marcar_mensaje(mensaje.id, "entregado")

      assert {:error, _} = ServidorPersonas.marcar_mensaje(mensaje.id, "entregado")
    end

    test "valida edad y nombre" do
      assert {:error, _} = ServidorPersonas.registrar("1", "Ana", -3, "norte")
      assert {:error, _} = ServidorPersonas.registrar("2", "  ", 30, "norte")
    end
  end


  # Mascotas


  describe "mascotas" do
    test "el puntaje de similitud suma los atributos coincidentes" do
      {:ok, perdida} =
        Mascota.crear("MA1", "lost", "perro", "Luna", "collar rojo y mancha blanca", "negra", "mediana", "zona_norte", "300")

      {:ok, encontrada} =
        Mascota.crear("MA2", "found", "perro", "", "collar rojo", "negra", "mediana", "zona_norte", "300")

      assert Mascota.calcular_similitud(perdida, encontrada) == 80
    end

    test "si la especie es distinta no hay coincidencia" do
      {:ok, perro} = Mascota.crear("MA1", "lost", "perro", "", "", "negra", "mediana", "norte", "300")
      {:ok, gato} = Mascota.crear("MA2", "found", "gato", "", "", "negra", "mediana", "norte", "300")

      assert Mascota.calcular_similitud(perro, gato) == 0
    end

    test "una coincidencia no se puede confirmar dos veces" do
      ServidorMascotas.reportar("lost", "perro", "Luna", "", "negra", "mediana", "norte", "300")
      ServidorMascotas.reportar("found", "perro", "", "", "negra", "mediana", "norte", "300")

      assert [{_, _, puntaje}] = ServidorMascotas.buscar_coincidencias()
      assert puntaje >= Mascota.umbral()

      assert {:ok, _} = ServidorMascotas.confirmar_coincidencia("MA001", "MA002")
      assert {:error, _} = ServidorMascotas.confirmar_coincidencia("MA001", "MA002")
      assert length(ServidorMascotas.buscar(estado: :resuelta)) == 2
    end

    test "un mismo reporte no se resuelve dos veces en paralelo" do
      ServidorMascotas.reportar("lost", "perro", "Luna", "", "negra", "mediana", "norte", "300")
      ServidorMascotas.reportar("found", "perro", "", "", "negra", "mediana", "norte", "300")
      ServidorMascotas.reportar("found", "perro", "Luna", "", "negra", "grande", "norte", "300")

      resultados =
        ["MA002", "MA003"]
        |> Enum.map(fn id ->
          Task.async(fn -> ServidorMascotas.confirmar_coincidencia("MA001", id) end)
        end)
        |> Enum.map(&Task.await/1)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
    end

    test "exige que sea un reporte perdido contra uno encontrado de la misma especie" do
      ServidorMascotas.reportar("lost", "perro", "", "", "negra", "mediana", "norte", "300")
      ServidorMascotas.reportar("found", "gato", "", "", "negra", "mediana", "norte", "300")

      assert {:error, _} = ServidorMascotas.confirmar_coincidencia("MA001", "MA002")
      assert {:error, _} = ServidorMascotas.confirmar_coincidencia("MA002", "MA001")
    end
  end


  # Albergues


  describe "albergues" do
    test "20 ingresos simultáneos a un albergue de 5 cupos admiten exactamente 5" do
      {:ok, _} = ServidorAlbergues.registrar("A02", "Centro", "zona_centro", 5)

      resultados =
        1..20
        |> Enum.map(fn i ->
          Task.async(fn -> ServidorAlbergues.ingreso("A02", "D#{i}") end)
        end)
        |> Enum.map(&Task.await/1)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 5
      assert {:ok, 0} = ServidorAlbergues.cupos("A02")
    end

    test "una persona no puede ingresar dos veces al mismo tiempo" do
      {:ok, _} = ServidorAlbergues.registrar("A03", "Sur", "zona_sur", 40)

      resultados =
        1..5
        |> Enum.map(fn _ -> Task.async(fn -> ServidorAlbergues.ingreso("A03", "X1") end) end)
        |> Enum.map(&Task.await/1)

      assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
    end

    test "al salir una persona se libera un cupo" do
      {:ok, _} = ServidorAlbergues.registrar("A01", "Norte", "zona_norte", 1)

      assert {:ok, _} = ServidorAlbergues.ingreso("A01", "1")
      assert {:error, _} = ServidorAlbergues.ingreso("A01", "2")
      assert {:ok, _} = ServidorAlbergues.salida("A01", "1")
      assert {:ok, _} = ServidorAlbergues.ingreso("A01", "2")
    end

    test "valida capacidad y ocupación" do
      assert {:error, _} = ServidorAlbergues.registrar("A1", "X", "z", -10)
      assert {:error, _} = ServidorAlbergues.registrar("A2", "X", "z", 0)
      assert {:error, _} = ServidorAlbergues.registrar("A3", "X", "z", 100, 200)
    end

    test "el reporte ordena por mayor porcentaje de ocupación" do
      ServidorAlbergues.registrar("A01", "Norte", "z", 100, 20)
      ServidorAlbergues.registrar("A02", "Centro", "z", 10, 9)
      ServidorAlbergues.registrar("A03", "Sur", "z", 50, 25)

      codigos = Enum.map(ServidorAlbergues.reporte_ocupacion(3), & &1.codigo)
      assert codigos == ["A02", "A03", "A01"]
    end
  end


  # Persistencia y supervisión


  describe "persistencia y supervisión" do
    test "los datos sobreviven al reinicio de todos los servidores" do
      ServidorZonas.registrar_zona("Z01", "Centro", "critico", 5000)
      ServidorRecursos.registrar("R001", "agua", 50, "litros", "centro")
      ServidorNecesidades.registrar("agua", 30, "critica", "centro", "Con | barra, y tilde é", "laura")

      :ok = stop_supervised(SupervisorEmergencias)
      start_supervised!(SupervisorEmergencias)

      assert {:ok, %Zona{nombre: "Centro"}} = ServidorZonas.consultar("Z01")
      assert {:ok, %Recurso{cantidad: 50}} = ServidorRecursos.consultar("R001")

      assert {:ok, %Necesidad{descripcion: "Con | barra, y tilde é"}} =
               ServidorNecesidades.consultar("N001")

      # El contador de IDs continúa
      assert {:ok, %Necesidad{id: "N002"}} =
               ServidorNecesidades.registrar("agua", 1, "baja", "centro", "Otra", "laura")
    end

    test "el supervisor reinicia un servidor caído y este recupera su estado" do
      ServidorRecursos.registrar("R001", "agua", 50, "litros", "centro")

      pid_viejo = Process.whereis(ServidorRecursos)
      Process.exit(pid_viejo, :kill)
      :timer.sleep(200)
      pid_nuevo = Process.whereis(ServidorRecursos)

      assert pid_nuevo != nil
      assert pid_nuevo != pid_viejo
      assert {:ok, %Recurso{cantidad: 50}} = ServidorRecursos.consultar("R001")
    end

    test "el supervisor arranca los 7 servidores y el DynamicSupervisor" do
      hijos = Supervisor.which_children(SupervisorEmergencias)
      assert length(hijos) == 8
      assert Process.whereis(SupervisorSesiones) != nil
    end

    test "codificar y decodificar registros conserva los caracteres especiales" do
      campos = ["a|b", "línea\nnueva", "ruta\\carpeta", "normal"]
      assert campos == campos |> Almacen.codificar() |> Almacen.decodificar()
    end
  end


  # CLI


  describe "cli" do
    test "divide la línea respetando las comillas" do
      assert {:ok, ["a", "b c", "d"]} = Cli.dividir(~s(a "b c" d))
      assert {:error, _} = Cli.dividir(~s(a "b))
      assert {:ok, []} = Cli.dividir("   ")
    end

    test "sin sesión pide conectarse y no ejecuta nada" do
      assert {:continuar, nil} = Cli.procesar_linea(nil, "list_needs")
    end

    test "flujo completo con permisos por rol" do
      {:continuar, laura} = Cli.procesar_linea(nil, "connect laura 1234 coordinador centro")
      {:continuar, ana} = Cli.procesar_linea(nil, "connect ana 1234 ciudadano centro")

      Cli.procesar_linea(laura, ~s(register_zone centro "Centro" critico 100))
      Cli.procesar_linea(laura, "register_resource R001 agua 50 litros acopio")
      Cli.procesar_linea(ana, ~s(register_need agua 30 critica centro "Punto 3"))

      assert {:ok, %Necesidad{estado: :pendiente}} = ServidorNecesidades.consultar("N001")

      # Ana es ciudadana: no puede asignar
      Cli.procesar_linea(ana, "assign_resource N001 R001")
      assert {:ok, %Necesidad{estado: :pendiente}} = ServidorNecesidades.consultar("N001")

      # Laura es coordinadora: sí puede
      Cli.procesar_linea(laura, "assign_resource N001 R001")
      assert {:ok, %Necesidad{estado: :asignada}} = ServidorNecesidades.consultar("N001")
      assert {:ok, %Recurso{cantidad: 20}} = ServidorRecursos.consultar("R001")

      assert :salir = Cli.procesar_linea(laura, "exit")
    end
  end
end
