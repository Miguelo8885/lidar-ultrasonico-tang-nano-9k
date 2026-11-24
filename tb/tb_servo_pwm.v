// =============================================================================
// tb_servo_pwm.v  -  testbench de servo_pwm
//
// Como correrlo (desde la carpeta lidar_scanner):
//   iverilog -o sim/tb_servo_pwm.vvp rtl/servo_pwm.v tb/tb_servo_pwm.v
//   vvp sim/tb_servo_pwm.vvp
//   gtkwave sim/tb_servo_pwm.vcd      (opcional)
//
// Para que sea rapido, tick llega cada 2 ciclos de reloj (en la tarjeta es
// cada 27). Por eso aqui 1 "us" = 2 ciclos, y un pulso de w us debe durar
// exactamente 2*w ciclos. El periodo debe durar 20 000 ticks = 40 000 ciclos.
//
// Un monitor mide, entre cada par de frames seguidos: cuantos ciclos duro el
// periodo y cuantos ciclos estuvo en 1 cada salida.
//
// Tiempo limite: si la simulacion se traba, termina sola con PRUEBA FALLIDA.
//
// Casos que prueba:
//   1. Reset: salidas en 0, sin frame.
//   2. Periodo exacto de 20 000 ticks entre frames (varios periodos) y
//      frame de un solo ciclo.
//   3. El primer periodo despues del reset no tiene pulso.
//   4. Anchos: idx 0 -> 1 280 us, idx 5 -> 1 480, idx 11 -> 1 720.
//   5. Indices invalidos: 12 -> 1 760 us; 15 -> 1 368 us, porque 15 * 40 = 600
//      no cabe en los 9 bits de off y se desborda (600 - 512 = 88). Sigue
//      siendo un ancho seguro para el servo.
//   6. Canales independientes: pan e tilt con indices distintos a la vez.
//   7. Cambio de indice a mitad del pulso: el pulso en curso no cambia; el
//      ancho nuevo aparece en el periodo siguiente.
//   8. Cambio de indice en el mismo ciclo de frame: se toma el valor NUEVO
//      (el registro w lo carga en ese flanco).
//   9. El pulso empieza justo despues de frame (1 ciclo despues del flanco
//      en que per vuelve a 0, por el flip-flop de salida).
//  10. Reset a mitad de un periodo: per vuelve a 0, salidas a 0, y el
//      periodo siguiente no tiene pulso.
// =============================================================================

`timescale 1ns / 1ps

module tb_servo_pwm;

    localparam TDIV = 2;            // ciclos por tick en esta simulacion

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg  [3:0] idx_pan  = 4'd0;
    reg  [3:0] idx_tilt = 4'd0;
    wire       tick, frame, pwm_pan, pwm_tilt;

    // ---------------- generador de tick ------------------------------------
    reg tdiv = 1'b0;
    always @(posedge clk) tdiv <= ~tdiv;
    assign tick = tdiv;

    servo_pwm dut (
        .clk(clk), .rst(rst), .tick(tick),
        .idx_pan(idx_pan), .idx_tilt(idx_tilt),
        .pwm_pan(pwm_pan), .pwm_tilt(pwm_tilt), .frame(frame)
    );

    always #18.5185 clk = ~clk;

    integer errores = 0;

    task revisar(input cond, input [8*70-1:0] mensaje);
        begin
            if (!cond) begin
                errores = errores + 1;
                $display("  ERROR (t = %0t ns): %0s", $time, mensaje);
            end
        end
    endtask

    // ---------------- monitor: mide cada periodo ----------------------------
    integer c_per = 0, c_pan = 0, c_tilt = 0;      // conteos en curso
    integer per_ciclos = 0, alto_pan = 0, alto_tilt = 0;   // del ultimo periodo
    integer n_frames = 0;
    reg     frame_prev = 1'b0;
    reg     pan_prev = 1'b0;
    integer desde_frame = 0;                         // ciclos desde el ultimo frame
    integer subida_pan = -1;                         // ciclos desde frame hasta subir pwm_pan

    always @(negedge clk) begin
        if (rst) begin c_per = 0; c_pan = 0; c_tilt = 0; end   // medir desde el reset
        c_per = c_per + 1;
        desde_frame = desde_frame + 1;
        if (pwm_pan)  c_pan  = c_pan  + 1;
        if (pwm_tilt) c_tilt = c_tilt + 1;
        if (pwm_pan && !pan_prev) subida_pan = desde_frame;
        pan_prev = pwm_pan;
        if (frame && frame_prev) begin
            errores = errores + 1;
            $display("  ERROR (t = %0t ns): frame duro mas de un ciclo", $time);
        end
        frame_prev = frame;
        if (frame) begin
            per_ciclos = c_per;  alto_pan = c_pan;  alto_tilt = c_tilt;
            c_per = 0;  c_pan = 0;  c_tilt = 0;
            desde_frame = 0;
            n_frames = n_frames + 1;
        end
    end

    // Espera n frames (vuelve a mitad del ciclo en que ocurre el ultimo)
    task esperar_frames(input integer n);
        integer objetivo;
        begin
            objetivo = n_frames + n;
            while (n_frames < objetivo) @(negedge clk);
        end
    endtask

    // Mide el ancho que corresponde a los indices actuales:
    // un frame para cargar w, otro para terminar de medir el periodo.
    task medir_y_revisar(input integer us_pan, input integer us_tilt, input [8*40-1:0] caso);
        begin
            esperar_frames(2);
            revisar(alto_pan  == us_pan  * TDIV, caso);
            revisar(alto_tilt == us_tilt * TDIV, caso);
            $display("  idx_pan=%0d -> %0d us | idx_tilt=%0d -> %0d us",
                     idx_pan, alto_pan / TDIV, idx_tilt, alto_tilt / TDIV);
        end
    endtask

    integer i;

    // ---------------- tiempo limite: si algo se traba, la prueba falla -----
    initial begin
        #(200_000_000);
        $display("PRUEBA FALLIDA: la simulacion no termino a tiempo (algo se trabo)");
        $finish;
    end

    initial begin
        $dumpfile("sim/tb_servo_pwm.vcd");
        $dumpvars(1, tb_servo_pwm);
        $display("=== tb_servo_pwm ===");

        // ---- Caso 1 ----
        repeat (10) @(negedge clk);
        revisar(pwm_pan == 0 && pwm_tilt == 0 && frame == 0, "caso 1: salidas no estan en 0 con reset");
        revisar(dut.per == 0, "caso 1: per no esta en 0");
        $display("Caso 1 (reset) revisado");

        // ---- Casos 2 y 3 ----
        rst = 1'b0;
        esperar_frames(1);                 // primer frame tras el reset
        revisar(alto_pan == 0 && alto_tilt == 0, "caso 3: hubo pulso en el primer periodo");
        $display("Caso 3 (primer periodo sin pulso) revisado");
        for (i = 0; i < 3; i = i + 1) begin
            esperar_frames(1);
            revisar(per_ciclos == 20000 * TDIV, "caso 2: el periodo no duro 20 000 ticks");
        end
        $display("Caso 2 (periodo de 20 000 ticks, frame de 1 ciclo) revisado: %0d ticks",
                 per_ciclos / TDIV);

        // ---- Caso 4 ----
        idx_pan = 4'd0;  idx_tilt = 4'd0;   medir_y_revisar(1280, 1280, "caso 4: ancho de idx 0");
        idx_pan = 4'd5;  idx_tilt = 4'd5;   medir_y_revisar(1480, 1480, "caso 4: ancho de idx 5");
        idx_pan = 4'd11; idx_tilt = 4'd11;  medir_y_revisar(1720, 1720, "caso 4: ancho de idx 11");
        $display("Caso 4 (anchos 0, 5 y 11) revisado");

        // ---- Caso 5 ----
        idx_pan = 4'd12; idx_tilt = 4'd12;  medir_y_revisar(1760, 1760, "caso 5: ancho de idx 12");
        idx_pan = 4'd15; idx_tilt = 4'd15;  medir_y_revisar(1368, 1368, "caso 5: ancho de idx 15");
        $display("Caso 5 (indices invalidos 12 y 15, con desborde en 15) revisado");

        // ---- Caso 6 ----
        idx_pan = 4'd0;  idx_tilt = 4'd11;  medir_y_revisar(1280, 1720, "caso 6: canales no independientes");
        idx_pan = 4'd7;  idx_tilt = 4'd2;   medir_y_revisar(1560, 1360, "caso 6: canales no independientes");
        $display("Caso 6 (canales independientes) revisado");

        // ---- Caso 9: el pulso arranca 1 ciclo despues del flanco de frame ----
        esperar_frames(1);
        wait (pwm_pan == 1'b1);
        @(negedge clk);
        revisar(subida_pan == 2, "caso 9: el pulso no arranco justo despues de frame");
        $display("Caso 9 (pulso alineado con frame) revisado: pwm_pan sube %0d ciclos despues del ciclo de frame", subida_pan);

        // ---- Caso 7: cambio a mitad del pulso ----
        // Estamos dentro del pulso de idx 7 (1 560 us). Cambiamos a idx 0.
        repeat (500 * TDIV) @(negedge clk);
        revisar(pwm_pan == 1'b1, "caso 7: no estabamos dentro del pulso");
        idx_pan = 4'd0;
        esperar_frames(1);
        revisar(alto_pan == 1560 * TDIV, "caso 7: el pulso en curso se deformo");
        esperar_frames(1);
        revisar(alto_pan == 1280 * TDIV, "caso 7: el ancho nuevo no aparecio en el periodo siguiente");
        $display("Caso 7 (cambio a mitad del pulso) revisado");

        // ---- Caso 8: cambio en el mismo ciclo de frame ----
        // Esperamos al ciclo previo al frame y cambiamos el indice a mitad del
        // ciclo del frame (antes del flanco que carga w).
        wait (dut.per == 15'd19999);
        while (!frame) @(negedge clk);     // ahora estamos a mitad del ciclo de frame
        idx_pan = 4'd11;
        esperar_frames(1);
        revisar(alto_pan == 1720 * TDIV, "caso 8: no tomo el indice nuevo en el ciclo de frame");
        $display("Caso 8 (cambio en el ciclo de frame: toma el valor nuevo) revisado");

        // ---- Caso 10: reset a mitad de periodo ----
        repeat (5000 * TDIV) @(negedge clk);
        rst = 1'b1;
        @(negedge clk);
        revisar(dut.per == 0, "caso 10: per no volvio a 0");
        @(negedge clk);
        revisar(pwm_pan == 0 && pwm_tilt == 0, "caso 10: las salidas no bajaron con reset");
        rst = 1'b0;
        esperar_frames(1);
        revisar(per_ciclos >= 20000 * TDIV - TDIV && per_ciclos <= 20000 * TDIV + TDIV, "caso 10: el periodo tras el reset no duro 20 000 ticks");
        $display("  periodo tras el reset: %0d ciclos (20 000 ticks = %0d ciclos)", per_ciclos, 20000 * TDIV);
        revisar(alto_pan == 0 && alto_tilt == 0, "caso 10: hubo pulso en el periodo tras el reset");
        $display("Caso 10 (reset a mitad de periodo) revisado");

        if (errores == 0) $display("PRUEBA EXITOSA: servo_pwm paso todos los casos");
        else              $display("PRUEBA FALLIDA: %0d errores", errores);
        $finish;
    end

endmodule
