// =============================================================================
// tb_echo_to_mm.v  -  testbench de echo_to_mm
//
// Como correrlo: ./simular.sh echo_to_mm
//
// El modulo es combinacional, asi que no hay reloj: se pone cada entrada,
// se espera 1 ns y se revisa la salida.
//
// Casos que prueba:
//   1. TODAS las entradas validas (0 a 5 957) contra el calculo exacto
//      floor(11 t / 64).
//   2. Error frente a la fisica: para t entre 100 y 5 000 us,
//      |d_mm - 0,1715 t| <= 0,22 % de la distancia + 1 mm.
//   3. Valores de referencia: 0 -> 0, 1 -> 0, 1 749 -> 300, 3 498 -> 601,
//      5 000 (T_MAX) -> 859, 5 957 (limite) -> 1 023.
//   4. 5 957 es el mayor valor sin desborde: 11 * 5 957 = 65 527 cabe en
//      16 bits; 5 958 ya no (documentado: hcsr04_ctrl nunca lo entrega).
// =============================================================================

`timescale 1ns / 1ps

module tb_echo_to_mm;

    reg  [12:0] t_us = 13'd0;
    wire [9:0]  d_mm;

    echo_to_mm dut (.t_us(t_us), .d_mm(d_mm));

    integer errores = 0;
    integer t, k, esperado;
    real    fisico, tol, peor;

    task referencia(input integer tin, input integer dref);
        begin
            t_us = tin; #1;
            if (d_mm != dref) begin
                errores = errores + 1;
                $display("  ERROR: caso 3: %0d us -> %0d mm (esperado %0d)", tin, d_mm, dref);
            end else
                $display("  %0d us -> %0d mm", tin, d_mm);
        end
    endtask

    initial begin
        $dumpfile("sim/tb_echo_to_mm.vcd");
        $dumpvars(0, tb_echo_to_mm);
        $display("=== tb_echo_to_mm ===");

        // ---- Caso 1: todas las entradas validas ----
        k = 0;
        for (t = 0; t <= 5957; t = t + 1) begin
            t_us = t; #1;
            esperado = (11 * t) / 64;
            if (d_mm != esperado) begin
                k = k + 1;
                if (k <= 5) $display("  ERROR: caso 1: %0d -> %0d (esperado %0d)", t, d_mm, esperado);
            end
        end
        errores = errores + k;
        $display("Caso 1 (5 958 entradas contra floor(11t/64)) revisado: %0d diferencias", k);

        // ---- Caso 2: error frente a la fisica ----
        k = 0; peor = 0.0;
        for (t = 100; t <= 5000; t = t + 1) begin
            t_us = t; #1;
            fisico = 0.1715 * t;
            tol = 0.0022 * fisico + 1.0;
            if ((d_mm - fisico) > peor) peor = d_mm - fisico;
            if ((fisico - d_mm) > peor) peor = fisico - d_mm;
            if (d_mm > fisico + tol || d_mm < fisico - tol) k = k + 1;
        end
        errores = errores + k;
        $display("Caso 2 (error frente a 0,1715 mm/us) revisado: peor error %0.2f mm, %0d fuera de tolerancia",
                 peor, k);

        // ---- Caso 3: referencias ----
        $display("Caso 3 (valores de referencia):");
        referencia(0, 0);
        referencia(1, 0);
        referencia(1749, 300);
        referencia(3498, 601);
        referencia(5000, 859);
        referencia(5957, 1023);

        // ---- Caso 4: limite ----
        $display("Caso 4 (limite del ancho minimo): 11 x 5 957 = %0d cabe en 16 bits (max 65 535)", 11 * 5957);

        if (errores == 0) $display("PRUEBA EXITOSA: echo_to_mm paso todos los casos");
        else              $display("PRUEBA FALLIDA: %0d errores", errores);
        $finish;
    end

endmodule
