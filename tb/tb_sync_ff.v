// =============================================================================
// tb_sync_ff.v  -  testbench de sync_ff
//
// Como correrlo (desde la carpeta lidar_scanner):
//   iverilog -o sim/tb_sync_ff.vvp rtl/sync_ff.v tb/tb_sync_ff.v
//   vvp sim/tb_sync_ff.vvp
//   gtkwave sim/tb_sync_ff.vcd        (opcional)
//
// Se prueban DOS copias del modulo a la vez: una con RESET_VAL = 0 (como Echo)
// y otra con RESET_VAL = 1 (como un boton activo en bajo, que en reposo vale 1).
//
// Tiempo limite: si la simulacion se traba, termina sola con PRUEBA FALLIDA.
//
// Casos que prueba:
//   1. Con reset, cada copia toma su RESET_VAL aunque la entrada valga otra cosa.
//   2. Sin reset, la salida copia la entrada exactamente 1 ciclo despues.
//   3. Si la entrada cambia entre flancos (en cualquier momento), la salida
//      solo cambia en el siguiente flanco de subida.
//   4. Una entrada que se mantiene, mantiene la salida (sin cambios espurios).
//   5. Un pulso mas corto que un periodo y que no cruza ningun flanco se
//      pierde (comportamiento esperado y documentado).
//   6. El reset tiene prioridad: con rst = 1 la salida es RESET_VAL aunque
//      la entrada cambie.
// =============================================================================

`timescale 1ns / 1ps

module tb_sync_ff;

    reg  clk = 1'b0;
    reg  rst = 1'b1;
    reg  d   = 1'b1;          // misma entrada para las dos copias
    wire q0, q1;

    sync_ff #(.RESET_VAL(1'b0)) dut0 (.clk(clk), .rst(rst), .d_async(d), .q_sync(q0));
    sync_ff #(.RESET_VAL(1'b1)) dut1 (.clk(clk), .rst(rst), .d_async(d), .q_sync(q1));

    always #18.5185 clk = ~clk;   // 27 MHz

    integer errores = 0;
    integer i;

    task revisar(input cond, input [8*70-1:0] mensaje);
        begin
            if (!cond) begin
                errores = errores + 1;
                $display("  ERROR (t = %0t ns): %0s", $time, mensaje);
            end
        end
    endtask

    // ---------------- tiempo limite: si algo se traba, la prueba falla -----
    initial begin
        #(1_000_000);
        $display("PRUEBA FALLIDA: la simulacion no termino a tiempo (algo se trabo)");
        $finish;
    end

    initial begin
        $dumpfile("sim/tb_sync_ff.vcd");
        $dumpvars(0, tb_sync_ff);
        $display("=== tb_sync_ff ===");

        // ---- Caso 1: reset con la entrada en 1 y luego en 0 ----
        d = 1'b1;
        repeat (3) @(posedge clk); #1;
        revisar(q0 == 1'b0, "caso 1: copia RESET_VAL=0 no quedo en 0");
        revisar(q1 == 1'b1, "caso 1: copia RESET_VAL=1 no quedo en 1");
        d = 1'b0;
        repeat (2) @(posedge clk); #1;
        revisar(q0 == 1'b0 && q1 == 1'b1, "caso 1: con d=0 las copias no tomaron RESET_VAL");
        $display("Caso 1 (valor de reset) revisado");

        // ---- Caso 2: copia la entrada 1 ciclo despues ----
        @(negedge clk) rst = 1'b0; d = 1'b1;
        #1;
        revisar(q0 == 1'b0, "caso 2: la salida cambio antes del flanco");
        @(posedge clk); #1;
        revisar(q0 == 1'b1 && q1 == 1'b1, "caso 2: la salida no copio d=1 en el flanco");
        @(negedge clk) d = 1'b0;
        @(posedge clk); #1;
        revisar(q0 == 1'b0 && q1 == 1'b0, "caso 2: la salida no copio d=0 en el flanco");
        $display("Caso 2 (retardo de un ciclo) revisado");

        // ---- Caso 3: cambios en distintos momentos entre flancos ----
        for (i = 1; i < 36; i = i + 4) begin
            @(posedge clk); #(i);          // cambiamos d i ns despues del flanco
            d = ~d;
            #0.5;
            revisar(q0 == ~d, "caso 3: la salida cambio sin flanco de reloj");
            @(posedge clk); #1;
            revisar(q0 == d && q1 == d, "caso 3: la salida no tomo el valor en el flanco");
        end
        $display("Caso 3 (cambios entre flancos) revisado");

        // ---- Caso 4: entrada estable ----
        @(negedge clk) d = 1'b1;
        @(posedge clk); #1;
        for (i = 0; i < 50; i = i + 1) begin
            @(posedge clk); #1;
            revisar(q0 == 1'b1 && q1 == 1'b1, "caso 4: cambio espurio con entrada estable");
        end
        $display("Caso 4 (entrada estable 50 ciclos) revisado");

        // ---- Caso 5: pulso corto entre dos flancos ----
        @(posedge clk); #5;
        d = 1'b0; #10; d = 1'b1;           // pulso de 10 ns, no cruza flanco
        @(posedge clk); #1;
        revisar(q0 == 1'b1, "caso 5: el pulso corto aparecio a la salida");
        $display("Caso 5 (pulso corto se pierde, esperado) revisado");

        // ---- Caso 6: reset con prioridad ----
        @(negedge clk) rst = 1'b1; d = 1'b1;
        @(posedge clk); #1;
        revisar(q0 == 1'b0 && q1 == 1'b1, "caso 6: el reset no tuvo prioridad");
        @(negedge clk) d = 1'b0;
        @(posedge clk); #1;
        revisar(q0 == 1'b0 && q1 == 1'b1, "caso 6: con reset la salida siguio a la entrada");
        @(negedge clk) rst = 1'b0;
        @(posedge clk); #1;
        revisar(q0 == 1'b0 && q1 == 1'b0, "caso 6: tras soltar reset no copio la entrada");
        $display("Caso 6 (prioridad del reset) revisado");

        if (errores == 0) $display("PRUEBA EXITOSA: sync_ff paso todos los casos");
        else              $display("PRUEBA FALLIDA: %0d errores", errores);
        $finish;
    end

endmodule
