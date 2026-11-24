// =============================================================================
// echo_to_mm.v
// Proyecto: escaner LIDAR en Tang Nano 9K (Electronica Digital)
//
// Que hace:
//   Convierte el tiempo de eco (us, ida y vuelta) en distancia (mm):
//     d = 343 m/s * t / 2 = 0,1715 mm por us  ~=  11/64 = 0,171875 (+0,22 %)
//   11t = 8t + 2t + t   (dos desplazadores y dos sumadores)
//   /64 = desplazar 6 posiciones a la derecha (truncando)
//   Es combinacional: no tiene reloj ni reset.
//
// Interfaz:
//   t_us  entrada  13 bits  tiempo de eco (med de median3), VALIDO HASTA 5 957
//   d_mm  salida   10 bits  distancia en mm (0 a 1 023)
//
// Correspondencia con el diagrama (docs/echo_to_mm):
//   ext  = {000, t_us}          extension con ceros a 16 bits
//   x8   = ext << 3             desplazador, shamt = 011
//   x2   = ext << 1             desplazador, shamt = 001
//   s10  = x8 + x2   (= 10t)    sumador de 16 bits
//   s11  = s10 + ext (= 11t)    sumador de 16 bits
//   d_mm = (s11 >> 6)[9:0]      desplazador, shamt = 0110 (bits 15..6)
//
// Decisiones:
//   - Ancho minimo: 16 bits alcanzan si 11t <= 65 535, es decir t <= 5 957.
//     hcsr04_ctrl satura en T_MAX = 5 000, asi que la condicion siempre se
//     cumple (5 000 us -> 859 mm). Para t > 5 957 la suma se desborda.
//     Alternativa documentada: 17 bits internos y 11 de salida, valida para
//     cualquier entrada de 13 bits (cuesta un bit mas por sumador).
//   - Se trunca: error < 1 mm. Redondear costaria otro sumador (+32).
//   - La velocidad del sonido varia ~0,6 m/s por grado C; en el laboratorio
//     (18 a 20 C) el error extra es < 1 %, irrelevante para los colores.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module echo_to_mm (
    input  wire [12:0] t_us,
    output wire [9:0]  d_mm
);

    wire [15:0] ext = {3'b000, t_us};
    wire [15:0] x8  = ext << 3'b011;
    wire [15:0] x2  = ext << 3'b001;
    wire [15:0] s10 = x8 + x2;
    wire [15:0] s11 = s10 + ext;
    wire [15:0] sh  = s11 >> 4'b0110;

    assign d_mm = sh[9:0];

endmodule

`default_nettype wire
