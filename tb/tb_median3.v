// =============================================================================
// tb_median3.v  -  testbench de median3
//
// Como correrlo: ./simular.sh median3
//
// El testbench tiene su PROPIO calculo de la mediana (ordenando los tres
// valores) y compara el modulo contra el en cada caso.
//
// Casos que prueba:
//   1. Reset: los tres registros y la salida en 0.
//   2. Las 6 permutaciones de 100, 200, 300: siempre 200.
//   3. Dos valores iguales en todas las posiciones (100,100,300 y 300,300,100).
//   4. Tres iguales.
//   5. Un "sin eco" (5 000) entre dos lecturas buenas: da una lectura buena.
//   6. Dos "sin eco" y una lectura: da 5 000 (el punto es fondo).
//   7. Extremos: 0, 1 y 8 191 (todos los bits en 1).
//   8. Sin din_valid la salida no cambia aunque din cambie.
//   9. Una cuarta medicion desplaza la mas vieja.
//  10. 2 000 trios aleatorios (la mitad con valores repetidos) contra el modelo.
// =============================================================================

`timescale 1ns / 1ps

module tb_median3;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg  [12:0] din = 13'd0;
    reg         din_valid = 1'b0;
    wire [12:0] med;

    median3 dut (.clk(clk), .rst(rst), .din(din), .din_valid(din_valid), .med(med));

    always #18.5185 clk = ~clk;

    integer errores = 0;

    task revisar(input cond, input [8*70-1:0] mensaje);
        begin
            if (!cond) begin
                errores = errores + 1;
                $display("  ERROR: %0s  [r0=%0d r1=%0d r2=%0d med=%0d]",
                         mensaje, dut.r0, dut.r1, dut.r2, med);
            end
        end
    endtask

    // Modelo: mediana de tres valores
    function [12:0] mediana(input [12:0] a, input [12:0] b, input [12:0] c);
        begin
            if ((a >= b && a <= c) || (a <= b && a >= c))      mediana = a;
            else if ((b >= a && b <= c) || (b <= a && b >= c)) mediana = b;
            else                                                mediana = c;
        end
    endfunction

    // Entrega una medicion (pulso de din_valid de un ciclo)
    task meter(input [12:0] v);
        begin
            @(negedge clk) begin din = v; din_valid = 1'b1; end
            @(negedge clk) din_valid = 1'b0;
        end
    endtask

    // Mete tres valores y revisa la mediana
    task trio(input [12:0] a, input [12:0] b, input [12:0] c, input [8*40-1:0] caso);
        begin
            meter(a); meter(b); meter(c);
            revisar(med == mediana(a, b, c), caso);
        end
    endtask

    integer i, k;
    reg [12:0] a, b, c, guardada;
    reg [12:0] p [0:2];

    initial begin
        $dumpfile("sim/tb_median3.vcd");
        $dumpvars(0, tb_median3);
        $display("=== tb_median3 ===");

        // ---- Caso 1 ----
        repeat (3) @(negedge clk);
        revisar(dut.r0 == 0 && dut.r1 == 0 && dut.r2 == 0 && med == 0, "caso 1: reset");
        rst = 1'b0;
        $display("Caso 1 (reset) revisado");

        // ---- Caso 2: permutaciones ----
        trio(100, 200, 300, "caso 2"); revisar(med == 200, "caso 2: no dio 200");
        trio(100, 300, 200, "caso 2"); revisar(med == 200, "caso 2: no dio 200");
        trio(200, 100, 300, "caso 2"); revisar(med == 200, "caso 2: no dio 200");
        trio(200, 300, 100, "caso 2"); revisar(med == 200, "caso 2: no dio 200");
        trio(300, 100, 200, "caso 2"); revisar(med == 200, "caso 2: no dio 200");
        trio(300, 200, 100, "caso 2"); revisar(med == 200, "caso 2: no dio 200");
        $display("Caso 2 (6 permutaciones de 100, 200, 300 -> 200) revisado");

        // ---- Caso 3: dos iguales ----
        trio(100, 100, 300, "caso 3"); trio(100, 300, 100, "caso 3"); trio(300, 100, 100, "caso 3");
        trio(300, 300, 100, "caso 3"); trio(300, 100, 300, "caso 3"); trio(100, 300, 300, "caso 3");
        $display("Caso 3 (dos valores iguales en todas las posiciones) revisado");

        // ---- Caso 4 ----
        trio(777, 777, 777, "caso 4: tres iguales");
        $display("Caso 4 (tres iguales) revisado");

        // ---- Caso 5 y 6: sin eco ----
        trio(1749, 5000, 1752, "caso 5"); revisar(med == 1752, "caso 5: el sin eco no se descarto");
        trio(5000, 1749, 1750, "caso 5"); revisar(med == 1750, "caso 5: el sin eco no se descarto");
        $display("Caso 5 (un sin eco entre lecturas buenas: se descarta) revisado: med = %0d", med);
        trio(5000, 1749, 5000, "caso 6"); revisar(med == 5000, "caso 6: dos sin eco no dieron fondo");
        $display("Caso 6 (dos sin eco: fondo) revisado");

        // ---- Caso 7: extremos ----
        trio(0, 8191, 1, "caso 7"); revisar(med == 1, "caso 7: extremos");
        trio(8191, 8191, 0, "caso 7"); revisar(med == 8191, "caso 7: extremos");
        trio(0, 0, 8191, "caso 7"); revisar(med == 0, "caso 7: extremos");
        $display("Caso 7 (extremos 0, 1 y 8 191) revisado");

        // ---- Caso 8: sin din_valid no cambia ----
        guardada = med;
        for (i = 0; i < 20; i = i + 1) @(negedge clk) din = i * 397;
        revisar(med == guardada, "caso 8: la salida cambio sin din_valid");
        $display("Caso 8 (sin din_valid la salida no cambia) revisado");

        // ---- Caso 9: la cuarta desplaza a la mas vieja ----
        meter(10); meter(20); meter(30);          // r2=10 r1=20 r0=30
        meter(40);                                 // r2=20 r1=30 r0=40
        revisar(dut.r2 == 20 && dut.r1 == 30 && dut.r0 == 40, "caso 9: desplazamiento");
        revisar(med == 30, "caso 9: mediana tras desplazar");
        $display("Caso 9 (la cuarta medicion desplaza la mas vieja) revisado");

        // ---- Caso 10: aleatorio ----
        k = 0;
        for (i = 0; i < 2000; i = i + 1) begin
            if (i % 2 == 0) begin                  // rango completo
                a = $random; b = $random; c = $random;
            end else begin                         // pocos valores: muchos empates
                a = ($random & 3) * 1000; b = ($random & 3) * 1000; c = ($random & 3) * 1000;
            end
            meter(a); meter(b); meter(c);
            if (med != mediana(a, b, c)) begin
                k = k + 1;
                if (k <= 5) $display("  ERROR: caso 10: %0d %0d %0d -> %0d (esperado %0d)",
                                     a, b, c, med, mediana(a, b, c));
            end
        end
        errores = errores + k;
        $display("Caso 10 (2 000 trios aleatorios contra el modelo) revisado: %0d diferencias", k);

        if (errores == 0) $display("PRUEBA EXITOSA: median3 paso todos los casos");
        else              $display("PRUEBA FALLIDA: %0d errores", errores);
        $finish;
    end

endmodule
