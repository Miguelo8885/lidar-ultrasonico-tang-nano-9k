// =============================================================================
// tb_debounce.v  -  testbench de debounce
//
// Como correrlo (desde la carpeta lidar_scanner):
//   iverilog -o sim/tb_debounce.vvp rtl/debounce.v tb/tb_debounce.v
//   vvp sim/tb_debounce.vvp
//   gtkwave sim/tb_debounce.vcd       (opcional)
//
// Para que la simulacion sea rapida, el testbench genera "tick" cada 3 ciclos
// de reloj en vez de cada 27. El modulo no cambia: solo cuenta ticks, asi que
// la ventana sigue siendo de 20 000 ticks.
//
// Recordatorio: el boton es activo en bajo. btn = 1 suelto, btn = 0 pulsado.
//
// Tiempo limite: si la simulacion se traba, termina sola con PRUEBA FALLIDA.
//
// Casos que prueba:
//   1. Reset: pressed = 0, press = 0, contador en 0.
//   2. Pulsacion limpia: press sale exactamente en el tick 20 000, dura un
//      ciclo, y pressed pasa a 1.
//   3. Boton sostenido mucho tiempo: no hay mas pulsos press.
//   4. Soltar limpio: pressed vuelve a 0 tras 20 000 ticks y NO sale press.
//   5. Rebotes al pulsar (cambios cada 3 000 ticks): no se acepta nada; luego,
//      con el boton firme, se acepta 20 000 ticks despues del ultimo rebote.
//   6. Pulsacion corta (10 000 ticks): se ignora.
//   7. Limite de la ventana: 19 999 ticks y suelta -> se ignora.
//   8. Reset a mitad de la ventana: el contador vuelve a 0 y hay que esperar
//      la ventana completa otra vez.
//   9. Reset con el boton oficialmente pulsado: pressed vuelve a 0; si el
//      boton sigue pulsado, se acepta de nuevo tras 20 000 ticks.
//  10. (Durante toda la prueba) press nunca dura mas de un ciclo.
// =============================================================================

`timescale 1ns / 1ps

module tb_debounce;

    reg  clk = 1'b0;
    reg  rst = 1'b1;
    reg  btn = 1'b1;            // suelto
    wire tick;
    wire pressed, press;

    // ---------------- generador de tick (cada 3 ciclos) --------------------
    reg [1:0] tdiv = 2'd0;
    always @(posedge clk) tdiv <= (tdiv == 2'd2) ? 2'd0 : tdiv + 2'd1;
    assign tick = (tdiv == 2'd2);

    debounce dut (
        .clk(clk), .rst(rst), .tick(tick), .btn(btn),
        .pressed(pressed), .press(press)
    );

    always #18.5185 clk = ~clk;

    integer errores = 0;
    integer n_press = 0;        // pulsos press vistos en toda la prueba
    integer n;
    integer antes;
    reg     press_prev = 1'b0;

    task revisar(input cond, input [8*70-1:0] mensaje);
        begin
            if (!cond) begin
                errores = errores + 1;
                $display("  ERROR (t = %0t ns): %0s", $time, mensaje);
            end
        end
    endtask

    // ---- Caso 10: monitor permanente (se revisa a mitad de cada ciclo) ----
    always @(negedge clk) begin
        if (press) n_press = n_press + 1;
        if (press && press_prev) begin
            errores = errores + 1;
            $display("  ERROR (t = %0t ns): caso 10: press duro mas de un ciclo", $time);
        end
        press_prev = press;
    end

    // Cambia el boton justo despues de un flanco de subida
    task poner_btn(input v);
        begin
            @(posedge clk); #1 btn = v;
        end
    endtask

    // Cuenta ticks (a mitad de ciclo) hasta ver press o hasta 'max' ticks.
    task contar_hasta_press(input integer max, output integer cuenta);
        begin
            cuenta = 0;
            begin : lazo
                forever begin
                    @(negedge clk);
                    if (tick) cuenta = cuenta + 1;
                    if (press || cuenta >= max) disable lazo;
                end
            end
        end
    endtask

    // Espera n ticks
    task esperar_ticks(input integer m);
        integer k;
        begin
            k = 0;
            while (k < m) begin
                @(negedge clk);
                if (tick) k = k + 1;
            end
        end
    endtask

    integer r;

    // ---------------- tiempo limite: si algo se traba, la prueba falla -----
    initial begin
        #(200_000_000);
        $display("PRUEBA FALLIDA: la simulacion no termino a tiempo (algo se trabo)");
        $finish;
    end

    initial begin
        $dumpfile("sim/tb_debounce.vcd");
        $dumpvars(1, tb_debounce);
        $dumpvars(1, dut);
        $display("=== tb_debounce ===");

        // ---- Caso 1 ----
        repeat (5) @(posedge clk); #1;
        revisar(pressed == 1'b0 && press == 1'b0, "caso 1: salidas no estan en 0 con reset");
        revisar(dut.cnt == 15'd0, "caso 1: contador no esta en 0");
        @(negedge clk) rst = 1'b0;
        esperar_ticks(100);
        revisar(pressed == 1'b0 && n_press == 0, "caso 1: algo cambio con el boton suelto");
        $display("Caso 1 (reset) revisado");

        // ---- Caso 2: pulsacion limpia ----
        poner_btn(1'b0);
        contar_hasta_press(30000, n);
        revisar(press == 1'b1, "caso 2: nunca salio press");
        revisar(n == 20000, "caso 2: press no salio en el tick 20 000");
        @(negedge clk);
        revisar(press == 1'b0, "caso 2: press duro mas de un ciclo");
        revisar(pressed == 1'b1, "caso 2: pressed no paso a 1");
        $display("Caso 2 (pulsacion limpia) revisado: press en el tick %0d", n);

        // ---- Caso 3: sostenido ----
        antes = n_press;
        esperar_ticks(50000);
        revisar(n_press == antes, "caso 3: salieron pulsos extra con el boton sostenido");
        revisar(pressed == 1'b1, "caso 3: pressed se cayo");
        $display("Caso 3 (boton sostenido 50 000 ticks) revisado");

        // ---- Caso 4: soltar limpio ----
        antes = n_press;
        poner_btn(1'b1);
        esperar_ticks(19999);
        revisar(pressed == 1'b1, "caso 4: pressed bajo antes de la ventana");
        esperar_ticks(2);
        revisar(pressed == 1'b0, "caso 4: pressed no volvio a 0");
        revisar(n_press == antes, "caso 4: salio press al soltar");
        $display("Caso 4 (soltar limpio) revisado");

        // ---- Caso 5: rebotes al pulsar ----
        antes = n_press;
        for (r = 0; r < 6; r = r + 1) begin
            poner_btn(1'b0); esperar_ticks(3000);
            poner_btn(1'b1); esperar_ticks(500);
        end
        revisar(pressed == 1'b0 && n_press == antes, "caso 5: se acepto un rebote");
        poner_btn(1'b0);
        contar_hasta_press(30000, n);
        revisar(n == 20000, "caso 5: tras los rebotes no se acepto en el tick 20 000");
        $display("Caso 5 (rebotes) revisado: aceptado %0d ticks despues del ultimo rebote", n);
        poner_btn(1'b1); esperar_ticks(20010);   // volvemos a suelto

        // ---- Caso 6: pulsacion corta ----
        antes = n_press;
        poner_btn(1'b0); esperar_ticks(10000);
        poner_btn(1'b1); esperar_ticks(25000);
        revisar(pressed == 1'b0 && n_press == antes, "caso 6: se acepto una pulsacion corta");
        $display("Caso 6 (pulsacion de 10 000 ticks ignorada) revisado");

        // ---- Caso 7: limite de la ventana ----
        // Se suelta justo despues de que el modulo consume el tick 19 999:
        // el contador queda en 19 999 (full = 1), pero el tick 20 000 ya
        // llega con el boton suelto.
        antes = n_press;
        poner_btn(1'b0);
        esperar_ticks(19999);
        @(posedge clk); #1;
        revisar(dut.cnt == 15'd19999, "caso 7: el contador no llego a 19 999");
        btn = 1'b1;
        esperar_ticks(25000);
        revisar(pressed == 1'b0 && n_press == antes, "caso 7: se acepto con 19 999 ticks");
        $display("Caso 7 (19 999 ticks ignorados) revisado");

        // ---- Caso 8: reset a mitad de la ventana ----
        poner_btn(1'b0);
        esperar_ticks(10000);
        @(negedge clk) rst = 1'b1;
        @(negedge clk);
        revisar(dut.cnt == 15'd0, "caso 8: el contador no volvio a 0 con reset");
        rst = 1'b0;
        contar_hasta_press(30000, n);
        revisar(n == 20000, "caso 8: tras el reset no se espero la ventana completa");
        $display("Caso 8 (reset a mitad de ventana) revisado: %0d ticks", n);

        // ---- Caso 9: reset con el boton oficialmente pulsado ----
        esperar_ticks(10);
        revisar(pressed == 1'b1, "caso 9: el boton no estaba oficialmente pulsado");
        @(negedge clk) rst = 1'b1;
        @(negedge clk);
        revisar(pressed == 1'b0, "caso 9: pressed no volvio a 0 con reset");
        rst = 1'b0;
        contar_hasta_press(30000, n);
        revisar(n == 20000 && press == 1'b1, "caso 9: no se volvio a aceptar el boton pulsado");
        $display("Caso 9 (reset con boton pulsado) revisado");

        $display("Caso 10 (press de un solo ciclo) revisado durante toda la prueba");
        if (errores == 0) $display("PRUEBA EXITOSA: debounce paso todos los casos");
        else              $display("PRUEBA FALLIDA: %0d errores", errores);
        $finish;
    end

endmodule
