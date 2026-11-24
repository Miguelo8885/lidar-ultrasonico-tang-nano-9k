// =============================================================================
// scan_fsm.v  (version final)
// Proyecto: escaner LIDAR en Tang Nano 9K (Electronica Digital)
//
// Que hace:
//   Coordina el escaneo. En cada punto dispara el sensor 3 veces, con una
//   espera de N frames entre disparos (GAP). Despues del tercer done pasa por
//   WRITE (un ciclo): escribe el color del punto en depth_ram y da step. El
//   GAP siguiente sirve tambien para que el servo llegue al punto nuevo. En
//   el ultimo punto, en vez de GAP espera RET frames (RETURN) mientras los
//   servos regresan a (0, 0). S1 (press) inicia y detiene el barrido.
//
// Estados (3 bits, binario):
//   IDLE      = 000   detenido                       running = 0
//   FIRE      = 001   start = 1 (un ciclo)
//   WAIT_ECHO = 010   espera done de hcsr04_ctrl
//   GAP       = 011   espera N frames
//   RETURN    = 100   espera RET frames (regreso a (0, 0))
//   WRITE     = 101   we = 1 y step = 1 (un ciclo)
//   110, 111          no usados -> IDLE
//
// Interfaz:
//   clk, rst  entradas  1 bit  reloj de 27 MHz y reset sincrono
//   frame     entrada   1 bit  pulso cada 20 ms (de servo_pwm)
//   press     entrada   1 bit  pulso por pulsacion de S1 (de debounce)
//   done      entrada   1 bit  medicion lista y Echo en bajo (de hcsr04_ctrl)
//   last      entrada   1 bit  ultimo punto de la rejilla (de grid_walker)
//   start     salida    1 bit  disparar (a hcsr04_ctrl)
//   we        salida    1 bit  escribir el punto actual (a depth_ram)
//   step      salida    1 bit  avanzar al siguiente punto (a grid_walker)
//   running   salida    1 bit  barrido activo (LED)
//
// Parametros:
//   N    frames de espera entre disparos (4: al menos 60 ms)
//   RET  frames de espera para el regreso a (0, 0) (10: al menos 180 ms)
//
// Correspondencia con el diagrama (docs/scan_fsm):
//   decodificacion: idle, fire, wecho, gap, ret, write
//   shot   contador de 2 bits, EN = wecho.done, Reset = rst + idle + write
//   third  = shot[1] . shot[0]'          (el done que llega es el tercero)
//   cnt    contador de 4 bits, EN = frame, Reset = rst + (gap + ret)' + fdone
//   lim    = s2 ? RET-1 : N-1            (mux 2:1; GAP = 011, RETURN = 100)
//   fdone  = frame . (cnt == lim)
//   pn     = press'
//   n2 = wecho.pn.done.third + write.pn.last + ret.pn.fdone'
//   n1 = idle.press + fire.pn + wecho.pn.(third' + done') + write.pn.last'
//        + gap.pn.fdone'
//   n0 = idle.press + wecho.pn.done + write.pn.last' + gap.pn + ret.pn.fdone
//   start = fire   we = write   step = write   running = idle'   (Moore)
//
// Decisiones:
//   - WRITE es un estado aparte: median3 carga la tercera medicion en el
//     flanco de done, asi que la mediana correcta esta un ciclo despues; en
//     ese ciclo el grid_walker todavia apunta al punto actual.
//   - Reanudar pasa por GAP: se respeta el margen del sensor aunque se haya
//     pausado a mitad de una medicion.
//   - Al pausar, shot vuelve a 0: al reanudar se hacen tres disparos nuevos.
//   - press tiene prioridad en todos los estados (WRITE igual completa el
//     punto porque sus salidas son Moore).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module scan_fsm #(
    parameter N   = 4,
    parameter RET = 10
) (
    input  wire clk,
    input  wire rst,
    input  wire frame,
    input  wire press,
    input  wire done,
    input  wire last,
    output wire start,
    output wire we,
    output wire step,
    output wire running
);

    localparam [3:0] LIM_GAP = N - 1;
    localparam [3:0] LIM_RET = RET - 1;

    // ======================= registro de estado =============================
    reg  [2:0] state;
    wire [2:0] n;
    wire s2 = state[2], s1 = state[1], s0 = state[0];

    always @(posedge clk) begin
        if (rst) state <= 3'b000;
        else     state <= n;
    end

    // ======================= decodificacion =================================
    wire idle  = ~s2 & ~s1 & ~s0;
    wire fire  = ~s2 & ~s1 &  s0;
    wire wecho = ~s2 &  s1 & ~s0;
    wire gap   = ~s2 &  s1 &  s0;
    wire ret   =  s2 & ~s1 & ~s0;
    wire write =  s2 & ~s1 &  s0;

    // ======================= contador de disparos ===========================
    reg  [1:0] shot;
    wire       third = shot[1] & ~shot[0];

    always @(posedge clk) begin
        if (rst | idle | write)  shot <= 2'b00;
        else if (wecho & done)   shot <= shot + 2'b01;
    end

    // ======================= contador de frames =============================
    reg  [3:0] cnt;
    wire [3:0] lim   = s2 ? LIM_RET : LIM_GAP;
    wire       fdone = frame & (cnt == lim);
    wire       cnt_rst = rst | ~(gap | ret) | fdone;

    always @(posedge clk) begin
        if (cnt_rst)    cnt <= 4'd0;
        else if (frame) cnt <= cnt + 4'd1;
    end

    // ======================= estado siguiente ===============================
    wire pn = ~press;

    assign n[2] = (wecho & pn & done & third)
                | (write & pn & last)
                | (ret   & pn & ~fdone);

    assign n[1] = (idle  & press)
                | (fire  & pn)
                | (wecho & pn & (~third | ~done))
                | (write & pn & ~last)
                | (gap   & pn & ~fdone);

    assign n[0] = (idle  & press)
                | (wecho & pn & done)
                | (write & pn & ~last)
                | (gap   & pn)
                | (ret   & pn & fdone);

    // ======================= salidas (Moore) ================================
    assign start   = fire;
    assign we      = write;
    assign step    = write;
    assign running = ~idle;

endmodule

`default_nettype wire
