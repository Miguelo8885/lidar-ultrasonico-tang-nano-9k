// =============================================================================
// tb_lidar_top.v  -  prueba del SISTEMA COMPLETO (sensor + servos, sin video)
//
// Como correrlo: ./simular.sh lidar_top     (tarda un par de minutos)
// (usa todos los modulos de rtl/ y por_gen)
//
// Todo corre a VELOCIDAD REAL: reloj de 27 MHz, tick cada 27 ciclos, periodo
// del servo de 20 ms, antirrebote de 20 ms y esperas de N = 4 frames.
// Un MODELO del sensor responde a cada pulso de trig con un Echo de 1 749 us
// (un objeto a 300 mm), 2,2 ms despues (retardo medido en el sensor real).
//
// Se revisa lo mismo que se vera en la tarjeta:
//   1. Al encender (reset de encendido): todo en reset, LEDs apagados, servos sin pulso.
//   2. Cuando termina el reset de encendido (2,43 ms): LED de listo encendido; servos con pulsos de 1 280 us
//      (punto (0, 0)) cada 20 ms; barrido detenido; sin disparos al sensor.
//   3. El periodo de los servos es de 20 ms.
//   4. Se pulsa S1 (con rebotes): arranca el barrido (LED running).
//   5. El trig dura entre 11 y 12 us; el primer disparo llega despues del GAP.
//   6. Tras 3 disparos se escribe el punto (0, 0) en la memoria con el color
//      del objeto (indice 3) y los LEDs muestran 3.
//   7. El servo de pan pasa a (0, 1): 1 320 us; tilt sigue en 1 280 us.
//   8. Se pulsa S1 otra vez: se detiene y no hay mas disparos.
//   9. Se pulsa S2: reset del sistema; los servos vuelven a (0, 0).
// =============================================================================

`timescale 1ns / 1fs   // precision fina: el periodo de 37,037 ns no se redondea

module tb_lidar_top;

    reg        clk_27 = 1'b0;
    reg        btn_s1 = 1'b1;     // suelto
    reg        btn_s2 = 1'b1;     // suelto
    reg        echo   = 1'b0;
    wire       trig, pwm_pan, pwm_tilt;
    wire [5:0] led;

    lidar_top dut (
        .clk_27(clk_27), .btn_s1(btn_s1), .btn_s2(btn_s2), .echo(echo), .trig(trig),
        .pwm_pan(pwm_pan), .pwm_tilt(pwm_tilt), .led(led)
    );

    always #18.5185 clk_27 = ~clk_27;   // 27 MHz

    // LEDs activos en bajo: los traducimos a "encendido = 1"
    wire       led_running = ~led[0];
    wire       led_listo    = ~led[1];
    wire [3:0] led_idx     = ~led[5:2];

    integer errores = 0;

    task revisar(input cond, input [8*70-1:0] mensaje);
        begin
            if (!cond) begin
                errores = errores + 1;
                $display("  ERROR (t = %0.3f ms): %0s", $realtime / 1e6, mensaje);
            end
        end
    endtask

    // ---------------- modelo del sensor: objeto a 300 mm ---------------------
    integer n_trig = 0;
    realtime trig_sube = 0;
    integer  trig_us = 0;
    always @(posedge trig) begin n_trig = n_trig + 1; trig_sube = $realtime; end
    always @(negedge trig) begin
        trig_us = ($realtime - trig_sube) / 1000.0;
        #2_200_000;                     // 2,2 ms hasta que sube Echo (como el clon del equipo)
        echo = 1'b1;
        #1_749_000;                     // 1 749 us de Echo
        echo = 1'b0;
    end

    // ---------------- medicion de pulsos de los servos ----------------------
    realtime sube_pan = 0, sube_tilt = 0, sube_pan_ant = 0;
    integer  ancho_pan = 0, ancho_tilt = 0, periodo_pan = 0, n_pulsos_pan = 0;

    always @(posedge pwm_pan) begin
        sube_pan_ant = sube_pan;
        sube_pan     = $realtime;
        if (n_pulsos_pan > 0) periodo_pan = ($realtime - sube_pan_ant) / 1000.0;
        n_pulsos_pan = n_pulsos_pan + 1;
    end
    always @(negedge pwm_pan)  ancho_pan  = ($realtime - sube_pan)  / 1000.0;
    always @(posedge pwm_tilt) sube_tilt  = $realtime;
    always @(negedge pwm_tilt) ancho_tilt = ($realtime - sube_tilt) / 1000.0;

    task siguiente_pulso;
        begin
            @(negedge pwm_pan);
            #1000;
        end
    endtask

    // pulsa un boton con rebotes: 5 rebotes cortos, 30 ms firme, suelta
    task pulsar_s1;
        integer r;
        begin
            for (r = 0; r < 5; r = r + 1) begin
                btn_s1 = 1'b0; #300_000; btn_s1 = 1'b1; #200_000;
            end
            btn_s1 = 1'b0; #30_000_000;
            btn_s1 = 1'b1; #25_000_000;
        end
    endtask

    task pulsar_s2;
        begin
            btn_s2 = 1'b0; #30_000_000;
            btn_s2 = 1'b1; #25_000_000;
        end
    endtask

    // ---------------- tiempo limite -----------------------------------------
    initial begin
        #(2_000_000_000);   // 2 s
        $display("PRUEBA FALLIDA: la simulacion no termino a tiempo (algo se trabo)");
        $finish;
    end

    integer n0;

    initial begin
        $dumpfile("sim/tb_lidar_top.vcd");
        $dumpvars(0, btn_s1, btn_s2, echo, trig, pwm_pan, pwm_tilt, led, led_running, led_listo, led_idx);
        $display("=== tb_lidar_top (sensor + servos, velocidad real) ===");

        // ---- Caso 1 ----
        #1000;
        revisar(led_listo == 0 && led_running == 0, "caso 1: LEDs encendidos durante el reset de encendido");
        revisar(pwm_pan == 0 && pwm_tilt == 0 && trig == 0, "caso 1: salidas activas durante el reset de encendido");
        $display("Caso 1 (encendido, durante el reset de encendido) revisado");

        // ---- Casos 2 y 3 ----
        #2_600_000;                      // fin del reset de encendido (2,43 ms)
        revisar(led_listo == 1, "caso 2: LED de listo no encendio");
        siguiente_pulso; siguiente_pulso;
        revisar(ancho_pan == 1280 && ancho_tilt == 1280, "caso 2: los pulsos en (0, 0) no son de 1 280 us");
        revisar(led_running == 0 && n_trig == 0, "caso 2: el barrido arranco solo");
        $display("Caso 2 (listo, servos en (0, 0), sin disparos) revisado: pan %0d us, tilt %0d us", ancho_pan, ancho_tilt);
        revisar(periodo_pan == 20000, "caso 3: el periodo no es de 20 ms");
        $display("Caso 3 (periodo de los servos) revisado: %0d us", periodo_pan);

        // ---- Caso 4 ----
        pulsar_s1;
        revisar(led_running == 1, "caso 4: S1 no arranco el barrido");
        $display("Caso 4 (S1 con rebotes arranca el barrido) revisado");

        // ---- Caso 5 ----
        wait (n_trig >= 1); #20_000;
        revisar(trig_us >= 11 && trig_us <= 12, "caso 5: trig no duro entre 11 y 12 us");
        $display("Caso 5 (disparo al sensor) revisado: trig de %0d us", trig_us);

        // ---- Caso 6: se escribe el punto (0, 0) ----
        wait (dut.we);
        #100;
        revisar(n_trig == 3, "caso 6: el punto no tuvo 3 disparos");
        #1000;
        revisar(dut.u_ram.mem[8'h00] == 4'd3, "caso 6: la memoria no tiene el color 3 en (0, 0)");
        revisar(led_idx == 4'd3, "caso 6: los LEDs no muestran el indice 3");
        $display("Caso 6 (3 disparos, (0, 0) guardado con color %0d, LEDs = %0d) revisado",
                 dut.u_ram.mem[8'h00], led_idx);

        // ---- Caso 7: el pan avanza a (0, 1) ----
        siguiente_pulso; siguiente_pulso;
        revisar(ancho_pan == 1320 && ancho_tilt == 1280, "caso 7: en (0, 1) pan no es 1 320 us");
        $display("Caso 7 (servo en (0, 1)) revisado: pan %0d us, tilt %0d us", ancho_pan, ancho_tilt);

        // ---- Caso 8: S1 detiene ----
        pulsar_s1;
        revisar(led_running == 0, "caso 8: S1 no detuvo el barrido");
        #50_000_000;                    // dejar terminar un disparo en curso
        n0 = n_trig;
        #150_000_000;                   // 150 ms detenido
        revisar(n_trig == n0, "caso 8: hubo disparos estando detenido");
        $display("Caso 8 (S1 detiene: sin disparos) revisado");

        // ---- Caso 9: S2 reset ----
        pulsar_s2;
        revisar(led_running == 0 && led_listo == 1, "caso 9: estado de LEDs tras S2");
        siguiente_pulso; siguiente_pulso;
        revisar(ancho_pan == 1280 && ancho_tilt == 1280, "caso 9: tras S2 los servos no volvieron a (0, 0)");
        $display("Caso 9 (S2 reinicia a (0, 0)) revisado");

        if (errores == 0) $display("PRUEBA EXITOSA: lidar_top paso todos los casos");
        else              $display("PRUEBA FALLIDA: %0d errores", errores);
        $finish;
    end

endmodule
