// =============================================================================
// tb_depth_quant.v  -  testbench de depth_quant
//
// Como correrlo: ./simular.sh depth_quant
//
// Modulo combinacional: se pone cada entrada, se espera 1 ns y se revisa.
// Se prueban DOS copias: D_NEAR = 200 (el valor de diseno) y D_NEAR = 160
// (para comprobar que el parametro de calibracion funciona).
//
// Casos que prueba:
//   1. TODAS las entradas (0 a 1 023) en las dos copias, contra el modelo
//      min(15, max(0, (d - D_NEAR) / 32)) con 15 para d >= D_NEAR + 480.
//   2. Bordes con D_NEAR = 200: 199->0, 200->0, 231->0, 232->1, 679->14,
//      680->15, 711->15, 712->15, 859->15 (sin eco), 1 023->15.
//   3. Requisito: botella a 300 mm -> 3, botella a 600 mm -> 12.
// =============================================================================

`timescale 1ns / 1ps

module tb_depth_quant;

    reg  [9:0] d_mm = 10'd0;
    wire [3:0] idx200, idx160;

    depth_quant #(.D_NEAR(10'd200)) dut200 (.d_mm(d_mm), .idx(idx200));
    depth_quant #(.D_NEAR(10'd160)) dut160 (.d_mm(d_mm), .idx(idx160));

    integer errores = 0;
    integer d, k;

    function integer modelo(input integer dist, input integer dnear);
        integer q;
        begin
            if (dist < dnear) modelo = 0;
            else begin
                q = (dist - dnear) / 32;
                modelo = (q >= 15) ? 15 : q;
            end
        end
    endfunction

    task borde(input integer dist, input integer esperado);
        begin
            d_mm = dist; #1;
            if (idx200 != esperado) begin
                errores = errores + 1;
                $display("  ERROR: %0d mm -> %0d (esperado %0d)", dist, idx200, esperado);
            end else
                $display("  %0d mm -> indice %0d", dist, idx200);
        end
    endtask

    initial begin
        $dumpfile("sim/tb_depth_quant.vcd");
        $dumpvars(0, tb_depth_quant);
        $display("=== tb_depth_quant ===");

        // ---- Caso 1 ----
        k = 0;
        for (d = 0; d <= 1023; d = d + 1) begin
            d_mm = d; #1;
            if (idx200 != modelo(d, 200) || idx160 != modelo(d, 160)) begin
                k = k + 1;
                if (k <= 5) $display("  ERROR: caso 1: %0d mm -> %0d / %0d (esperado %0d / %0d)",
                                     d, idx200, idx160, modelo(d, 200), modelo(d, 160));
            end
        end
        errores = errores + k;
        $display("Caso 1 (1 024 entradas, D_NEAR = 200 y 160) revisado: %0d diferencias", k);

        // ---- Caso 2 ----
        $display("Caso 2 (bordes, D_NEAR = 200):");
        borde(199, 0);  borde(200, 0);  borde(231, 0);  borde(232, 1);
        borde(679, 14); borde(680, 15); borde(711, 15); borde(712, 15);
        borde(859, 15); borde(1023, 15);

        // ---- Caso 3 ----
        $display("Caso 3 (requisito):");
        borde(300, 3);
        borde(600, 12);

        if (errores == 0) $display("PRUEBA EXITOSA: depth_quant paso todos los casos");
        else              $display("PRUEBA FALLIDA: %0d errores", errores);
        $finish;
    end

endmodule
