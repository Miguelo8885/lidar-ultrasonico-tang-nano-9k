// =============================================================================
// tb_uart_tx.v  -  testbench de uart_tx
//
// Como correrlo: ./simular.sh uart_tx
//
// Reloj real de 27 MHz y DIV = 234. Un RECEPTOR UART independiente (como el
// del chip USB) espera la bajada del bit de inicio, se ubica en la mitad de
// cada bit y lo lee; revisa el bit de inicio, el dato y el bit de parada.
//
// Casos que prueba:
//   1. Despues del reset: tx = 1 (reposo), busy = 0, sin bdone.
//   2. Enviar 0x55, 0xA3, 0x00, 0xFF, 0x80, 0x01: el receptor los lee bien.
//   3. Duracion: cada bit dura 234 ciclos; busy dura 2 340 ciclos (10 bits)
//      y la velocidad resultante es 115 385 baudios.
//   4. bdone: exactamente un pulso por byte, en el ciclo en que busy baja.
//   5. start mientras busy = 1 se ignora: el byte en curso no cambia y no
//      se envia un byte extra.
//   6. Bytes seguidos: start dos ciclos despues de bdone (como mem_monitor).
//   7. Reset a mitad de un byte: tx vuelve a 1 y busy a 0 en el siguiente
//      flanco; despues se puede enviar normalmente.
// =============================================================================

`timescale 1ns / 1fs

module tb_uart_tx;

    reg        clk = 1'b0, rst = 1'b1, start = 1'b0;
    reg  [7:0] data = 8'd0;
    wire       tx, busy, bdone;

    uart_tx #(.DIV(234)) dut (.clk(clk), .rst(rst), .start(start), .data(data),
                              .tx(tx), .busy(busy), .bdone(bdone));

    always #18.5185 clk = ~clk;     // 27 MHz
    localparam real TCLK = 37.037;
    localparam real TBIT = 234 * TCLK;

    integer errores = 0;

    task revisar(input cond, input [8*64-1:0] mensaje);
        begin
            if (!cond) begin
                errores = errores + 1;
                $display("  ERROR (t = %0.1f us): %0s", $realtime / 1000.0, mensaje);
            end
        end
    endtask

    // ---------------- receptor UART -----------------------------------------
    reg  [7:0] rx_byte;
    integer    n_rx = 0, malos_trama = 0, i;
    reg  [7:0] recibidos [0:31];
    reg        rx_on = 1'b1;

    always @(negedge tx) if (rx_on) begin
        #(TBIT / 2);
        if (tx !== 1'b0) malos_trama = malos_trama + 1;      // bit de inicio
        for (i = 0; i < 8; i = i + 1) begin
            #(TBIT);
            rx_byte[i] = tx;
        end
        #(TBIT);
        if (tx !== 1'b1) malos_trama = malos_trama + 1;      // bit de parada
        recibidos[n_rx] = rx_byte;
        n_rx = n_rx + 1;
    end

    // ---------------- medidores ---------------------------------------------
    integer n_bdone = 0, bdone_sin_bajar = 0;
    integer ciclos_busy = 0, ultimo_busy = 0;
    reg     busy_ant = 1'b0;

    always @(posedge clk) begin
        if (bdone) begin
            n_bdone = n_bdone + 1;
        end
        if (busy) ciclos_busy = ciclos_busy + 1;
        if (busy_ant && !busy) begin
            ultimo_busy = ciclos_busy;
            ciclos_busy = 0;
        end
        busy_ant = busy;
    end
    // bdone debe coincidir con el ciclo en que busy pasa a 0
    always @(negedge clk) if (bdone) #(TCLK) if (busy) bdone_sin_bajar = bdone_sin_bajar + 1;

    // ---------------- tareas -------------------------------------------------
    task enviar(input [7:0] b);
        begin
            @(negedge clk) begin start = 1'b1; data = b; end
            @(negedge clk) start = 1'b0;
        end
    endtask

    task esperar_fin;
        begin
            @(posedge clk); while (!bdone) @(posedge clk);
            @(negedge clk);
        end
    endtask

    // ---------------- tiempo limite -----------------------------------------
    initial begin
        #(20_000_000);
        $display("PRUEBA FALLIDA: la simulacion no termino a tiempo (algo se trabo)");
        $finish;
    end

    reg [7:0] lista [0:5];
    integer k, n0, b0;
    realtime t_baja, t_sube;

    initial begin
        $dumpfile("sim/tb_uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
        $display("=== tb_uart_tx ===  (27 MHz, DIV = 234)");
        lista[0] = 8'h55; lista[1] = 8'hA3; lista[2] = 8'h00;
        lista[3] = 8'hFF; lista[4] = 8'h80; lista[5] = 8'h01;

        // ---- Caso 1 ----
        repeat (3) @(posedge clk);
        @(negedge clk) rst = 1'b0;
        repeat (500) @(posedge clk);
        revisar(tx == 1'b1 && busy == 1'b0 && n_bdone == 0, "caso 1: no esta en reposo tras el reset");
        $display("Caso 1 (reposo: tx = 1, busy = 0) revisado");

        // ---- Casos 2, 3 y 4 ----
        for (k = 0; k < 6; k = k + 1) begin
            enviar(lista[k]);
            if (k == 0) begin
                t_baja = $realtime;               // tx baja en el flanco de carga
            end
            esperar_fin;
            repeat (300) @(posedge clk);
            revisar(ultimo_busy == 2340, "caso 3: busy no duro 2 340 ciclos");
        end
        revisar(n_rx == 6, "caso 2: el receptor no recibio 6 bytes");
        for (k = 0; k < 6; k = k + 1)
            revisar(recibidos[k] == lista[k], "caso 2: byte recibido distinto");
        revisar(malos_trama == 0, "caso 2: bit de inicio o de parada incorrecto");
        $display("Caso 2 (6 bytes recibidos: %h %h %h %h %h %h) revisado",
                 recibidos[0], recibidos[1], recibidos[2], recibidos[3], recibidos[4], recibidos[5]);
        $display("Caso 3 (busy = %0d ciclos = 10 bits de 234; %0d baudios) revisado",
                 ultimo_busy, $rtoi(27_000_000.0 / 234.0));
        revisar(n_bdone == 6 && bdone_sin_bajar == 0, "caso 4: bdone no es un pulso por byte al bajar busy");
        $display("Caso 4 (bdone: %0d pulsos para 6 bytes, al bajar busy) revisado", n_bdone);

        // ---- Medicion directa de un bit: 0x55 alterna 0/1 en cada bit ----
        @(negedge clk) begin start = 1'b1; data = 8'h55; end
        @(negedge clk) start = 1'b0;
        @(posedge tx) t_sube = $realtime;            // fin del bit de inicio
        @(negedge tx);
        revisar(($realtime - t_sube) > TBIT - 1.0 && ($realtime - t_sube) < TBIT + 1.0,
                "caso 3: un bit no dura 234 ciclos");
        $display("Caso 3 (un bit dura %0.3f us = 234 ciclos) revisado", ($realtime - t_sube) / 1000.0);
        esperar_fin; repeat (300) @(posedge clk);

        // ---- Caso 5: start con busy = 1 ----
        n0 = n_rx; b0 = n_bdone;
        enviar(8'h3C);
        repeat (1000) @(posedge clk);
        enviar(8'hC3);                               // se debe ignorar
        esperar_fin; repeat (3000) @(posedge clk);
        revisar(n_rx == n0 + 1 && recibidos[n0] == 8'h3C, "caso 5: start con busy = 1 no se ignoro");
        revisar(n_bdone == b0 + 1, "caso 5: hubo un bdone extra");
        $display("Caso 5 (start con busy = 1 se ignora) revisado");

        // ---- Caso 6: bytes seguidos ----
        n0 = n_rx;
        enviar(8'h50);
        esperar_fin;                                 // estamos en negedge del ciclo de bdone
        @(negedge clk);                              // +1 ciclo
        start = 1'b1; data = 8'h0A;                  // start 2 ciclos despues de bdone
        @(negedge clk) start = 1'b0;
        esperar_fin; repeat (300) @(posedge clk);
        revisar(n_rx == n0 + 2 && recibidos[n0] == 8'h50 && recibidos[n0 + 1] == 8'h0A,
                "caso 6: bytes seguidos mal recibidos");
        $display("Caso 6 (dos bytes seguidos: %h %h) revisado", recibidos[n0], recibidos[n0 + 1]);

        // ---- Caso 7: reset a mitad de un byte ----
        rx_on = 1'b0;
        enviar(8'h00);
        repeat (900) @(posedge clk);
        @(negedge clk) rst = 1'b1;
        @(posedge clk); #1;
        revisar(tx == 1'b1 && busy == 1'b0, "caso 7: el reset no devolvio la linea al reposo");
        @(negedge clk) rst = 1'b0;
        repeat (3000) @(posedge clk);
        rx_on = 1'b1; n0 = n_rx;
        enviar(8'h7E); esperar_fin; repeat (300) @(posedge clk);
        revisar(n_rx == n0 + 1 && recibidos[n0] == 8'h7E, "caso 7: no envio bien despues del reset");
        $display("Caso 7 (reset a mitad de byte y envio posterior) revisado");

        if (errores == 0) $display("PRUEBA EXITOSA: uart_tx paso todos los casos");
        else              $display("PRUEBA FALLIDA: %0d errores", errores);
        $finish;
    end

endmodule
