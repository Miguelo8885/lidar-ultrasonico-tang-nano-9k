// =============================================================================
// depth_ram.v
// Proyecto: escaner LIDAR en Tang Nano 9K (Electronica Digital)
//
// Que hace:
//   Memoria de doble puerto simple (un puerto escribe, el otro lee), con un
//   reloj distinto en cada puerto. Guarda el indice de color (4 bits) de
//   cada punto de la rejilla.
//     - Escritura: dominio del barrido (27 MHz), desde scan_fsm.
//     - Lectura:   desde mem_monitor (en el sistema rclk = wclk = 27 MHz).
//   El cruce entre los dos dominios de reloj se hace en las celdas de la
//   memoria: ningun registro muestrea directamente una senal del otro reloj.
//
// Interfaz:
//   wclk   entrada  1 bit   reloj de escritura (27 MHz)
//   we     entrada  1 bit   habilitacion de escritura (pulso, de scan_fsm)
//   waddr  entrada  8 bits  direccion {row, col} (del grid_walker)
//   wdata  entrada  4 bits  indice de color (de depth_quant)
//   rclk   entrada  1 bit   reloj de lectura (27 MHz en el sistema)
//   raddr  entrada  8 bits  direccion que pide mem_monitor
//   rdata  salida   4 bits  palabra leida, UN ciclo de rclk despues de raddr
//
// Correspondencia con el diagrama (docs/depth_ram):
//   mem       arreglo de 256 palabras x 4 bits
//   escritura flanco de wclk: si we, mem[waddr] <- wdata
//             (decodificador 8 -> 256 de waddr, AND we, habilita una palabra)
//   lectura   flanco de rclk: rdata <- mem[raddr]
//             (mux 256:1 de 4 bits seguido de un registro)
//
// Decisiones:
//   - Direccion {row, col}: solo cables; usa 144 de 256 palabras.
//   - Doble reloj: forma estandar de cruzar un bus de varios bits entre
//     dominios. Leer la misma palabra mientras se escribe da el valor viejo
//     o el nuevo; la siguiente lectura ya trae el valor nuevo.
//   - Lectura registrada (latencia de 1 ciclo): asi la infiere Gowin como un
//     bloque BSRAM y no como cientos de flip-flops.
//   - Contenido inicial 15 (fondo, negro): la pantalla arranca negra.
//   - Sin reset: el contenido de una memoria no se borra con reset.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module depth_ram (
    input  wire       wclk,
    input  wire       we,
    input  wire [7:0] waddr,
    input  wire [3:0] wdata,
    input  wire       rclk,
    input  wire [7:0] raddr,
    output reg  [3:0] rdata
);

    reg [3:0] mem [0:255];

    // Contenido inicial: todo en 15 (negro)
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) mem[i] = 4'hF;
        rdata = 4'hF;
    end

    // Puerto de escritura (dominio de 27 MHz)
    always @(posedge wclk) begin
        if (we) mem[waddr] <= wdata;
    end

    // Puerto de lectura
    always @(posedge rclk) begin
        rdata <= mem[raddr];
    end

endmodule

`default_nettype wire
