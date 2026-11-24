// =============================================================================
// tb_depth_ram.v  -  testbench de depth_ram
//
// Como correrlo: ./simular.sh depth_ram
//
// Corren los DOS relojes reales a la vez: wclk de 27 MHz (escritura) y rclk
// de 25,2 MHz (lectura). Las senales de cada puerto se cambian solo en su
// propio dominio, como sera en el sistema.
//
// Casos que prueba:
//   1. Contenido inicial: las 256 palabras leen 15 (negro).
//   2. Escribir los 144 puntos {row, col} con un patron y leerlos todos desde
//      el reloj de lectura: coinciden.
//   3. Latencia: rdata cambia en el flanco de rclk SIGUIENTE a poner raddr,
//      no antes.
//   4. we = 0: cambiar waddr y wdata no escribe nada.
//   5. Sobrescribir una palabra.
//   6. Escribir direcciones no usadas (fila 12 a 15) no altera las 144 validas.
//   7. Escrituras en ciclos consecutivos de wclk.
//   8. Leer continuamente una palabra mientras se escribe sin parar con dos
//      valores alternos: cada lectura da uno de esos valores, nunca otro.
// =============================================================================

`timescale 1ns / 1ps

module tb_depth_ram;

    reg        wclk = 1'b0, rclk = 1'b0;
    reg        we = 1'b0;
    reg  [7:0] waddr = 8'd0, raddr = 8'd0;
    reg  [3:0] wdata = 4'd0;
    wire [3:0] rdata;

    depth_ram dut (
        .wclk(wclk), .we(we), .waddr(waddr), .wdata(wdata),
        .rclk(rclk), .raddr(raddr), .rdata(rdata)
    );

    always #18.5185 wclk = ~wclk;      // 27 MHz
    always #19.8413 rclk = ~rclk;      // 25,2 MHz

    integer errores = 0;

    // Valor de prueba para cada punto
    function [3:0] patron(input [3:0] r, input [3:0] c);
        patron = (r * 7 + c * 3) % 15;
    endfunction

    // ----- puerto de escritura (dominio wclk) -----
    task escribir(input [7:0] a, input [3:0] d);
        begin
            @(negedge wclk) begin we = 1'b1; waddr = a; wdata = d; end
            @(negedge wclk) we = 1'b0;
        end
    endtask

    // ----- puerto de lectura (dominio rclk) -----
    task automatic leer(input [7:0] a, output [3:0] d);
        begin
            @(negedge rclk) raddr = a;
            @(posedge rclk) #1 d = rdata;
        end
    endtask

    task revisar(input cond, input [8*60-1:0] mensaje);
        begin
            if (!cond) begin
                errores = errores + 1;
                if (errores <= 10) $display("  ERROR: %0s", mensaje);
            end
        end
    endtask

    integer r, c, k, malos;
    reg [3:0] v, previo;
    reg       detener;

    initial begin
        $dumpfile("sim/tb_depth_ram.vcd");
        $dumpvars(0, tb_depth_ram);
        $display("=== tb_depth_ram ===  (wclk 27 MHz, rclk 25,2 MHz)");

        // ---- Caso 1 ----
        malos = 0;
        for (k = 0; k < 256; k = k + 1) begin
            leer(k, v);
            if (v != 4'hF) malos = malos + 1;
        end
        revisar(malos == 0, "caso 1: contenido inicial distinto de 15");
        $display("Caso 1 (contenido inicial = 15 en las 256 palabras) revisado");

        // ---- Caso 2 ----
        for (r = 0; r < 12; r = r + 1)
            for (c = 0; c < 12; c = c + 1)
                escribir({r[3:0], c[3:0]}, patron(r, c));
        malos = 0;
        for (r = 0; r < 12; r = r + 1)
            for (c = 0; c < 12; c = c + 1) begin
                leer({r[3:0], c[3:0]}, v);
                if (v != patron(r, c)) malos = malos + 1;
            end
        revisar(malos == 0, "caso 2: lo leido no coincide con lo escrito");
        $display("Caso 2 (144 puntos escritos a 27 MHz y leidos a 25,2 MHz) revisado: %0d diferencias", malos);

        // ---- Caso 3: latencia ----
        @(negedge rclk) raddr = {4'd0, 4'd1};
        @(posedge rclk) #1 previo = rdata;               // ya muestra (0,1)
        @(negedge rclk) raddr = {4'd2, 4'd2};
        #1 revisar(rdata == previo, "caso 3: rdata cambio antes del flanco de rclk");
        @(posedge rclk) #1 revisar(rdata == patron(2, 2), "caso 3: rdata no cambio en el flanco siguiente");
        $display("Caso 3 (latencia de un ciclo de rclk) revisado");

        // ---- Caso 4: we = 0 ----
        for (k = 0; k < 20; k = k + 1) begin
            @(negedge wclk) begin waddr = k; wdata = 4'd9; end   // we sigue en 0
        end
        malos = 0;
        for (k = 0; k < 20; k = k + 1) begin
            leer(k, v);
            if (v != patron(k[7:4], k[3:0]) && k[3:0] < 12) malos = malos + 1;
        end
        revisar(malos == 0, "caso 4: escribio con we = 0");
        $display("Caso 4 (we = 0 no escribe) revisado");

        // ---- Caso 5: sobrescribir ----
        escribir({4'd5, 4'd5}, 4'd14);
        leer({4'd5, 4'd5}, v);
        revisar(v == 4'd14, "caso 5: no se sobrescribio");
        $display("Caso 5 (sobrescribir) revisado");
        escribir({4'd5, 4'd5}, patron(5, 5));

        // ---- Caso 6: direcciones no usadas ----
        for (k = 192; k < 256; k = k + 1) escribir(k, 4'd0);     // filas 12 a 15
        malos = 0;
        for (r = 0; r < 12; r = r + 1)
            for (c = 0; c < 12; c = c + 1) begin
                leer({r[3:0], c[3:0]}, v);
                if (v != patron(r, c)) malos = malos + 1;
            end
        revisar(malos == 0, "caso 6: escribir filas 12-15 altero puntos validos");
        $display("Caso 6 (direcciones no usadas no alteran las validas) revisado");

        // ---- Caso 7: escrituras consecutivas ----
        @(negedge wclk) begin we = 1'b1; waddr = 8'h00; wdata = 4'd1; end
        @(negedge wclk) begin waddr = 8'h01; wdata = 4'd2; end
        @(negedge wclk) begin waddr = 8'h02; wdata = 4'd3; end
        @(negedge wclk) we = 1'b0;
        leer(8'h00, v); revisar(v == 4'd1, "caso 7: escritura consecutiva 1");
        leer(8'h01, v); revisar(v == 4'd2, "caso 7: escritura consecutiva 2");
        leer(8'h02, v); revisar(v == 4'd3, "caso 7: escritura consecutiva 3");
        $display("Caso 7 (tres escrituras en ciclos seguidos) revisado");

        // ---- Caso 8: lectura y escritura simultaneas de la misma palabra ----
        detener = 0; malos = 0;
        fork
            begin                                   // escritor: alterna 6 y 9
                for (k = 0; k < 400; k = k + 1) begin
                    @(negedge wclk) begin we = 1'b1; waddr = 8'h33; wdata = (k % 2) ? 4'd9 : 4'd6; end
                end
                @(negedge wclk) we = 1'b0;
                detener = 1;
            end
            begin                                   // lector: lee sin parar
                @(negedge rclk) raddr = 8'h33;
                @(posedge rclk);
                while (!detener) begin
                    @(posedge rclk) #1;
                    if (rdata != 4'd6 && rdata != 4'd9 && rdata != patron(3, 3)) malos = malos + 1;
                end
            end
        join
        revisar(malos == 0, "caso 8: lectura simultanea dio un valor que nunca se escribio");
        $display("Caso 8 (lectura y escritura simultaneas: siempre valor viejo o nuevo) revisado");

        if (errores == 0) $display("PRUEBA EXITOSA: depth_ram paso todos los casos");
        else              $display("PRUEBA FALLIDA: %0d errores", errores);
        $finish;
    end

endmodule
