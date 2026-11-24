// =============================================================================
// tb_hcsr04_ctrl.v  -  testbench de hcsr04_ctrl
//
// Como correrlo: ./simular.sh hcsr04_ctrl
//
// Para que sea rapido, tick llega cada 3 ciclos (en la tarjeta, cada 27).
// Aqui "1 us" = 1 tick = 3 ciclos. Un MODELO del sensor responde al trig:
// espera un tiempo, sube Echo, lo mantiene el tiempo pedido y lo baja.
// Echo se maneja ya sincronizado (como sale de sync_ff).
//
// Como start y Echo llegan en cualquier momento entre dos ticks, la medicion
// tiene un error de +-1 us (unos 0,17 mm). Se acepta esa tolerancia.
//
// Casos que prueba:
//   1. Reset: trig = 0, done = 0, t_us = 0.
//   2. Medicion normal (Echo de 1 749 us ~ 300 mm): t_us = 1 749 +-1;
//      trig dura entre 11 y 12 us; done llega cuando Echo ya bajo.
//   3. Sin eco (Echo nunca sube): done a los RISE_MAX us, t_us = T_MAX.
//   4. Eco lejano (Echo de 38 ms, como el HC-SR04 sin obstaculo):
//      t_us = T_MAX y done solo despues de que Echo baja.
//   5. Echo pegado en alto: done llega por FALL_MAX y t_us = T_MAX.
//   6. start durante una medicion: se ignora (un solo trig).
//   7. Ecos limite: 1 us y T_MAX - 1 us (este ultimo NO se satura).
//   8. Reset a mitad de la medicion: vuelve a IDLE y la siguiente medicion
//      funciona normal.
//   9. (Todo el tiempo) done dura un ciclo; trig nunca sube sin start.
// =============================================================================

`timescale 1ns / 1ps

module tb_hcsr04_ctrl;

    localparam TDIV = 3;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         start = 1'b0;
    reg         echo = 1'b0;
    wire        tick, trig, done;
    wire [12:0] t_us;

    reg [1:0] tdiv = 2'd0;
    always @(posedge clk) tdiv <= (tdiv == TDIV - 1) ? 2'd0 : tdiv + 2'd1;
    assign tick = (tdiv == TDIV - 1);

    hcsr04_ctrl dut (
        .clk(clk), .rst(rst), .tick(tick), .start(start), .echo(echo),
        .trig(trig), .t_us(t_us), .done(done)
    );

    always #18.5185 clk = ~clk;

    integer errores = 0;

    task revisar(input cond, input [8*70-1:0] mensaje);
        begin
            if (!cond) begin
                errores = errores + 1;
                $display("  ERROR (t = %0t ns): %0s  [t_us = %0d]", $time, mensaje, t_us);
            end
        end
    endtask

    // ---------------- monitor ----------------------------------------------
    integer n_done = 0, n_trig = 0, trig_ciclos = 0, ultimo_trig = 0;
    reg done_prev = 0, trig_prev = 0;
    always @(negedge clk) begin
        if (done) n_done = n_done + 1;
        if (done && done_prev) begin
            errores = errores + 1; $display("  ERROR: done duro mas de un ciclo");
        end
        // done con Echo en alto solo se permite por el limite FALL_MAX
        if (done && echo && !dut.tdone) begin
            errores = errores + 1; $display("  ERROR: done con Echo todavia en alto");
        end
        if (trig) trig_ciclos = trig_ciclos + 1;
        if (trig && !trig_prev) begin n_trig = n_trig + 1; trig_ciclos = 1; end
        if (!trig && trig_prev) ultimo_trig = trig_ciclos;
        done_prev = done; trig_prev = trig;
    end

    task automatic esperar_ticks(input integer m);
        integer k;
        begin
            k = 0;
            while (k < m) begin @(negedge clk); if (tick) k = k + 1; end
        end
    endtask

    task automatic pulsar_start;
        begin
            @(negedge clk) start = 1'b1;
            @(negedge clk) start = 1'b0;
        end
    endtask

    // Modelo del sensor: tras bajar trig espera 'retardo' us, sube Echo
    // durante 'ancho' us (ancho = 0: no sube nunca; ancho < 0: se queda pegado)
    task automatic sensor(input integer retardo, input integer ancho);
        begin
            @(negedge trig);
            esperar_ticks(retardo);
            // Echo cambia justo despues de un flanco de subida, como la
            // salida real de sync_ff
            if (ancho != 0) begin
                @(posedge clk) #1 echo = 1'b1;
                if (ancho > 0) begin
                    esperar_ticks(ancho);
                    @(posedge clk) #1 echo = 1'b0;
                end
            end
        end
    endtask

    // Una medicion completa: start + sensor, espera done
    task automatic medir(input integer ancho, output integer duracion_us);
        integer objetivo, t0;
        begin
            objetivo = n_done + 1;
            t0 = $time;
            fork
                pulsar_start;
                sensor(450, ancho);
            join
            while (n_done < objetivo) @(negedge clk);
            duracion_us = ($time - t0) / (37.037 * TDIV);
        end
    endtask

    function integer abs(input integer v);
        abs = (v < 0) ? -v : v;
    endfunction

    // ---------------- tiempo limite ----------------------------------------
    initial begin
        #(200_000_000);
        $display("PRUEBA FALLIDA: la simulacion no termino a tiempo (algo se trabo)");
        $finish;
    end

    integer dur;

    initial begin
        $dumpfile("sim/tb_hcsr04_ctrl.vcd");
        $dumpvars(0, tb_hcsr04_ctrl);
        $display("=== tb_hcsr04_ctrl ===  (1 us = %0d ciclos en esta simulacion)", TDIV);

        // ---- Caso 1 ----
        repeat (5) @(negedge clk);
        revisar(trig == 0 && done == 0 && t_us == 0, "caso 1: salidas no estan en 0 con reset");
        rst = 1'b0;
        esperar_ticks(50);
        revisar(trig == 0 && n_trig == 0, "caso 9: trig subio sin start");
        $display("Caso 1 (reset) revisado");

        // ---- Caso 2: medicion normal ----
        medir(1749, dur);
        revisar(abs(t_us - 1749) <= 1, "caso 2: el ancho medido no es 1 749 +-1 us");
        revisar(ultimo_trig >= 11 * TDIV && ultimo_trig <= 12 * TDIV, "caso 2: trig no duro entre 11 y 12 us");
        $display("Caso 2 (medicion normal) revisado: t_us = %0d, trig = %0d ciclos (%0d a %0d)",
                 t_us, ultimo_trig, 11 * TDIV, 12 * TDIV);

        // ---- Caso 3: sin eco ----
        esperar_ticks(100);
        medir(0, dur);
        revisar(t_us == 5000, "caso 3: sin eco no dio T_MAX");
        revisar(dur >= 5000 && dur <= 5020, "caso 3: done no llego a los RISE_MAX us");
        $display("Caso 3 (sin eco) revisado: t_us = %0d, done a los %0d us del start", t_us, dur);

        // ---- Caso 4: eco lejano de 38 ms ----
        esperar_ticks(100);
        medir(38000, dur);
        revisar(t_us == 5000, "caso 4: eco lejano no dio T_MAX");
        revisar(dur >= 38000 + 450, "caso 4: done llego antes de que Echo bajara");
        $display("Caso 4 (eco de 38 ms) revisado: t_us = %0d, done a los %0d us", t_us, dur);

        // ---- Caso 7: ecos limite ----
        esperar_ticks(100);
        medir(1, dur);
        revisar(t_us <= 2, "caso 7: eco de 1 us mal medido");
        $display("Caso 7a (eco de 1 us) revisado: t_us = %0d", t_us);
        esperar_ticks(100);
        medir(4999, dur);
        revisar(abs(t_us - 4999) <= 1, "caso 7: eco de T_MAX-1 mal medido");
        $display("Caso 7b (eco de 4 999 us) revisado: t_us = %0d", t_us);

        // ---- Caso 6: start durante la medicion ----
        esperar_ticks(100);
        n_trig = 0;
        fork
            medir(1000, dur);
            begin
                esperar_ticks(600);         // a mitad de la medicion
                @(negedge clk) start = 1'b1;
                @(negedge clk) start = 1'b0;
            end
        join
        esperar_ticks(3000);
        revisar(n_trig == 1, "caso 6: start durante la medicion genero otro trig");
        revisar(abs(t_us - 1000) <= 1, "caso 6: la medicion se altero");
        $display("Caso 6 (start durante la medicion ignorado) revisado");

        // ---- Caso 5: Echo pegado en alto ----
        esperar_ticks(100);
        medir(-1, dur);
        revisar(t_us == 5000, "caso 5: Echo pegado no dio T_MAX");
        revisar(dur >= 5000 + 40000, "caso 5: done llego antes de FALL_MAX");
        $display("Caso 5 (Echo pegado en alto) revisado: done a los %0d us", dur);
        @(posedge clk) #1 echo = 1'b0;

        // ---- Caso 8: reset a mitad ----
        esperar_ticks(100);
        fork
            pulsar_start;
            sensor(450, 3000);
            begin
                esperar_ticks(1500);        // en MEASURE
                @(negedge clk) rst = 1'b1;
                @(negedge clk) rst = 1'b0;
                revisar(dut.state == 3'b000 && trig == 0, "caso 8: reset no llevo a IDLE");
            end
        join
        wait (echo == 1'b0);
        esperar_ticks(100);
        medir(2500, dur);
        revisar(abs(t_us - 2500) <= 1, "caso 8: tras el reset la medicion fallo");
        $display("Caso 8 (reset a mitad) revisado");

        $display("Caso 9 (done de un ciclo, trig solo con start) revisado durante toda la prueba");
        if (errores == 0) $display("PRUEBA EXITOSA: hcsr04_ctrl paso todos los casos");
        else              $display("PRUEBA FALLIDA: %0d errores", errores);
        $finish;
    end

endmodule
