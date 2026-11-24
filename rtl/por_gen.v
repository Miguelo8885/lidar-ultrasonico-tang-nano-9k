// =============================================================================
// por_gen.v  (reset de encendido, "power-on reset")
// Proyecto: escaner LIDAR en Tang Nano 9K (Electronica Digital)
//
// Que hace:
//   Mantiene rst_por = 1 durante los primeros 2^W - 1 ciclos de reloj despues
//   de encender (65 535 ciclos = 2,43 ms con W = 16 y 27 MHz) y despues lo deja
//   en 0 para siempre. Es la fuente del reset de todo el sistema al encender.
//
// Interfaz:
//   clk      entrada  1 bit  reloj de 27 MHz
//   rst_por  salida   1 bit  1 mientras el sistema arranca
//   listo    salida   1 bit  1 cuando termino el arranque (LED)
//
// Correspondencia con el diagrama (docs/por_gen):
//   c      contador de W bits, EN = listo', SIN reset
//   listo  = (c == 1...1)       (AND de los W bits)
//   rst_por = listo'
//
// Decisiones:
//   - Es el unico registro del diseno sin entrada de reset: es quien genera
//     el reset. Arranca en 0 porque, al terminar de configurarse, la FPGA
//     pone todos sus flip-flops en su valor inicial (aqui 0).
//   - Al llegar a 1...1 el contador se detiene (EN = listo'), asi rst_por no
//     vuelve a subir nunca.
//   - Reemplaza al PLL, que solo se usaba por su senal lock: sin la salida
//     HDMI no hace falta un segundo reloj.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module por_gen #(
    parameter W = 16
) (
    input  wire clk,
    output wire rst_por,
    output wire listo
);

    reg [W-1:0] c = {W{1'b0}};

    assign listo   = &c;
    assign rst_por = ~listo;

    always @(posedge clk) begin
        if (~listo) c <= c + 1'b1;
    end

endmodule

`default_nettype wire
