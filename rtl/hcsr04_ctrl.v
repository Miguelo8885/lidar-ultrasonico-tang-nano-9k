// =============================================================================
// hcsr04_ctrl.v
// Proyecto: escaner LIDAR en Tang Nano 9K (Electronica Digital)
//
// Que hace:
//   Con un pulso "start", genera el disparo (trig) del HC-SR04 y mide cuantos
//   microsegundos dura Echo en alto. Entrega el resultado con "done" cuando el
//   sensor ya termino (Echo de vuelta en bajo).
//
// Estados (3 bits):
//   IDLE      = 000   espera start
//   TRIG      = 001   trig = 1 durante 12 ticks (entre 11 y 12 us)
//   WAIT_RISE = 010   espera a que suba Echo (maximo RISE_MAX us)
//   MEASURE   = 011   cuenta us mientras Echo esta en alto (maximo T_MAX us)
//   WAIT_FALL = 100   espera a que baje Echo (maximo FALL_MAX us)
//   101, 110, 111     no usados -> IDLE
//
// Interfaz:
//   clk    entrada  1 bit    reloj de 27 MHz
//   rst    entrada  1 bit    reset sincrono
//   tick   entrada  1 bit    pulso de 1 us (de tick_gen)
//   start  entrada  1 bit    pulso de un ciclo: medir (de scan_fsm)
//   echo   entrada  1 bit    Echo YA sincronizado por sync_ff
//   trig   salida   1 bit    al pin Trig del sensor (registrado)
//   t_us   salida   13 bits  ancho de Echo en us; T_MAX = sin eco o muy lejos
//   done   salida   1 bit    pulso de un ciclo: medicion lista y Echo en bajo
//
// Correspondencia con el diagrama (docs/hcsr04_ctrl):
//   decodificacion: idle, trg, wrise, meas, wfall
//   cnt     registro de 16 bits, EN = tick, Reset = cnt_rst
//   lim     mux 4:1 con sel = {s1, s0}:
//             00 -> FALL_MAX-1 (WAIT_FALL = 100)   01 -> 11 (TRIG)
//             10 -> RISE_MAX-1 (WAIT_RISE)         11 -> T_MAX-1 (MEASURE)
//   at_lim  = (cnt == lim)          tdone = tick . at_lim
//   n2 = wrise.echo'.tdone + meas.(echo' + tdone) + wfall.echo.tdone'
//   n1 = trg.tdone + wrise.(echo + tdone') + meas.echo.tdone'
//   n0 = idle.start + trg.tdone' + wrise.echo + meas.echo.tdone'
//   cnt_rst = rst + (n != state)    (el contador arranca en 0 en cada estado)
//   load    = wrise.echo'.tdone + meas.(echo' + tdone)
//   sat     = wrise + echo          (mux: 1 -> T_MAX, 0 -> cnt[12:0])
//   done    = wfall.(echo' + tdone)
//   trig    flip-flop con D = trg
//
// Decisiones:
//   - Trig de 12 ticks: la hoja de datos pide >= 10 us; como start llega en
//     cualquier momento entre dos ticks, dura entre 11 y 12 us.
//   - done solo cuando Echo ya bajo: scan_fsm solo cuenta los frames de margen.
//   - Sin eco o mas lejos de T_MAX: t_us = T_MAX (se interpreta como fondo).
//   - Tres limites de tiempo: el sistema nunca se traba aunque el sensor este
//     desconectado (RISE_MAX) o Echo quede pegado en alto (FALL_MAX).
//   - start solo se acepta en IDLE.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module hcsr04_ctrl #(
    parameter [12:0] T_MAX    = 13'd5000,    //  ~857 mm
    parameter [15:0] RISE_MAX = 16'd5000,   // el clon del equipo tarda 2,2 ms en subir Echo
    parameter [15:0] FALL_MAX = 16'd40000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick,
    input  wire        start,
    input  wire        echo,
    output reg         trig,
    output reg  [12:0] t_us,
    output wire        done
);

    localparam [15:0] LIM_TRIG = 16'd11;
    localparam [15:0] LIM_RISE = RISE_MAX - 16'd1;
    localparam [15:0] LIM_MEAS = {3'b000, T_MAX} - 16'd1;
    localparam [15:0] LIM_FALL = FALL_MAX - 16'd1;

    // ======================= registro de estado =============================
    reg  [2:0] state;
    wire [2:0] n;
    wire       s2 = state[2], s1 = state[1], s0 = state[0];

    always @(posedge clk) begin
        if (rst) state <= 3'b000;
        else     state <= n;
    end

    // ======================= decodificacion =================================
    wire idle  = ~s2 & ~s1 & ~s0;
    wire trg   = ~s2 & ~s1 &  s0;
    wire wrise = ~s2 &  s1 & ~s0;
    wire meas  = ~s2 &  s1 &  s0;
    wire wfall =  s2 & ~s1 & ~s0;

    // ======================= contador de us =================================
    reg  [15:0] cnt;
    wire [15:0] cnt_inc = cnt + 16'd1;
    reg  [15:0] lim;
    wire        at_lim, tdone, cnt_rst;

    always @(*) begin                    // mux 4:1, sel = {s1, s0}
        case ({s1, s0})
            2'b00: lim = LIM_FALL;
            2'b01: lim = LIM_TRIG;
            2'b10: lim = LIM_RISE;
            2'b11: lim = LIM_MEAS;
        endcase
    end

    assign at_lim  = (cnt == lim);
    assign tdone   = tick & at_lim;
    assign cnt_rst = rst | (n != state);

    always @(posedge clk) begin
        if (cnt_rst)   cnt <= 16'd0;
        else if (tick) cnt <= cnt_inc;
    end

    // ======================= estado siguiente ===============================
    wire echo_n  = ~echo;
    wire tdone_n = ~tdone;

    assign n[2] = (wrise & echo_n & tdone)
                | (meas  & (echo_n | tdone))
                | (wfall & echo & tdone_n);

    assign n[1] = (trg   & tdone)
                | (wrise & (echo | tdone_n))
                | (meas  & echo & tdone_n);

    assign n[0] = (idle  & start)
                | (trg   & tdone_n)
                | (wrise & echo)
                | (meas  & echo & tdone_n);

    // ======================= resultado ======================================
    wire load = (wrise & echo_n & tdone) | (meas & (echo_n | tdone));
    wire sat  = wrise | echo;

    always @(posedge clk) begin
        if (rst)       t_us <= 13'd0;
        else if (load) t_us <= sat ? T_MAX : cnt[12:0];
    end

    // ======================= salidas ========================================
    assign done = wfall & (echo_n | tdone);

    always @(posedge clk) begin
        if (rst) trig <= 1'b0;
        else     trig <= trg;
    end

endmodule

`default_nettype wire
