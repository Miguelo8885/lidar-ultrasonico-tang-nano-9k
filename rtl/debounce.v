// =============================================================================
// debounce.v
// Proyecto: escaner LIDAR en Tang Nano 9K (Electronica Digital)
//
// Que hace:
//   Antirrebote por ventana de 20 ms. El boton de la tarjeta es activo en
//   bajo (pulsado = 0). Un cambio del boton solo se acepta si se mantiene
//   20 000 ticks seguidos (20 ms). Si el boton rebota (vuelve al valor
//   oficial antes de completar la ventana), el contador se reinicia.
//
// Interfaz:
//   clk      entrada  1 bit  reloj de 27 MHz
//   rst      entrada  1 bit  reset sincrono (en el sistema: rst_btn = rst_por)
//   tick     entrada  1 bit  pulso de 1 us (de tick_gen)
//   btn      entrada  1 bit  boton YA sincronizado por sync_ff (activo en bajo)
//   pressed  salida   1 bit  estado oficial del boton: 1 = pulsado
//   press    salida   1 bit  pulso de UN ciclo cuando se acepta una pulsacion
//
// Correspondencia con el diagrama (docs/debounce):
//   p_in     = btn'                     (boton en logica positiva)
//   stable   registro de 1 bit, EN = accept, D = p_in; su Q es pressed
//   diff     = p_in XOR pressed         (el boton difiere del estado oficial)
//   cnt      registro de 15 bits, EN = en_cnt, Reset = cnt_rst
//   cnt_inc  = cnt + 1
//   full     = (cnt == 100 1110 0001 1111) = 19 999
//   en_cnt   = tick . diff
//   accept   = tick . diff . full       (se completa el tick numero 20 000)
//   cnt_rst  = rst + diff' + accept
//   press    = accept . p_in            (solo al aceptar una PULSACION)
//
// Decisiones:
//   - Ventana de 20 ms: mas larga que los rebotes tipicos (pocos ms) y
//     suficientemente corta para que la respuesta se sienta inmediata.
//   - press solo se genera al pulsar, no al soltar.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module debounce (
    input  wire clk,
    input  wire rst,
    input  wire tick,
    input  wire btn,
    output wire pressed,
    output wire press
);

    localparam [14:0] FULL_VAL = 15'b100_1110_0001_1111;   // 19 999

    // ---------------- cables internos (nombres del diagrama) ---------------
    wire        p_in;
    reg         stable;
    wire        diff;
    reg  [14:0] cnt;
    wire [14:0] cnt_inc;
    wire        full;
    wire        en_cnt;
    wire        accept;
    wire        cnt_rst;

    // ---------------- estado oficial del boton -----------------------------
    assign p_in    = ~btn;              // inversor: pulsado = 1
    assign pressed = stable;
    assign diff    = p_in ^ pressed;    // XOR

    // Registro "stable": reset sincrono prioritario, EN = accept
    always @(posedge clk) begin
        if (rst)
            stable <= 1'b0;
        else if (accept)
            stable <= p_in;
    end

    // ---------------- contador de la ventana (15 bits) ---------------------
    assign cnt_inc = cnt + 15'd1;
    assign full    = (cnt == FULL_VAL);

    always @(posedge clk) begin
        if (cnt_rst)
            cnt <= 15'd0;
        else if (en_cnt)
            cnt <= cnt_inc;
    end

    // ---------------- logica de control ------------------------------------
    assign en_cnt  = tick & diff;
    assign accept  = tick & diff & full;
    assign cnt_rst = rst | ~diff | accept;   // OR de 3 entradas
    assign press   = accept & p_in;

endmodule

`default_nettype wire
