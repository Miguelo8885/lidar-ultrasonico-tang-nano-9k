// =============================================================================
// grid_walker.v
// Proyecto: escaner LIDAR en Tang Nano 9K (Electronica Digital)
//
// Que hace:
//   Lleva la posicion actual en la rejilla de 12 x 12 y la recorre en
//   serpentina: filas pares de izquierda a derecha (col 0 -> 11), filas
//   impares de derecha a izquierda (col 11 -> 0). Con cada pulso "step"
//   avanza un punto. El ultimo punto es (fila 11, col 0); el step siguiente
//   vuelve a (0, 0).
//
// Interfaz:
//   clk   entrada  1 bit   reloj de 27 MHz
//   rst   entrada  1 bit   reset sincrono (activo en 1): vuelve a (0, 0)
//   step  entrada  1 bit   pulso de un ciclo: avanzar al siguiente punto
//   row   salida   4 bits  fila actual (0 a 11)
//   col   salida   4 bits  columna actual (0 a 11)
//   addr  salida   8 bits  {row, col}: direccion para la memoria de profundidad
//   last  salida   1 bit   1 mientras se esta en el ultimo punto (11, 0)
//
// Correspondencia con el diagrama (docs/grid_walker):
//   dir         = row[0]                         (0: col sube, 1: col baja)
//   col_move    = col + {dir, dir, dir, 1}       (+1 o -1 en complemento a 2)
//   row_inc     = row + 0001
//   at_right    = (col == 1011)   at_left = (col == 0000)   row_last = (row == 1011)
//   end_of_row  = dir ? at_left : at_right       (mux 2:1)
//   last        = row_last . end_of_row
//   en_col      = step . end_of_row'
//   en_row      = step . end_of_row
//   rst_s       = rst + step . last              (OR de 2 entradas)
//   Registros de 4 bits con reset sincrono prioritario sobre EN.
//
// Decisiones:
//   - Serpentina: el servo nunca da el salto largo de regreso de una fila a
//     la siguiente; solo en el ultimo punto vuelve a (0, 0).
//   - Sin entrada clear: al detener el barrido la posicion se conserva y el
//     regreso al inicio lo hacen rst o step . last.
//   - Las columnas 12 a 15 y filas 12 a 15 nunca se alcanzan partiendo de
//     un reset.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module grid_walker (
    input  wire       clk,
    input  wire       rst,
    input  wire       step,
    output wire [3:0] row,
    output wire [3:0] col,
    output wire [7:0] addr,
    output wire       last
);

    // ---------------- registros ---------------------------------------------
    reg  [3:0] row_q;   // registro "fila"
    reg  [3:0] col_q;   // registro "columna"

    // ---------------- cables internos (nombres del diagrama) ----------------
    wire       dir;
    wire [3:0] b_col;
    wire [3:0] col_move;
    wire [3:0] row_inc;
    wire       at_right, at_left, row_last;
    wire       end_of_row;
    wire       en_col, en_row;
    wire       rst_s;

    assign dir      = row_q[0];

    // Sumador de columna: B = {dir, dir, dir, 1}
    assign b_col    = {dir, dir, dir, 1'b1};
    assign col_move = col_q + b_col;

    // Incrementador de fila
    assign row_inc  = row_q + 4'b0001;

    // Comparadores de bordes
    assign at_right = (col_q == 4'b1011);
    assign at_left  = (col_q == 4'b0000);
    assign row_last = (row_q == 4'b1011);

    // Mux 2:1 y AND de last
    assign end_of_row = dir ? at_left : at_right;
    assign last       = row_last & end_of_row;

    // Logica de control
    assign en_col = step & ~end_of_row;
    assign en_row = step &  end_of_row;
    assign rst_s  = rst | (step & last);

    // Registro de fila: reset sincrono prioritario, EN = en_row
    always @(posedge clk) begin
        if (rst_s)
            row_q <= 4'b0000;
        else if (en_row)
            row_q <= row_inc;
    end

    // Registro de columna: reset sincrono prioritario, EN = en_col
    always @(posedge clk) begin
        if (rst_s)
            col_q <= 4'b0000;
        else if (en_col)
            col_q <= col_move;
    end

    // ---------------- salidas -------------------------------------------------
    assign row  = row_q;
    assign col  = col_q;
    assign addr = {row_q, col_q};

endmodule

`default_nettype wire
