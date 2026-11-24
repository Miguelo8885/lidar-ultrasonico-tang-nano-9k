// =============================================================================
// tick_gen.v
// Proyecto: escaner LIDAR en Tang Nano 9K (Electronica Digital)
//
// Que hace:
//   Genera "tick", un pulso de UN ciclo de reloj cada 1 us.
//   El reloj es de 27 MHz, asi que 1 us = 27 ciclos.
//   Un contador de 5 bits cuenta 0, 1, 2, ..., 26 y vuelve a 0.
//   Cuando el contador vale 26 (el ciclo numero 27), tick = 1.
//
// Interfaz:
//   clk   entrada  1 bit   reloj de 27 MHz
//   rst   entrada  1 bit   reset sincrono (activo en 1)
//   tick  salida   1 bit   pulso de un ciclo cada 27 ciclos (1 us)
//
// Correspondencia con el diagrama (docs/tick_gen):
//   cnt      registro de 5 bits, sin EN, reset sincrono
//   cnt_inc  salida del sumador cnt + 00001 (Cin = 0, Cout sin conectar)
//   tick     comparador de igualdad cnt == 11010 (26)
//   cnt_rst  OR de rst y tick (reset sincrono del registro)
//
// Decisiones:
//   - tick NO se usa como reloj de nadie: es una habilitacion (EN) que dura
//     un ciclo. Todo el sistema sigue usando clk.
//   - 5 bits alcanzan hasta 31; se necesita llegar a 26.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none   // obliga a declarar todos los cables (evita errores de tipeo)

module tick_gen (
    input  wire clk,
    input  wire rst,
    output wire tick
);

    // Constante del comparador: 26 = 11010 (el ciclo 27 de la cuenta)
    localparam [4:0] LAST = 5'b11010;

    // ---------------- cables internos (mismos nombres del diagrama) --------
    reg  [4:0] cnt;       // salida Q del registro
    wire [4:0] cnt_inc;   // salida del sumador
    wire       cnt_rst;   // reset sincrono del registro

    // ---------------- sumador: cnt + 00001 ---------------------------------
    assign cnt_inc = cnt + 5'b00001;

    // ---------------- comparador: cnt == 26 -> tick -------------------------
    assign tick = (cnt == LAST);

    // ---------------- OR del reset: rst + tick -------------------------------
    assign cnt_rst = rst | tick;

    // ---------------- registro de 5 bits con reset sincrono -----------------
    always @(posedge clk) begin
        if (cnt_rst)
            cnt <= 5'b00000;
        else
            cnt <= cnt_inc;
    end

endmodule

`default_nettype wire
