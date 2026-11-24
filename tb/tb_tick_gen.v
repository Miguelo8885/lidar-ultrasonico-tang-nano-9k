// =============================================================================
// tb_tick_gen.v  -  testbench de tick_gen
//
// Como correrlo (desde la carpeta lidar_scanner):
//   iverilog -o sim/tb_tick_gen.vvp rtl/tick_gen.v tb/tb_tick_gen.v
//   vvp sim/tb_tick_gen.vvp
//   gtkwave sim/tb_tick_gen.vcd        (opcional: ver las formas de onda)
//
// Tiempo limite: si la simulacion se traba, termina sola con PRUEBA FALLIDA.
//
// Casos que prueba:
//   1. Despues del reset: cnt = 0 y tick = 0.
//   2. El primer tick llega exactamente 27 ciclos despues de soltar el reset.
//   3. tick dura exactamente 1 ciclo.
//   4. Entre dos ticks seguidos hay exactamente 27 ciclos (100 ticks seguidos).
//   5. Reset a mitad de la cuenta: el contador vuelve a 0 y el siguiente tick
//      llega 27 ciclos despues de soltar el reset.
//   6. Reset en el mismo ciclo en que tick = 1: el contador queda en 0.
//   7. Reset sostenido varios ciclos: tick nunca sube mientras rst = 1
//      (salvo que el contador ya estuviera en 26, cosa que el caso 6 cubre).
//
// Al final imprime "PRUEBA EXITOSA" o el numero de errores.
// =============================================================================

`timescale 1ns / 1ps

module tb_tick_gen;

    // ---------------- senales que conectamos al modulo ----------------------
    reg  clk = 1'b0;
    reg  rst = 1'b1;
    wire tick;

    // ---------------- el modulo bajo prueba (DUT: device under test) --------
    tick_gen dut (
        .clk  (clk),
        .rst  (rst),
        .tick (tick)
    );

    // ---------------- reloj de 27 MHz: periodo 37.037 ns ------------------
    always #18.5185 clk = ~clk;

    // ---------------- herramientas de verificacion -------------------------
    integer errores = 0;
    integer ciclos;
    integer i;

    // Avanza n flancos de subida del reloj
    task esperar_ciclos(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) @(posedge clk);
            #1;   // pequeno margen para leer las salidas ya estables
        end
    endtask

    // Cuenta cuantos ciclos pasan hasta que tick = 1 (maximo 100)
    task contar_hasta_tick(output integer n);
        begin
            n = 0;
            while (tick !== 1'b1 && n < 100) begin
                @(posedge clk); #1;
                n = n + 1;
            end
        end
    endtask

    task revisar(input cond, input [8*60-1:0] mensaje);
        begin
            if (!cond) begin
                errores = errores + 1;
                $display("  ERROR (t = %0t ns): %0s", $time, mensaje);
            end
        end
    endtask

    // ---------------- secuencia de prueba -----------------------------------
    // ---------------- tiempo limite: si algo se traba, la prueba falla -----
    initial begin
        #(10_000_000);
        $display("PRUEBA FALLIDA: la simulacion no termino a tiempo (algo se trabo)");
        $finish;
    end

    initial begin
        $dumpfile("sim/tb_tick_gen.vcd");   // archivo de formas de onda
        $dumpvars(0, tb_tick_gen);

        $display("=== tb_tick_gen ===");

        // ---- Caso 1: reset ----
        esperar_ciclos(3);
        revisar(dut.cnt == 5'd0, "caso 1: cnt no es 0 durante el reset");
        revisar(tick == 1'b0,    "caso 1: tick subio durante el reset");
        $display("Caso 1 (reset) revisado");

        // ---- Caso 2: primer tick a los 27 ciclos ----
        @(negedge clk) rst = 1'b0;          // soltamos el reset lejos del flanco
        contar_hasta_tick(ciclos);
        // El contador sale del reset en 0 y sube en cada flanco:
        // tras 26 flancos vale 26 y tick sube. Ese es el ciclo 27 contando el 0.
        revisar(ciclos == 26, "caso 2: el primer tick no llego a los 26 flancos");
        $display("Caso 2 (primer tick) revisado: llego tras %0d flancos", ciclos);

        // ---- Caso 3: tick dura un ciclo ----
        esperar_ciclos(1);
        revisar(tick == 1'b0, "caso 3: tick duro mas de un ciclo");
        revisar(dut.cnt == 5'd0, "caso 3: cnt no volvio a 0 despues del tick");
        $display("Caso 3 (duracion de tick) revisado");

        // ---- Caso 4: periodo exacto de 27 ciclos, 100 veces ----
        for (i = 0; i < 100; i = i + 1) begin
            contar_hasta_tick(ciclos);
            // ya estamos 1 ciclo despues del tick anterior, faltan 26
            revisar(ciclos == 26, "caso 4: periodo distinto de 27 ciclos");
            esperar_ciclos(1);
        end
        $display("Caso 4 (100 periodos de 27 ciclos) revisado");

        // ---- Caso 5: reset a mitad de la cuenta ----
        esperar_ciclos(10);                  // el contador va en 10
        @(negedge clk) rst = 1'b1;
        esperar_ciclos(1);
        revisar(dut.cnt == 5'd0, "caso 5: cnt no volvio a 0 con reset");
        @(negedge clk) rst = 1'b0;
        contar_hasta_tick(ciclos);
        revisar(ciclos == 26, "caso 5: tras el reset el tick no llego a los 26 flancos");
        $display("Caso 5 (reset a mitad de cuenta) revisado");

        // ---- Caso 6: reset en el mismo ciclo del tick ----
        // ahora tick = 1; activamos rst en este mismo ciclo
        rst = 1'b1;
        esperar_ciclos(1);
        revisar(dut.cnt == 5'd0, "caso 6: cnt no quedo en 0");
        revisar(tick == 1'b0,    "caso 6: tick siguio en 1");
        $display("Caso 6 (reset junto con tick) revisado");

        // ---- Caso 7: reset sostenido ----
        for (i = 0; i < 60; i = i + 1) begin
            esperar_ciclos(1);
            revisar(tick == 1'b0, "caso 7: tick subio con reset sostenido");
        end
        $display("Caso 7 (reset sostenido 60 ciclos) revisado");

        // ---- resultado ----
        if (errores == 0) $display("PRUEBA EXITOSA: tick_gen paso todos los casos");
        else              $display("PRUEBA FALLIDA: %0d errores", errores);
        $finish;
    end

endmodule
