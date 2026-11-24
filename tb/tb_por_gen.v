// =============================================================================
// tb_por_gen.v  -  testbench de por_gen
//
// Como correrlo: ./simular.sh por_gen
//
// Casos que prueba (reloj real de 27 MHz, W = 16):
//   1. Desde el primer instante rst_por = 1 y listo = 0.
//   2. rst_por dura exactamente 65 535 ciclos (2,43 ms).
//   3. Despues rst_por queda en 0 y listo en 1 durante 200 000 ciclos mas:
//      el contador se detuvo y no vuelve a dar reset.
// =============================================================================

`timescale 1ns / 1fs

module tb_por_gen;

    reg  clk = 1'b0;
    wire rst_por, listo;

    por_gen #(.W(16)) dut (.clk(clk), .rst_por(rst_por), .listo(listo));

    always #18.5185 clk = ~clk;

    integer errores = 0, ciclos = 0, k;

    initial begin
        $dumpfile("sim/tb_por_gen.vcd");
        $dumpvars(0, tb_por_gen);
        $display("=== tb_por_gen ===  (27 MHz, W = 16)");

        // ---- Caso 1 ----
        #1;
        if (rst_por !== 1'b1 || listo !== 1'b0) begin
            errores = errores + 1; $display("  ERROR caso 1: rst_por no arranca en 1");
        end
        $display("Caso 1 (rst_por = 1 desde el encendido) revisado");

        // ---- Caso 2 ----
        while (rst_por) begin @(posedge clk); #1; ciclos = ciclos + 1; end
        if (ciclos != 65535) begin
            errores = errores + 1; $display("  ERROR caso 2: rst_por duro %0d ciclos", ciclos);
        end
        $display("Caso 2 (rst_por dura %0d ciclos = %0.3f ms) revisado", ciclos, $realtime / 1e6);

        // ---- Caso 3 ----
        for (k = 0; k < 200000; k = k + 1) begin
            @(posedge clk); #1;
            if (rst_por !== 1'b0 || listo !== 1'b1) errores = errores + 1;
        end
        if (errores) $display("  ERROR caso 3: rst_por volvio a subir");
        $display("Caso 3 (despues queda en 0 para siempre) revisado");

        if (errores == 0) $display("PRUEBA EXITOSA: por_gen paso todos los casos");
        else              $display("PRUEBA FALLIDA: %0d errores", errores);
        $finish;
    end

endmodule
