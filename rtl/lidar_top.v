// =============================================================================
// lidar_top.v  (sistema sin el monitor USB; el sistema final es
//               monitor/lidar_top_monitor.v)
// Proyecto: escaner LIDAR en Tang Nano 9K (Electronica Digital)
//
// Que hace:
//   Es el modulo superior. No tiene logica propia de barrido: solo crea una
//   copia de cada modulo y une sus cables. Sus puertos son los pines fisicos
//   de la tarjeta (ver constraints/lidar_top.cst).
//
// Puertos (pines de la tarjeta):
//   clk_27    entrada  1 bit   oscilador de 27 MHz de la tarjeta
//   btn_s1    entrada  1 bit   pulsador S1 (activo en bajo): iniciar / detener
//   btn_s2    entrada  1 bit   pulsador S2 (activo en bajo): reset del sistema
//   echo      entrada  1 bit   Echo del HC-SR04 (5 V -> divisor resistivo -> 3,3 V)
//   trig      salida   1 bit   Trig del HC-SR04
//   pwm_pan   salida   1 bit   senal del servo de pan (horizontal)
//   pwm_tilt  salida   1 bit   senal del servo de tilt (vertical)
//   led[5:0]  salida   6 bits  LEDs de la tarjeta (activos en bajo: 0 = encendido)
//
// LEDs (sirven para probar el sensor sin el PC):
//   led[0]    encendido = barrido activo (running)
//   led[1]    encendido = arranque terminado (listo, de por_gen)
//   led[5:2]  indice de color de la ultima mediana (0 cerca ... 14 lejos,
//             15 = fondo): al poner la mano frente al sensor debe cambiar
//
// Red de reset:
//   rst_btn = rst_por              -> tick_gen, sync_ff (S1, S2, echo), debounce
//   rst     = rst_por + pressed_S2 -> grid_walker, servo_pwm, scan_fsm,
//                                     hcsr04_ctrl, median3
//   tick_gen va en rst_btn: si S2 detuviera tick, el debounce de S2 se
//   congelaria con pressed_S2 = 1 y el sistema quedaria en reset para siempre.
//
// por_gen:
//   Reset de encendido: mantiene el sistema en reset los primeros 2,43 ms.
//   Todo el sistema usa un solo reloj, el de 27 MHz de la tarjeta.
//
// depth_ram:
//   El puerto de escritura ya esta conectado al barrido. El puerto de lectura
//   (rclk, raddr, rdata) lo usa mem_monitor en lidar_top_monitor; aqui queda sin
//   conectar (raddr = 0, rclk = clk_27).
//
// Parametros:
//   N, RET               frames de espera (scan_fsm): 4 y 10
//   BASE_PAN, BASE_TILT  ancho en us del indice 0 (se ajustan al calibrar)
//   D_NEAR               distancia del color rojo en mm (depth_quant)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module lidar_top #(
    parameter        N         = 4,
    parameter        RET       = 10,
    parameter [10:0] BASE_PAN  = 11'd1280,
    parameter [10:0] BASE_TILT = 11'd1280,
    parameter [9:0]  D_NEAR    = 10'd200
) (
    input  wire       clk_27,
    input  wire       btn_s1,
    input  wire       btn_s2,
    input  wire       echo,
    output wire       trig,
    output wire       pwm_pan,
    output wire       pwm_tilt,
    output wire [5:0] led
);

    wire clk = clk_27;   // reloj de todo el sistema (27 MHz)

    // ======================= reset de encendido =============================
    wire rst_por, listo;

    por_gen u_por (.clk(clk), .rst_por(rst_por), .listo(listo));

    // ======================= red de reset ===================================
    wire rst_btn;
    wire rst;
    wire pressed_s2;

    assign rst_btn = rst_por;
    assign rst     = rst_por | pressed_s2;

    // ======================= base de tiempo de 1 us =========================
    wire tick;

    tick_gen u_tick (.clk(clk), .rst(rst_btn), .tick(tick));

    // ======================= entradas externas ==============================
    wire s1_sync, s2_sync, echo_sync;
    wire pressed_s1, press_s1, press_s2;

    sync_ff #(.RESET_VAL(1'b1)) u_sync_s1 (.clk(clk), .rst(rst_btn), .d_async(btn_s1), .q_sync(s1_sync));
    sync_ff #(.RESET_VAL(1'b1)) u_sync_s2 (.clk(clk), .rst(rst_btn), .d_async(btn_s2), .q_sync(s2_sync));
    sync_ff #(.RESET_VAL(1'b0)) u_sync_echo (.clk(clk), .rst(rst_btn), .d_async(echo), .q_sync(echo_sync));

    debounce u_deb_s1 (.clk(clk), .rst(rst_btn), .tick(tick), .btn(s1_sync),
                       .pressed(pressed_s1), .press(press_s1));
    debounce u_deb_s2 (.clk(clk), .rst(rst_btn), .tick(tick), .btn(s2_sync),
                       .pressed(pressed_s2), .press(press_s2));

    // ======================= barrido ========================================
    wire       start, we, step, last, running, frame, done;
    wire [3:0] row, col;
    wire [7:0] addr;

    scan_fsm #(.N(N), .RET(RET)) u_fsm (
        .clk(clk), .rst(rst), .frame(frame), .press(press_s1), .done(done), .last(last),
        .start(start), .we(we), .step(step), .running(running)
    );

    grid_walker u_grid (.clk(clk), .rst(rst), .step(step),
                        .row(row), .col(col), .addr(addr), .last(last));

    servo_pwm #(.BASE_PAN(BASE_PAN), .BASE_TILT(BASE_TILT)) u_servo (
        .clk(clk), .rst(rst), .tick(tick), .idx_pan(col), .idx_tilt(row),
        .pwm_pan(pwm_pan), .pwm_tilt(pwm_tilt), .frame(frame)
    );

    // ======================= cadena del sensor ==============================
    wire [12:0] t_us, med;
    wire [9:0]  d_mm;
    wire [3:0]  idx;

    hcsr04_ctrl u_hc (.clk(clk), .rst(rst), .tick(tick), .start(start), .echo(echo_sync),
                      .trig(trig), .t_us(t_us), .done(done));
    median3     u_med (.clk(clk), .rst(rst), .din(t_us), .din_valid(done), .med(med));
    echo_to_mm  u_mm  (.t_us(med), .d_mm(d_mm));
    depth_quant #(.D_NEAR(D_NEAR)) u_q (.d_mm(d_mm), .idx(idx));

    // ======================= memoria de la imagen ===========================
    wire [3:0] rdata;     // sin uso en esta version

    depth_ram u_ram (.wclk(clk), .we(we), .waddr(addr), .wdata(idx),
                     .rclk(clk), .raddr(8'd0), .rdata(rdata));

    // ======================= LEDs (activos en bajo) =========================
    assign led = ~{idx, listo, running};

endmodule

`default_nettype wire
