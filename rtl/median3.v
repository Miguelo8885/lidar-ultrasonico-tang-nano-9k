// =============================================================================
// median3.v
// Proyecto: escaner LIDAR en Tang Nano 9K (Electronica Digital)
//
// Que hace:
//   Guarda las tres ultimas mediciones en un registro de desplazamiento y
//   entrega la del medio (la mediana). Si una de las tres es un error
//   (eco rebotado, un "sin eco" momentaneo), queda descartada.
//
// Interfaz:
//   clk        entrada  1 bit    reloj de 27 MHz
//   rst        entrada  1 bit    reset sincrono
//   din        entrada  13 bits  medicion nueva (t_us de hcsr04_ctrl)
//   din_valid  entrada  1 bit    pulso de un ciclo: hay medicion nueva (done)
//   med        salida   13 bits  mediana de las tres ultimas mediciones
//
// Correspondencia con el diagrama (docs/median3):
//   r0, r1, r2   registros de 13 bits en cadena, EN = din_valid, Reset = rst
//                r0 <- din, r1 <- r0, r2 <- r1
//   ab = (r0 < r1)   ac = (r0 < r2)   bc = (r1 < r2)
//                Cada "<" es un restador de 13 bits (B invertido, Cin = 1):
//                x < y  <=>  Cout = 0  ->  lt = Cout'
//   sel_a = ab XOR ac       (r0 es mayor que exactamente uno de los otros)
//   sel_b = ab XOR bc'      (r1 es mayor que exactamente uno de los otros)
//   med   = sel_a ? r0 : (sel_b ? r1 : r2)     (dos muxes 2:1 en cascada)
//
// Decisiones:
//   - Mediana y no promedio: no la arrastra un valor erroneo y no necesita
//     dividir entre 3.
//   - Registro de desplazamiento: tras tres din_valid, los tres registros
//     son del punto actual; no hace falta contar ni borrar entre puntos.
//   - med es combinacional: no va a un pin, y scan_fsm la usa un ciclo
//     despues del tercer done.
//   - Con valores repetidos cualquier eleccion entre ellos es correcta.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module median3 (
    input  wire        clk,
    input  wire        rst,
    input  wire [12:0] din,
    input  wire        din_valid,
    output wire [12:0] med
);

    // ======================= registro de desplazamiento =====================
    reg [12:0] r0, r1, r2;

    always @(posedge clk) begin
        if (rst) begin
            r0 <= 13'd0;
            r1 <= 13'd0;
            r2 <= 13'd0;
        end else if (din_valid) begin
            r0 <= din;
            r1 <= r0;
            r2 <= r1;
        end
    end

    // ======================= comparadores "menor que" =======================
    // x - y = x + ~y + 1 ; el bit 13 es Cout. Cout = 0 <=> x < y
    wire [13:0] d_ab = {1'b0, r0} + {1'b0, ~r1} + 14'd1;
    wire [13:0] d_ac = {1'b0, r0} + {1'b0, ~r2} + 14'd1;
    wire [13:0] d_bc = {1'b0, r1} + {1'b0, ~r2} + 14'd1;

    wire ab = ~d_ab[13];      // r0 < r1
    wire ac = ~d_ac[13];      // r0 < r2
    wire bc = ~d_bc[13];      // r1 < r2

    // ======================= seleccion ======================================
    wire sel_a = ab ^ ac;
    wire sel_b = ab ^ ~bc;

    wire [12:0] m_bc = sel_b ? r1 : r2;     // primer mux
    assign      med  = sel_a ? r0 : m_bc;   // segundo mux

endmodule

`default_nettype wire
