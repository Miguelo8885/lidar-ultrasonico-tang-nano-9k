// =============================================================================
// tb_scan_fsm.v  -  testbench de scan_fsm (version final) con la cadena real
//
// Como correrlo: ./simular.sh scan_fsm      (tarda alrededor de un minuto)
//
// Se conectan los modulos reales: scan_fsm, hcsr04_ctrl, median3, echo_to_mm,
// depth_quant, grid_walker y depth_ram. Un MODELO del sensor responde a cada
// trig segun una ESCENA:
//   - pared a 700 mm en todo el fondo                   -> indice 15 (negro)
//   - "botella" cercana: filas 2-5, columnas 2-4, 300 mm -> indice 3
//   - "botella" lejana:  filas 6-9, columnas 7-9, 600 mm -> indice 12
//   - errores a proposito: en los puntos k con k % 7 == 0 el PRIMER disparo
//     no tiene eco; en los k % 11 == 0 el TERCERO da un eco falso de 900 us.
//     median3 debe descartarlos.
// Para que sea rapido: tick cada 2 ciclos y frame cada 500 ticks (en la
// tarjeta, 1 us y 20 ms). La logica es la misma.
//
// Casos que prueba:
//   1. Reset: IDLE, sin start, running = 0.
//   2. press: el primer disparo llega despues de al menos N-1 frames (GAP).
//   3. Cada punto: exactamente 3 start, y entre cada done y el siguiente
//      start pasan al menos N-1 frames.
//   4. Cada escritura: direccion del punto actual (orden de la serpentina),
//      dato = depth_quant(echo_to_mm(mediana de las 3 mediciones del punto))
//      y coincide con la escena (los errores a proposito se descartan).
//   5. step = we, siempre.
//   6. Imagen completa: 144 escrituras; despues del ultimo punto, RETURN y al
//      menos RET-1 frames antes del primer disparo de la imagen siguiente,
//      con el grid en (0, 0).
//   7. La memoria, leida desde el reloj de video (25,2 MHz), contiene la
//      imagen esperada en los 144 puntos.
//   8. Pausa en WAIT_ECHO: va a IDLE, no escribe ni avanza, el done que
//      llega despues se ignora; al reanudar, GAP y tres disparos nuevos del
//      MISMO punto, escrito con el valor correcto.
//   9. press en GAP: va a IDLE sin escribir.
//  10. press en el ciclo de WRITE: el punto se completa (we y step) y luego IDLE.
//  11. Estados 110 y 111 forzados: van a IDLE.
// =============================================================================

`timescale 1ns / 1ps

module tb_scan_fsm;

    localparam TDIV = 2;
    localparam FR   = 500;      // ticks entre frames en esta simulacion
    localparam N    = 4;
    localparam RET  = 10;

    reg        clk = 1'b0, rclk = 1'b0;
    reg        rst = 1'b1;
    reg        press = 1'b0;
    reg        echo = 1'b0;
    reg  [7:0] raddr = 8'd0;

    // ---------------- tick y frame ------------------------------------------
    reg        tdiv = 1'b0;
    reg [9:0]  fcnt = 10'd0;
    wire       tick  = tdiv;
    wire       frame = tick & (fcnt == FR - 1);
    always @(posedge clk) begin
        tdiv <= ~tdiv;
        if (tick) fcnt <= (fcnt == FR - 1) ? 10'd0 : fcnt + 10'd1;
    end

    // ---------------- cadena real -------------------------------------------
    wire        start, we, step, running, done, last, trig;
    wire [12:0] t_us, med;
    wire [9:0]  d_mm;
    wire [3:0]  idx, rdata, row, col;
    wire [7:0]  addr;

    scan_fsm #(.N(N), .RET(RET)) dut (
        .clk(clk), .rst(rst), .frame(frame), .press(press), .done(done), .last(last),
        .start(start), .we(we), .step(step), .running(running));
    hcsr04_ctrl hc (.clk(clk), .rst(rst), .tick(tick), .start(start), .echo(echo),
                    .trig(trig), .t_us(t_us), .done(done));
    median3     md (.clk(clk), .rst(rst), .din(t_us), .din_valid(done), .med(med));
    echo_to_mm  em (.t_us(med), .d_mm(d_mm));
    depth_quant dq (.d_mm(d_mm), .idx(idx));
    grid_walker gw (.clk(clk), .rst(rst), .step(step), .row(row), .col(col), .addr(addr), .last(last));
    depth_ram   rm (.wclk(clk), .we(we), .waddr(addr), .wdata(idx),
                    .rclk(rclk), .raddr(raddr), .rdata(rdata));

    always #18.5185 clk  = ~clk;    // 27 MHz
    always #19.8413 rclk = ~rclk;   // 25,2 MHz

    integer errores = 0;
    task revisar(input cond, input [8*70-1:0] mensaje);
        begin
            if (!cond) begin
                errores = errores + 1;
                if (errores <= 15)
                    $display("  ERROR (t = %0t): %0s [estado=%b row=%0d col=%0d]",
                             $time, mensaje, dut.state, row, col);
            end
        end
    endtask

    // ---------------- escena ------------------------------------------------
    function integer distancia(input integer r, input integer c);
        begin
            distancia = 700;
            if (r >= 2 && r <= 5 && c >= 2 && c <= 4) distancia = 300;
            if (r >= 6 && r <= 9 && c >= 7 && c <= 9) distancia = 600;
        end
    endfunction

    function integer color_escena(input integer r, input integer c);
        integer d;
        begin
            d = distancia(r, c);
            color_escena = (d == 300) ? 3 : (d == 600) ? 12 : 15;
        end
    endfunction

    // ancho de Echo en us para el disparo s (0, 1, 2) del punto (r, c); 0 = sin eco
    function integer ancho_echo(input integer r, input integer c, input integer s);
        integer d, k, t;
        begin
            d = distancia(r, c);
            k = r * 12 + c;
            t = (d == 300) ? 1749 : (d == 600) ? 3499 : 4082;
            t = t + 2 * (s - 1);                                   // pequena variacion
            if (k % 7 == 0 && s == 0)                    ancho_echo = 0;      // sin eco
            else if (k % 11 == 0 && k % 7 != 0 && s == 2) ancho_echo = 900;   // eco falso
            else                                          ancho_echo = t;
        end
    endfunction

    // ---------------- modelo del sensor -------------------------------------
    task automatic esperar_ticks(input integer m);
        integer q;
        begin
            q = 0;
            while (q < m) begin @(negedge clk); if (tick) q = q + 1; end
        end
    endtask

    integer sr, sc, ss, sa;
    always begin
        @(negedge trig);
        sr = row; sc = col; ss = dut.shot;
        sa = ancho_echo(sr, sc, ss);
        esperar_ticks(450);
        if (sa > 0) begin
            @(posedge clk) #1 echo = 1'b1;
            esperar_ticks(sa);
            @(posedge clk) #1 echo = 1'b0;
        end
    end

    // ---------------- modelo del recorrido y del dato esperado --------------
    integer er = 0, ec = 0;                 // punto esperado
    task modelo_siguiente;
        begin
            if (er == 11 && ec == 0) begin er = 0; ec = 0; end
            else if (er % 2 == 0) begin if (ec == 11) er = er + 1; else ec = ec + 1; end
            else begin if (ec == 0) er = er + 1; else ec = ec - 1; end
        end
    endtask

    function integer med3(input integer a, input integer b, input integer c);
        begin
            if ((a >= b && a <= c) || (a <= b && a >= c))      med3 = a;
            else if ((b >= a && b <= c) || (b <= a && b >= c)) med3 = b;
            else                                                med3 = c;
        end
    endfunction

    function integer cuantizar(input integer t);
        integer mm, q;
        begin
            mm = (11 * t) / 64;
            if (mm < 200) cuantizar = 0;
            else begin q = (mm - 200) / 32; cuantizar = (q >= 15) ? 15 : q; end
        end
    endfunction

    // ---------------- monitor permanente ------------------------------------
    integer n_frames = 0, frames_desde_done = 100, n_start = 0, n_writes = 0, n_done_ign = 0;
    integer min_gap = 1000, gap_tras_return = -1;
    integer m0, m1, m2, nmed = 0;           // mediciones del punto actual
    reg     monitor_on = 1'b1;
    reg     esperar_return = 1'b0;
    integer esperado;

    always @(negedge clk) begin
        if (frame) begin n_frames = n_frames + 1; frames_desde_done = frames_desde_done + 1; end
        if (step != we) begin errores = errores + 1; $display("  ERROR: caso 5: step distinto de we"); end
        if (done) begin
            if (dut.wecho) begin
                if (nmed == 0) m0 = t_us; else if (nmed == 1) m1 = t_us; else m2 = t_us;
                nmed = nmed + 1;
            end else n_done_ign = n_done_ign + 1;
            frames_desde_done = 0;
        end
        if (start) begin
            n_start = n_start + 1;
            if (frames_desde_done < min_gap) min_gap = frames_desde_done;
            if (esperar_return) begin gap_tras_return = frames_desde_done; esperar_return = 1'b0; end
        end
        if (dut.idle) nmed = 0;
        if (we && monitor_on) begin
            revisar(n_start == 3 && nmed == 3, "caso 3: el punto no tuvo exactamente 3 disparos");
            revisar(row == er && col == ec, "caso 4: escritura en una direccion distinta del punto actual");
            esperado = cuantizar(med3(m0, m1, m2));
            revisar(idx == esperado, "caso 4: el dato no es la mediana cuantizada de las 3 mediciones");
            revisar(idx == color_escena(er, ec), "caso 4: el dato no coincide con la escena");
            n_writes = n_writes + 1;
            if (er == 11 && ec == 0) esperar_return = 1'b1;
            modelo_siguiente;
            n_start = 0; nmed = 0;
        end
    end

    // ---------------- utilidades --------------------------------------------
    task pulsar;
        begin
            @(negedge clk) press = 1'b1;
            @(negedge clk) press = 1'b0;
        end
    endtask

    task esperar_frames(input integer m);
        integer obj;
        begin
            obj = n_frames + m;
            while (n_frames < obj) @(negedge clk);
        end
    endtask

    task automatic leer_ram(input [7:0] a, output [3:0] d);
        begin
            @(negedge rclk) raddr = a;
            @(posedge rclk) #1 d = rdata;
        end
    endtask

    // ---------------- tiempo limite -----------------------------------------
    initial begin
        #(2_000_000_000);
        $display("PRUEBA FALLIDA: la simulacion no termino a tiempo (algo se trabo)");
        $finish;
    end

    integer r, c, k, malos, w0, f0;
    reg [3:0] v;
    reg [7:0] punto_pausa;

    initial begin
        $dumpfile("sim/tb_scan_fsm.vcd");
        $dumpvars(1, tb_scan_fsm);
        $dumpvars(1, dut);
        $display("=== tb_scan_fsm (version final, con la cadena real) ===  N = %0d, RET = %0d", N, RET);

        // ---- Caso 1 ----
        repeat (5) @(negedge clk);
        rst = 1'b0;
        esperar_frames(5);
        revisar(dut.idle && n_start == 0 && running == 0, "caso 1: no esta en IDLE tras el reset");
        $display("Caso 1 (reset: IDLE, sin disparos) revisado");

        // ---- Caso 2 ----
        f0 = n_frames;
        frames_desde_done = 0;                       // medimos el GAP desde el press
        pulsar;
        wait (start);
        @(negedge clk);
        revisar(n_frames - f0 >= N - 1, "caso 2: disparo antes de N-1 frames tras press");
        $display("Caso 2 (press -> GAP -> primer disparo tras %0d frames) revisado", n_frames - f0);

        // ---- Casos 3 a 6: una imagen completa ----
        wait (n_writes == 144);
        @(negedge clk);
        revisar(dut.ret, "caso 6: tras el ultimo punto no esta en RETURN");
        revisar(row == 0 && col == 0, "caso 6: el grid no volvio a (0, 0)");
        wait (gap_tras_return >= 0);
        revisar(gap_tras_return >= RET - 1, "caso 6: RETURN espero menos de RET-1 frames");
        $display("Casos 3 a 6 (imagen completa: 144 puntos, 3 disparos c/u, datos y direcciones) revisados");
        $display("  GAP minimo entre done y start: %0d frames (debe ser >= %0d)", min_gap, N - 1);
        $display("  espera tras el ultimo punto (RETURN): %0d frames (debe ser >= %0d)", gap_tras_return, RET - 1);
        revisar(min_gap >= N - 1, "caso 3: GAP menor que N-1 frames");

        // ---- Caso 7: leer la memoria desde el reloj de video ----
        malos = 0;
        for (r = 0; r < 12; r = r + 1)
            for (c = 0; c < 12; c = c + 1) begin
                leer_ram({r[3:0], c[3:0]}, v);
                if (v != color_escena(r, c)) malos = malos + 1;
            end
        revisar(malos == 0, "caso 7: la memoria no contiene la imagen esperada");
        $display("Caso 7 (imagen en memoria leida a 25,2 MHz) revisada: %0d diferencias", malos);
        $display("  imagen (indice de color por punto):");
        for (r = 0; r < 12; r = r + 1) begin
            $write("   ");
            for (c = 0; c < 12; c = c + 1) begin
                leer_ram({r[3:0], c[3:0]}, v);
                $write(" %2d", v);
            end
            $write("\n");
        end

        // ---- Caso 8: pausa en WAIT_ECHO y reanudar ----
        wait (n_writes == 146);                     // segunda imagen, punto (0, 2)
        // a mitad de ciclo, en WAIT_ECHO con el segundo disparo midiendo
        @(negedge clk);
        while (!(dut.wecho && dut.shot == 1 && hc.state == 3'b011)) @(negedge clk);
        punto_pausa = addr; w0 = n_writes;
        pulsar;
        revisar(dut.idle, "caso 8: press en WAIT_ECHO no llevo a IDLE");
        k = n_done_ign;
        esperar_frames(12);                         // la medicion en curso dura hasta ~4 600 us
        revisar(n_writes == w0 && addr == punto_pausa, "caso 8: en pausa escribio o avanzo");
        revisar(n_done_ign > k, "caso 8: no llego el done de la medicion interrumpida");
        revisar(dut.idle && dut.shot == 0, "caso 8: el done en pausa cambio el estado");
        n_start = 0; nmed = 0;
        frames_desde_done = 0; f0 = n_frames;
        pulsar;
        wait (start); @(negedge clk);
        revisar(n_frames - f0 >= N - 1, "caso 8: al reanudar no respeto el GAP");
        wait (n_writes == w0 + 1);
        $display("Caso 8 (pausa en WAIT_ECHO, done ignorado, reanuda el mismo punto) revisado");

        // ---- Caso 9: press en GAP ----
        wait (dut.gap); @(negedge clk);
        w0 = n_writes;
        pulsar;
        revisar(dut.idle, "caso 9: press en GAP no llevo a IDLE");
        esperar_frames(10);
        revisar(n_writes == w0, "caso 9: escribio estando en pausa");
        $display("Caso 9 (press en GAP) revisado");

        // ---- Caso 10: press en el ciclo de WRITE ----
        n_start = 0; nmed = 0;
        pulsar;                                      // reanudar
        wait (dut.write);                            // a mitad del ciclo de WRITE
        #1 press = 1'b1;
        revisar(we && step, "caso 10: WRITE no dio we y step con press");
        @(negedge clk) press = 1'b0;
        revisar(dut.idle, "caso 10: tras WRITE con press no fue a IDLE");
        $display("Caso 10 (press en WRITE: completa el punto y se detiene) revisado");

        // ---- Caso 11: estados no usados ----
        monitor_on = 1'b0;
        @(negedge clk) force dut.state = 3'b110;
        #1 release dut.state;
        @(posedge clk) #1 revisar(dut.idle, "caso 11: 110 no fue a IDLE");
        @(negedge clk) force dut.state = 3'b111;
        #1 release dut.state;
        @(posedge clk) #1 revisar(dut.idle, "caso 11: 111 no fue a IDLE");
        $display("Caso 11 (estados 110 y 111 van a IDLE) revisado");

        $display("Casos 4 y 5 (datos de cada escritura; step = we) revisados durante toda la prueba");
        if (errores == 0) $display("PRUEBA EXITOSA: scan_fsm paso todos los casos");
        else              $display("PRUEBA FALLIDA: %0d errores", errores);
        $finish;
    end

endmodule
