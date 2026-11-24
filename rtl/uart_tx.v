// =============================================================================
// uart_tx.v
// Proyecto: escaner LIDAR en Tang Nano 9K (Electronica Digital)
//
// Que hace:
//   Envia un byte por una linea serial en formato UART 8N1: un bit de inicio
//   (0), los 8 bits del dato empezando por el menos significativo y un bit de
//   parada (1). En reposo la linea queda en 1. Con DIV = 234 cada bit dura
//   234 ciclos de 27 MHz: 115 385 baudios (0,16 % sobre 115 200).
//
// Interfaz:
//   clk    entrada  1 bit   reloj de 27 MHz
//   rst    entrada  1 bit   reset sincrono
//   start  entrada  1 bit   pulso de un ciclo: cargar data y empezar a enviar
//   data   entrada  8 bits  byte que se quiere enviar
//   tx     salida   1 bit   linea serial (pin 17 -> chip USB BL702)
//   busy   salida   1 bit   1 mientras se envian los 10 bits
//   bdone  salida   1 bit   pulso de un ciclo al terminar el bit de parada
//
// Parametro:
//   DIV    ciclos de reloj por bit (234). Maximo 256 (bcnt es de 8 bits).
//
// Correspondencia con el diagrama (docs/uart_tx):
//   ld    = start . busy'                    (start se ignora si busy = 1)
//   bcnt  contador de 8 bits, EN = busy, Reset = rst + busy' + bt
//   bt    = (bcnt == DIV-1)                  (fin de cada bit)
//   nb    registro de 4 bits, EN = ld + bt, D = ld ? 1010 : nb + 1111
//   busy  = nb3 + nb2 + nb1 + nb0            (nb != 0)
//   sh    registro de 10 bits, EN = ld + bt, Reset -> 11 1111 1111
//         D = ld ? {1, data, 0} : {1, sh[9:1]}   (desplazamiento a la derecha)
//   tx    = sh[0]
//   bdone = bt . (nb == 0001)                (bt del ultimo bit)
//
// Decisiones:
//   - Contador de baudios propio: un bit dura 8,68 us, no cabe un numero
//     entero de ticks de 1 us.
//   - tx sale directo de un flip-flop: sin glitches. Como en cada
//     desplazamiento entra un 1, al terminar sh queda lleno de unos y la
//     linea vuelve sola al reposo; no hace falta un mux en la salida.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module uart_tx #(
    parameter DIV = 234
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [7:0] data,
    output wire       tx,
    output wire       busy,
    output wire       bdone
);

    localparam [7:0] LIM_BIT = DIV - 1;

    reg  [7:0] bcnt;
    reg  [3:0] nb;
    reg  [9:0] sh;

    // ======================= senales de control =============================
    wire ld  = start & ~busy;
    wire bt  = (bcnt == LIM_BIT);
    wire en  = ld | bt;

    assign busy  = nb[3] | nb[2] | nb[1] | nb[0];
    assign bdone = bt & (nb == 4'b0001);

    // ======================= contador de baudios ============================
    wire bcnt_rst = rst | ~busy | bt;

    always @(posedge clk) begin
        if (bcnt_rst)  bcnt <= 8'd0;
        else if (busy) bcnt <= bcnt + 8'd1;
    end

    // ======================= contador de bits ===============================
    wire [3:0] nb_dec = nb + 4'b1111;           // nb - 1
    wire [3:0] nb_d   = ld ? 4'b1010 : nb_dec;  // 10 bits por byte

    always @(posedge clk) begin
        if (rst)     nb <= 4'b0000;
        else if (en) nb <= nb_d;
    end

    // ======================= registro de desplazamiento =====================
    wire [9:0] sh_d = ld ? {1'b1, data, 1'b0} : {1'b1, sh[9:1]};

    always @(posedge clk) begin
        if (rst)     sh <= 10'b11_1111_1111;
        else if (en) sh <= sh_d;
    end

    assign tx = sh[0];

endmodule

`default_nettype wire
