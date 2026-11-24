// =============================================================================
// mem_monitor.v
// Proyecto: escaner LIDAR en Tang Nano 9K (Electronica Digital)
//
// Que hace:
//   Cada vez que scan_fsm escribe un punto en depth_ram (we = 1), envia al PC
//   por UART una linea de texto con los datos de ese punto y el contenido
//   completo de la memoria, leido por su puerto de lectura. En el PC,
//   ver_memoria.py dibuja la imagen.
//
// Formato de la linea (280 bytes, ~24 ms a 115 200 baudios):
//   'P'  r c i  t0(4) t1(4) t2(4) med(4) mm(3)  <256 digitos de la RAM>  '\n'
//   r, c, i  fila, columna e indice de color escritos
//   t0..t2   las 3 mediciones del punto en us, de la mas vieja a la mas nueva
//   med, mm  mediana en us y distancia en mm
//   RAM      las direcciones 0 a 255 en orden ({row, col})
//   Todo en hexadecimal (digitos '0'..'9', 'A'..'F').
//
// Interfaz:
//   clk, rst  entradas  1 bit    reloj de 27 MHz y reset sincrono
//   done      entrada   1 bit    medicion lista (hcsr04_ctrl)
//   t_us      entrada   13 bits  medicion (hcsr04_ctrl)
//   we        entrada   1 bit    se escribe un punto (scan_fsm)
//   row, col  entradas  4 bits   punto escrito (grid_walker)
//   idx       entrada   4 bits   color escrito (depth_quant)
//   med       entrada   13 bits  mediana (median3)
//   d_mm      entrada   10 bits  distancia (echo_to_mm)
//   raddr     salida    8 bits   direccion de lectura de depth_ram
//   rdata     entrada   4 bits   dato leido de depth_ram (un ciclo despues)
//   tx        salida    1 bit    linea serial (pin 17)
//
// Estados (3 bits, binario, Moore):
//   IDLE    = 000   espera we
//   CHAR_P  = 001   envia 'P'
//   HEADER  = 010   envia los 22 digitos de la cabecera
//   DUMP    = 011   envia los 256 digitos de la RAM
//   CHAR_NL = 100   envia '\n'
//   101, 110, 111   no usados -> IDLE
//
// Correspondencia con el diagrama (docs/mem_monitor):
//   ta, tb, tc   registros de 13 bits en cadena, EN = done (como median3)
//   cap  = idle . we
//   hdr  registro de 88 bits: cap -> carga {row, col, idx, 000 tc, 000 tb,
//        000 ta, 000 med, 00 d_mm}; hsh = header . bdone -> {hdr[83:0], 0000}
//   cnt  contador de 8 bits, EN = bdone, Reset = rst + (n != state)
//   lastH = (cnt == 21)   lastD = (cnt == 255)   raddr = cnt
//   n2 = d_go + nl_stay
//   n1 = p_go + header + d_stay
//   n0 = cap + p_stay + h_go + d_stay
//     p_go = cp.bdone   p_stay = cp.bdone'   h_go = header.bdone.lastH
//     d_go = dump.bdone.lastD   d_stay = dump.(bdone' + lastD')
//     nl_stay = nl.bdone'
//   nib   = s0 ? rdata : hdr[87:84]
//   ascii = {0000, nib} + (mayor9 ? 0011 0111 : 0011 0000),
//           mayor9 = nib3 . (nib2 + nib1)
//   byte  = cp ? 0101 0000 ('P') : (nl ? 0000 1010 ('\n') : ascii)
//   trigger = cap + bdone . nl'   go1 <- trigger   go2 <- go1   start = go2
//
// Decisiones:
//   - Texto hexadecimal: se puede leer en cualquier terminal serial y nunca
//     contiene 'P' ni '\n', asi que las lineas no se confunden.
//   - Se envian las 256 direcciones: basta un contador de 8 bits; el PC
//     descarta las columnas 12 a 15.
//   - Se lee la RAM real por su puerto de lectura: lo que se ve en el PC es
//     lo que esta guardado.
//   - start llega dos ciclos despues del cambio de cnt: la lectura de la RAM
//     es registrada y rdata necesita un flanco para actualizarse.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module mem_monitor #(
    parameter DIV = 234
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        done,
    input  wire [12:0] t_us,
    input  wire        we,
    input  wire [3:0]  row,
    input  wire [3:0]  col,
    input  wire [3:0]  idx,
    input  wire [12:0] med,
    input  wire [9:0]  d_mm,
    output wire [7:0]  raddr,
    input  wire [3:0]  rdata,
    output wire        tx
);

    // ======================= registro de estado =============================
    reg  [2:0] state;
    wire [2:0] n;
    wire       s2 = state[2], s1 = state[1], s0 = state[0];

    always @(posedge clk) begin
        if (rst) state <= 3'b000;
        else     state <= n;
    end

    // ======================= decodificacion =================================
    wire idle   = ~s2 & ~s1 & ~s0;
    wire cp     = ~s2 & ~s1 &  s0;
    wire header = ~s2 &  s1 & ~s0;
    wire dump   = ~s2 &  s1 &  s0;
    wire nl     =  s2 & ~s1 & ~s0;

    wire bdone;                         // de uart_tx: termino un byte
    wire cap = idle & we;               // capturar el punto

    // ======================= las tres mediciones ============================
    reg [12:0] ta, tb, tc;              // ta la mas nueva

    always @(posedge clk) begin
        if (rst) begin
            ta <= 13'd0; tb <= 13'd0; tc <= 13'd0;
        end else if (done) begin
            ta <= t_us; tb <= ta; tc <= tb;
        end
    end

    // ======================= registro de cabecera ===========================
    reg  [87:0] hdr;
    wire        hsh = header & bdone;
    wire [87:0] hdr_load  = {row, col, idx, 3'b000, tc, 3'b000, tb, 3'b000, ta,
                             3'b000, med, 2'b00, d_mm};
    wire [87:0] hdr_shift = {hdr[83:0], 4'b0000};

    always @(posedge clk) begin
        if (rst)               hdr <= 88'd0;
        else if (cap | hsh)    hdr <= cap ? hdr_load : hdr_shift;
    end

    // ======================= contador de bytes / direccion ==================
    reg  [7:0] cnt;
    wire       cnt_rst = rst | (n != state);
    wire       lastH   = (cnt == 8'd21);
    wire       lastD   = (cnt == 8'd255);

    always @(posedge clk) begin
        if (cnt_rst)    cnt <= 8'd0;
        else if (bdone) cnt <= cnt + 8'd1;
    end

    assign raddr = cnt;

    // ======================= estado siguiente ===============================
    wire bdone_n = ~bdone;
    wire p_go    = cp & bdone;
    wire p_stay  = cp & bdone_n;
    wire h_go    = header & bdone & lastH;
    wire d_go    = dump & bdone & lastD;
    wire d_stay  = dump & (bdone_n | ~lastD);
    wire nl_stay = nl & bdone_n;

    assign n[2] = d_go | nl_stay;
    assign n[1] = p_go | header | d_stay;
    assign n[0] = cap | p_stay | h_go | d_stay;

    // ======================= byte a enviar ==================================
    wire [3:0] nib    = s0 ? rdata : hdr[87:84];
    wire       mayor9 = nib[3] & (nib[2] | nib[1]);
    wire [7:0] off    = mayor9 ? 8'b0011_0111 : 8'b0011_0000;  // 'A'-10 : '0'
    wire [7:0] ascii  = {4'b0000, nib} + off;
    wire [7:0] m_nl   = nl ? 8'b0000_1010 : ascii;            // '\n'
    wire [7:0] byte_tx = cp ? 8'b0101_0000 : m_nl;            // 'P'

    // ======================= arranque de cada byte ==========================
    wire trigger = cap | (bdone & ~nl);
    reg  go1, go2;

    always @(posedge clk) begin
        if (rst) begin go1 <= 1'b0; go2 <= 1'b0; end
        else     begin go1 <= trigger; go2 <= go1; end
    end

    // ======================= transmisor =====================================
    wire busy;

    uart_tx #(.DIV(DIV)) u_tx (
        .clk(clk), .rst(rst), .start(go2), .data(byte_tx),
        .tx(tx), .busy(busy), .bdone(bdone)
    );

endmodule

`default_nettype wire
