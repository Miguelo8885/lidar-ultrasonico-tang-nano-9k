// =============================================================================
// servo_pwm.v
// Proyecto: escaner LIDAR en Tang Nano 9K (Electronica Digital)
//
// Que hace:
//   Genera las senales PWM de los dos servos SG90 (pan y tilt).
//   - Un contador de periodo COMPARTIDO cuenta microsegundos de 0 a 19 999
//     (20 ms). Cada vez que vuelve a 0 da "frame", un pulso de un ciclo.
//   - Cada canal pone su salida en 1 durante "w" microsegundos al inicio de
//     cada periodo, con w = BASE + 40 * idx.
//   - El ancho nuevo solo se carga con frame, asi un pulso en curso nunca se
//     deforma.
//
// Interfaz:
//   clk       entrada  1 bit   reloj de 27 MHz
//   rst       entrada  1 bit   reset sincrono (activo en 1)
//   tick      entrada  1 bit   pulso de 1 us (de tick_gen)
//   idx_pan   entrada  4 bits  indice de columna (col del grid_walker), 0 a 11
//   idx_tilt  entrada  4 bits  indice de fila (row del grid_walker), 0 a 11
//   pwm_pan   salida   1 bit   senal al servo de pan
//   pwm_tilt  salida   1 bit   senal al servo de tilt
//   frame     salida   1 bit   pulso de un ciclo cada 20 ms (base de tiempo de scan_fsm)
//
// Parametros:
//   BASE_PAN, BASE_TILT  ancho en us para el indice 0 (11 bits). Por defecto
//                        1 280 = 101 0000 0000, para que la ventana de
//                        1 280 a 1 720 us quede centrada en 1 500 us.
//
// Correspondencia con el diagrama (docs/servo_pwm):
//   per       registro de 15 bits, EN = tick, Reset = per_rst
//   per_inc   = per + 1
//   per_end   = (per == 100 1110 0001 1111) = 19 999
//   frame     = tick . per_end
//   per_rst   = rst + frame
//   Por canal:
//     ext     = {00000, idx}               (extension con ceros a 9 bits)
//     sh5     = ext << 5   (x32)           desplazador, shamt = 0101
//     sh3     = ext << 3   (x8)            desplazador, shamt = 0011
//     off     = sh5 + sh3  (= 40 * idx)    sumador de 9 bits
//     width   = BASE + {00, off}           sumador de 11 bits
//     w       registro de 11 bits, EN = frame, Reset = rst
//     resta   = per + ~{0000, w} + 1       restador de 15 bits (B invertido, Cin = 1)
//     lt      = Cout'                      (Cout = 0 <=> per < w)
//     pwm     flip-flop de salida, D = lt
//
// Decisiones:
//   - El primer periodo despues del reset no tiene pulso (w = 0 hasta el
//     primer frame).
//   - La salida pasa por un flip-flop para que no salgan glitches al pin.
//   - Indices 12 a 15 nunca llegan (el grid_walker solo da 0 a 11). Si
//     llegaran: 12 * 40 = 480 cabe en los 9 bits de off (1 760 us), pero
//     13, 14 y 15 dan 520, 560 y 600, que NO caben en 9 bits (maximo 511) y
//     se desbordan: quedan 8, 48 y 88 -> 1 288, 1 328 y 1 368 us. Todos
//     siguen entre 1 280 y 1 760 us, asi que el servo nunca recibe un
//     ancho peligroso. (Lo encontro el testbench, caso 5.)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module servo_pwm #(
    parameter [10:0] BASE_PAN  = 11'd1280,
    parameter [10:0] BASE_TILT = 11'd1280
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       tick,
    input  wire [3:0] idx_pan,
    input  wire [3:0] idx_tilt,
    output reg        pwm_pan,
    output reg        pwm_tilt,
    output wire       frame
);

    localparam [14:0] PER_LAST = 15'b100_1110_0001_1111;   // 19 999

    // =================== contador de periodo (compartido) ===================
    reg  [14:0] per;
    wire [14:0] per_inc;
    wire        per_end;
    wire        per_rst;

    assign per_inc = per + 15'd1;
    assign per_end = (per == PER_LAST);
    assign frame   = tick & per_end;
    assign per_rst = rst | frame;

    always @(posedge clk) begin
        if (per_rst)
            per <= 15'd0;
        else if (tick)
            per <= per_inc;
    end

    // =========================== canal PAN ==================================
    wire [8:0]  ext_pan, sh5_pan, sh3_pan, off_pan;
    wire [10:0] width_pan;
    reg  [10:0] w_pan;
    wire [15:0] resta_pan;     // bit 15 = Cout, bits 14:0 = resultado (sin conectar)
    wire        lt_pan;

    assign ext_pan   = {5'b00000, idx_pan};
    assign sh5_pan   = ext_pan << 4'b0101;
    assign sh3_pan   = ext_pan << 4'b0011;
    assign off_pan   = sh5_pan + sh3_pan;
    assign width_pan = BASE_PAN + {2'b00, off_pan};

    always @(posedge clk) begin
        if (rst)
            w_pan <= 11'd0;
        else if (frame)
            w_pan <= width_pan;
    end

    assign resta_pan = {1'b0, per} + {1'b0, ~{4'b0000, w_pan}} + 16'd1;
    assign lt_pan    = ~resta_pan[15];

    always @(posedge clk) begin
        if (rst)
            pwm_pan <= 1'b0;
        else
            pwm_pan <= lt_pan;
    end

    // =========================== canal TILT =================================
    wire [8:0]  ext_tilt, sh5_tilt, sh3_tilt, off_tilt;
    wire [10:0] width_tilt;
    reg  [10:0] w_tilt;
    wire [15:0] resta_tilt;
    wire        lt_tilt;

    assign ext_tilt   = {5'b00000, idx_tilt};
    assign sh5_tilt   = ext_tilt << 4'b0101;
    assign sh3_tilt   = ext_tilt << 4'b0011;
    assign off_tilt   = sh5_tilt + sh3_tilt;
    assign width_tilt = BASE_TILT + {2'b00, off_tilt};

    always @(posedge clk) begin
        if (rst)
            w_tilt <= 11'd0;
        else if (frame)
            w_tilt <= width_tilt;
    end

    assign resta_tilt = {1'b0, per} + {1'b0, ~{4'b0000, w_tilt}} + 16'd1;
    assign lt_tilt    = ~resta_tilt[15];

    always @(posedge clk) begin
        if (rst)
            pwm_tilt <= 1'b0;
        else
            pwm_tilt <= lt_tilt;
    end

endmodule

`default_nettype wire
