// =============================================================================
// depth_quant.v
// Proyecto: escaner LIDAR en Tang Nano 9K (Electronica Digital)
//
// Que hace:
//   Convierte la distancia en mm en un indice de color de 4 bits:
//     d < D_NEAR                          -> 0  (rojo, lo mas cercano)
//     D_NEAR <= d < D_NEAR + 480          -> (d - D_NEAR) / 32  (0 a 14)
//     d >= D_NEAR + 480                   -> 15 (fondo, negro)
//   Con D_NEAR = 200: escala de 200 a 680 mm en pasos de 32 mm.
//   Es combinacional: no tiene reloj ni reset.
//
// Interfaz:
//   d_mm  entrada  10 bits  distancia en mm (de echo_to_mm)
//   idx   salida   4 bits   indice de color (0 a 14 escala, 15 fondo)
//
// Parametro:
//   D_NEAR  distancia del color rojo (200 mm). Se calibra para que la pared
//           del fondo quede en el indice 15 (pared >= D_NEAR + 480).
//
// Correspondencia con el diagrama (docs/depth_quant):
//   resta   = d_mm + ~D_NEAR + 1    restador de 11 bits (bit 10 = Cout)
//   near    = Cout'                 (d_mm < D_NEAR)
//   q       = resta[9:5]            dividir entre 32: tomar bits
//   sat[i]  = q[i] + q[4]           OR por bit: q >= 16 fuerza 1111
//   idx[i]  = near' . sat[i]        AND por bit: cercano fuerza 0000
//
// Decisiones:
//   - Paso de 32 mm (potencia de 2): dividir es tomar bits.
//   - q = 15 (680 a 711 mm) ya da 1111, asi que la saturacion solo mira q[4].
//   - Fondo de color propio (15): pared y "sin eco" se ven negros.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module depth_quant #(
    parameter [9:0] D_NEAR = 10'd200
) (
    input  wire [9:0] d_mm,
    output wire [3:0] idx
);

    // ---------------- restador de 11 bits: d_mm - D_NEAR -------------------
    wire [10:0] resta = {1'b0, d_mm} + {1'b0, ~D_NEAR} + 11'd1;
    wire        near  = ~resta[10];      // Cout = 0 <=> d_mm < D_NEAR

    // ---------------- dividir entre 32 --------------------------------------
    wire [4:0]  q = resta[9:5];

    // ---------------- saturar en el fondo y forzar el rojo ------------------
    wire [3:0]  sat = q[3:0] | {4{q[4]}};
    assign      idx = sat & {4{~near}};

endmodule

`default_nettype wire
