// =============================================================================
// sync_ff.v
// Proyecto: escaner LIDAR en Tang Nano 9K (Electronica Digital)
//
// Que hace:
//   Sincroniza una senal externa (asincrona: puede cambiar en cualquier
//   instante, sin respetar el reloj) con el reloj de 27 MHz. Es UN flip-flop:
//   en cada flanco de subida copia la entrada. Desde ese momento la senal
//   solo cambia justo despues de un flanco, como todo lo demas del sistema.
//
// Interfaz:
//   clk      entrada  1 bit  reloj de 27 MHz
//   rst      entrada  1 bit  reset sincrono (activo en 1)
//   d_async  entrada  1 bit  senal externa (boton S1, boton S2 o Echo)
//   q_sync   salida   1 bit  la misma senal, ya sincronizada (1 ciclo despues)
//
// Parametro:
//   RESET_VAL  valor que toma la salida con el reset. Debe ser el valor de
//              reposo de la senal: 0 para Echo; para los botones, el valor
//              que tienen sin pulsar.
//
// Decisiones:
//   - Un solo flip-flop basta (indicacion del profesor): a 27 MHz hay casi un
//     periodo completo (37 ns) para que un posible estado metaestable se
//     resuelva antes del siguiente registro, porque despues de q_sync hay
//     muy poca logica.
//   - Las senales de varios bits no se sincronizan bit a bit con esto.
//   - Un pulso externo mas corto que un periodo de reloj se puede perder.
//     No es problema: botones y Echo duran microsegundos o mas.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module sync_ff #(
    parameter RESET_VAL = 1'b0
) (
    input  wire clk,
    input  wire rst,
    input  wire d_async,
    output reg  q_sync
);

    // Flip-flop D con reset sincrono
    always @(posedge clk) begin
        if (rst)
            q_sync <= RESET_VAL;
        else
            q_sync <= d_async;
    end

endmodule

`default_nettype wire
