// =============================================================================
// tb_grid_walker.v  -  testbench de grid_walker
//
// Como correrlo (desde la carpeta lidar_scanner):
//   iverilog -o sim/tb_grid_walker.vvp rtl/grid_walker.v tb/tb_grid_walker.v
//   vvp sim/tb_grid_walker.vvp
//   gtkwave sim/tb_grid_walker.vcd    (opcional)
//
// El testbench lleva su PROPIO modelo de la serpentina (fila y columna
// esperadas, calculadas de otra forma) y compara el modulo contra ese modelo
// despues de cada step.
//
// Tiempo limite: si la simulacion se traba, termina sola con PRUEBA FALLIDA.
//
// Casos que prueba:
//   1. Reset: (0, 0), addr = 0, last = 0.
//   2. Sin step no se mueve, aunque pasen muchos ciclos.
//   3. Recorrido completo: 144 puntos en el orden de la serpentina; addr
//      siempre igual a {row, col}; nunca se sale de 0..11.
//   4. Bordes: en (0, 11) el step baja a (1, 11); en (1, 0) baja a (2, 0).
//   5. last vale 1 SOLO en (11, 0) y en ningun otro punto.
//   6. El step en el ultimo punto vuelve a (0, 0).
//   7. Segunda vuelta identica a la primera.
//   8. Reset a mitad del recorrido: vuelve a (0, 0) y luego recorre normal.
//   9. Reset y step en el mismo ciclo: gana el reset.
//  10. step sostenido varios ciclos: avanza un punto por ciclo (por eso step
//      debe ser un pulso de un ciclo; scan_fsm lo garantiza).
// =============================================================================

`timescale 1ns / 1ps

module tb_grid_walker;

    reg        clk  = 1'b0;
    reg        rst  = 1'b1;
    reg        step = 1'b0;
    wire [3:0] row, col;
    wire [7:0] addr;
    wire       last;

    grid_walker dut (
        .clk(clk), .rst(rst), .step(step),
        .row(row), .col(col), .addr(addr), .last(last)
    );

    always #18.5185 clk = ~clk;

    integer errores = 0;
    integer k, n_last;
    integer er, ec;              // fila y columna esperadas (modelo)

    task revisar(input cond, input [8*70-1:0] mensaje);
        begin
            if (!cond) begin
                errores = errores + 1;
                $display("  ERROR (t = %0t ns): %0s  [row=%0d col=%0d]", $time, mensaje, row, col);
            end
        end
    endtask

    // Modelo de la serpentina: siguiente punto a partir de (er, ec)
    task modelo_siguiente;
        begin
            if (er == 11 && ec == 0) begin        // ultimo punto -> inicio
                er = 0; ec = 0;
            end else if (er % 2 == 0) begin       // fila par: hacia la derecha
                if (ec == 11) er = er + 1; else ec = ec + 1;
            end else begin                        // fila impar: hacia la izquierda
                if (ec == 0) er = er + 1; else ec = ec - 1;
            end
        end
    endtask

    // Da un pulso de step de un ciclo
    task dar_step;
        begin
            @(negedge clk) step = 1'b1;
            @(negedge clk) step = 1'b0;
        end
    endtask

    // Compara el modulo con el modelo
    task comparar(input [8*40-1:0] caso);
        begin
            revisar(row == er && col == ec, caso);
            revisar(addr == {row, col}, "addr distinto de {row, col}");
            revisar(row <= 11 && col <= 11, "posicion fuera de la rejilla");
            revisar(last == (er == 11 && ec == 0), "last incorrecto");
        end
    endtask

    // Recorre una vuelta completa (144 steps) comparando en cada punto
    task vuelta_completa(input [8*40-1:0] caso);
        begin
            n_last = 0;
            for (k = 0; k < 144; k = k + 1) begin
                if (last) n_last = n_last + 1;
                dar_step;
                modelo_siguiente;
                comparar(caso);
            end
        end
    endtask

    // ---------------- tiempo limite: si algo se traba, la prueba falla -----
    initial begin
        #(10_000_000);
        $display("PRUEBA FALLIDA: la simulacion no termino a tiempo (algo se trabo)");
        $finish;
    end

    initial begin
        $dumpfile("sim/tb_grid_walker.vcd");
        $dumpvars(0, tb_grid_walker);
        $display("=== tb_grid_walker ===");

        // ---- Caso 1 ----
        repeat (3) @(posedge clk);
        @(negedge clk);
        er = 0; ec = 0;
        comparar("caso 1: reset no da (0, 0)");
        revisar(addr == 8'd0, "caso 1: addr no es 0");
        rst = 1'b0;
        $display("Caso 1 (reset) revisado");

        // ---- Caso 2 ----
        repeat (50) @(negedge clk);
        comparar("caso 2: se movio sin step");
        $display("Caso 2 (sin step no se mueve) revisado");

        // ---- Casos 3, 4, 5, 6: primera vuelta ----
        vuelta_completa("caso 3: recorrido distinto al modelo");
        revisar(n_last == 1, "caso 5: last no estuvo en 1 exactamente en un punto");
        revisar(row == 0 && col == 0, "caso 6: tras el ultimo punto no volvio a (0, 0)");
        $display("Casos 3 a 6 (vuelta completa, bordes, last, regreso) revisados");

        // ---- Caso 4 explicito: bordes ----
        for (k = 0; k < 11; k = k + 1) dar_step;    // llegar a (0, 11)
        revisar(row == 0 && col == 11, "caso 4: no llego a (0, 11)");
        dar_step;
        revisar(row == 1 && col == 11, "caso 4: en (0, 11) no bajo a (1, 11)");
        for (k = 0; k < 11; k = k + 1) dar_step;    // llegar a (1, 0)
        revisar(row == 1 && col == 0, "caso 4: no llego a (1, 0)");
        dar_step;
        revisar(row == 2 && col == 0, "caso 4: en (1, 0) no bajo a (2, 0)");
        $display("Caso 4 (cambios de fila en ambos bordes) revisado");

        // ---- Caso 8: reset a mitad del recorrido ----
        @(negedge clk) rst = 1'b1;
        @(negedge clk) rst = 1'b0;
        er = 0; ec = 0;
        comparar("caso 8: reset a mitad no volvio a (0, 0)");
        $display("Caso 8 (reset a mitad del recorrido) revisado");

        // ---- Caso 7: vuelta completa otra vez ----
        vuelta_completa("caso 7: segunda vuelta distinta");
        revisar(n_last == 1, "caso 7: last mal en la segunda vuelta");
        $display("Caso 7 (segunda vuelta identica) revisado");

        // ---- Caso 9: reset y step juntos ----
        for (k = 0; k < 5; k = k + 1) dar_step;     // ir a (0, 5)
        @(negedge clk) begin rst = 1'b1; step = 1'b1; end
        @(negedge clk) begin rst = 1'b0; step = 1'b0; end
        revisar(row == 0 && col == 0, "caso 9: el step le gano al reset");
        $display("Caso 9 (reset y step juntos: gana el reset) revisado");

        // ---- Caso 10: step sostenido 3 ciclos ----
        @(negedge clk) step = 1'b1;
        repeat (3) @(negedge clk);
        step = 1'b0;
        revisar(row == 0 && col == 3, "caso 10: step sostenido no avanzo 1 punto por ciclo");
        $display("Caso 10 (step sostenido: un punto por ciclo) revisado");

        if (errores == 0) $display("PRUEBA EXITOSA: grid_walker paso todos los casos");
        else              $display("PRUEBA FALLIDA: %0d errores", errores);
        $finish;
    end

endmodule
