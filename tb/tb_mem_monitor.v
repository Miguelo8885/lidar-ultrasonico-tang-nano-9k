// =============================================================================
// tb_mem_monitor.v  -  testbench de mem_monitor (con la depth_ram real)
//
// Como correrlo: ./simular.sh mem_monitor
//
// Para que sea rapido se usa DIV = 4 (cada bit dura 4 ciclos en vez de 234);
// la logica es la misma. mem_monitor va conectado a una depth_ram de verdad,
// escrita con los mismos we, {row, col} e idx, como en el sistema. Un
// receptor UART arma cada linea y la compara con lo esperado: un modelo de
// la memoria y los datos del punto.
//
// Casos que prueba:
//   1. Sin we no sale nada: tx se queda en 1.
//   2. Un punto: la linea tiene 280 bytes, empieza con 'P', termina con '\n';
//      la cabecera trae fila, columna, color, las 3 mediciones (de la mas
//      vieja a la mas nueva), la mediana y los mm; las 256 palabras de la
//      RAM coinciden con el modelo (15 donde no se ha escrito).
//   3. Valores extremos: color 0 y 15, mediciones 0 y 8 191, 1 023 mm y
//      direccion 255; todos los digitos A..F y 0..9 bien convertidos.
//   4. 40 puntos al azar seguidos: cada linea coincide con la memoria del
//      momento.
//   5. Todos los bytes son 'P', '\n', '0'..'9' o 'A'..'F'.
//   6. Un we mientras se envia una linea se ignora (sale una sola linea).
//   7. Reset a mitad de una linea: tx vuelve al reposo y el siguiente punto
//      sale completo y correcto.
// =============================================================================

`timescale 1ns / 1ps

module tb_mem_monitor;

    localparam DIV = 4;

    reg         clk = 1'b0, rst = 1'b1;
    reg         done = 1'b0, we = 1'b0;
    reg  [12:0] t_us = 13'd0, med = 13'd0;
    reg  [3:0]  row = 4'd0, col = 4'd0, idx = 4'd0;
    reg  [9:0]  d_mm = 10'd0;
    wire [7:0]  raddr;
    wire [3:0]  rdata;
    wire        tx;

    mem_monitor #(.DIV(DIV)) dut (
        .clk(clk), .rst(rst), .done(done), .t_us(t_us), .we(we), .row(row), .col(col),
        .idx(idx), .med(med), .d_mm(d_mm), .raddr(raddr), .rdata(rdata), .tx(tx)
    );

    depth_ram u_ram (.wclk(clk), .we(we), .waddr({row, col}), .wdata(idx),
                     .rclk(clk), .raddr(raddr), .rdata(rdata));

    always #5 clk = ~clk;
    localparam TBIT = DIV * 10;

    integer errores = 0;

    task revisar(input cond, input [8*70-1:0] mensaje);
        begin
            if (!cond) begin
                errores = errores + 1;
                if (errores <= 15) $display("  ERROR (t = %0t): %0s", $time, mensaje);
            end
        end
    endtask

    // ---------------- receptor UART: arma lineas ---------------------------
    reg  [7:0] linea [0:399];
    integer    largo = 0, n_lineas = 0, n_bytes = 0, malos_char = 0, i;
    reg  [7:0] b;
    reg        lista = 1'b0;            // hay una linea completa sin revisar

    always @(negedge tx) begin
        #(TBIT / 2 + TBIT);
        for (i = 0; i < 8; i = i + 1) begin b[i] = tx; #(TBIT); end
        n_bytes = n_bytes + 1;
        if (!((b == 8'h50) || (b == 8'h0A) || (b >= 8'h30 && b <= 8'h39) || (b >= 8'h41 && b <= 8'h46)))
            malos_char = malos_char + 1;
        if (largo < 400) linea[largo] = b;
        largo = largo + 1;
        if (b == 8'h0A) begin n_lineas = n_lineas + 1; lista = 1'b1; end
    end

    // ---------------- modelo ------------------------------------------------
    reg  [3:0]  mem [0:255];
    reg  [12:0] e0, e1, e2, e_med;
    reg  [3:0]  e_row, e_col, e_idx;
    reg  [9:0]  e_mm;

    function [7:0] hx(input [3:0] v);
        hx = (v < 10) ? 8'h30 + v : 8'h37 + v;
    endfunction

    // revisa la ultima linea contra el modelo; devuelve el numero de fallas
    task revisar_linea;
        integer k, f;
        reg [87:0] h;
        begin
            f = 0;
            h = {e_row, e_col, e_idx, 3'b0, e0, 3'b0, e1, 3'b0, e2, 3'b0, e_med, 2'b0, e_mm};
            if (largo != 280)      f = f + 1;
            if (linea[0] != 8'h50) f = f + 1;
            if (linea[279] != 8'h0A) f = f + 1;
            for (k = 0; k < 22; k = k + 1)
                if (linea[1 + k] != hx(h[87 - 4 * k -: 4])) f = f + 1;
            for (k = 0; k < 256; k = k + 1)
                if (linea[23 + k] != hx(mem[k])) f = f + 1;
            revisar(f == 0, "la linea recibida no coincide con lo esperado");
            largo = 0; lista = 1'b0;
        end
    endtask

    // ---------------- estimulos ---------------------------------------------
    task medir(input [12:0] t);
        begin
            @(negedge clk) begin done = 1'b1; t_us = t; end
            @(negedge clk) done = 1'b0;
            repeat (5) @(negedge clk);
        end
    endtask

    // un punto completo: 3 mediciones y escritura
    task punto(input [3:0] r, input [3:0] c, input [3:0] ix,
               input [12:0] a, input [12:0] bb, input [12:0] cc, input [12:0] m, input [9:0] mm);
        begin
            medir(a); medir(bb); medir(cc);
            e0 = a; e1 = bb; e2 = cc; e_med = m; e_mm = mm; e_row = r; e_col = c; e_idx = ix;
            mem[{r, c}] = ix;
            @(negedge clk) begin we = 1'b1; row = r; col = c; idx = ix; med = m; d_mm = mm; end
            @(negedge clk) we = 1'b0;
        end
    endtask

    task esperar_linea;
        begin
            wait (lista == 1'b1);
            #(TBIT * 3);
        end
    endtask

    initial begin
        #(50_000_000);
        $display("PRUEBA FALLIDA: la simulacion no termino a tiempo (algo se trabo)");
        $finish;
    end

    integer k, n0, malos_antes;

    initial begin
        $dumpfile("sim/tb_mem_monitor.vcd");
        $dumpvars(0, tb_mem_monitor);
        $display("=== tb_mem_monitor ===  (DIV = %0d para acelerar)", DIV);
        for (k = 0; k < 256; k = k + 1) mem[k] = 4'hF;

        // ---- Caso 1 ----
        repeat (3) @(posedge clk);
        @(negedge clk) rst = 1'b0;
        medir(13'd1000);
        repeat (2000) @(posedge clk);
        revisar(n_bytes == 0 && tx == 1'b1, "caso 1: salio algo sin we");
        $display("Caso 1 (sin we no se envia nada) revisado");

        // ---- Caso 2 ----
        punto(4'd0, 4'd0, 4'd3, 13'd1749, 13'd2500, 13'd1600, 13'd1749, 10'd300);
        esperar_linea; revisar_linea;
        $display("Caso 2 (un punto: 280 bytes, cabecera y 256 palabras correctas) revisado: %s...",
                 {linea[0], linea[1], linea[2], linea[3]});

        // ---- Caso 3 ----
        punto(4'd15, 4'd15, 4'd0, 13'd0, 13'd8191, 13'h0ABC, 13'h1DEF, 10'd1023);
        esperar_linea; revisar_linea;
        punto(4'd11, 4'd11, 4'd15, 13'h0123, 13'h0456, 13'h0789, 13'h1FFF, 10'h2AB);
        esperar_linea; revisar_linea;
        $display("Caso 3 (valores extremos y digitos 0..9, A..F) revisado");

        // ---- Caso 4 ----
        malos_antes = errores;
        for (k = 0; k < 40; k = k + 1) begin
            punto($random % 12, $random % 12, $random, $random, $random, $random, $random, $random);
            esperar_linea; revisar_linea;
        end
        revisar(errores == malos_antes, "caso 4: alguna linea al azar no coincidio");
        $display("Caso 4 (40 puntos al azar, %0d lineas en total) revisado", n_lineas);

        // ---- Caso 5 ----
        revisar(malos_char == 0, "caso 5: se envio un caracter no permitido");
        $display("Caso 5 (%0d bytes, todos 'P', salto de linea o hexadecimal) revisado", n_bytes);

        // ---- Caso 6: we durante el envio ----
        n0 = n_lineas;
        punto(4'd5, 4'd6, 4'd9, 13'd10, 13'd20, 13'd30, 13'd20, 10'd3);
        repeat (DIV * 10 * 5) @(posedge clk);          // ya van ~5 bytes enviados
        @(negedge clk) begin we = 1'b1; row = 4'd0; col = 4'd1; idx = 4'd7; end   // la cabecera aun se esta enviando
        @(negedge clk) we = 1'b0;
        mem[8'h01] = 4'd7;                             // la RAM si se escribe
        esperar_linea;
        revisar(largo == 280, "caso 6: la linea no tiene 280 bytes");
        revisar_linea;                                 // DUMP aun no habia llegado a la dir. 1
        repeat (DIV * 10 * 400) @(posedge clk);
        revisar(n_lineas == n0 + 1, "caso 6: un we durante el envio genero otra linea");
        $display("Caso 6 (we durante el envio se ignora) revisado");

        // ---- Caso 7: reset a mitad de linea ----
        punto(4'd2, 4'd2, 4'd4, 13'd1, 13'd2, 13'd3, 13'd2, 10'd5);
        repeat (DIV * 10 * 100) @(posedge clk);        // en medio de DUMP
        @(negedge clk) rst = 1'b1;
        @(negedge clk) rst = 1'b0;
        #1 revisar(tx == 1'b1, "caso 7: tx no volvio a 1 con el reset");
        repeat (DIV * 10 * 20) @(posedge clk);
        largo = 0; lista = 1'b0; n0 = n_lineas;
        punto(4'd3, 4'd4, 4'd6, 13'd11, 13'd22, 13'd33, 13'd22, 10'd44);
        esperar_linea; revisar_linea;
        revisar(n_lineas == n0 + 1, "caso 7: despues del reset no salio una linea");
        $display("Caso 7 (reset a mitad de linea; el siguiente punto sale completo) revisado");

        if (errores == 0) $display("PRUEBA EXITOSA: mem_monitor paso todos los casos");
        else              $display("PRUEBA FALLIDA: %0d errores", errores);
        $finish;
    end

endmodule
