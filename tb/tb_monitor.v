// tb_monitor.v: sistema completo con el monitor (lidar_top_monitor), velocidad real.
// Como correrlo: ./simular.sh monitor
// Un receptor UART decodifica lo que sale por tx_pc y lo guarda en
// sim/monitor_uart.txt; ver_memoria.py --archivo lo interpreta despues.
`timescale 1ns / 1fs
module tb_monitor;
    reg clk_27 = 0, btn_s1 = 1, btn_s2 = 1, echo = 0;
    wire trig, pwm_pan, pwm_tilt, tx_pc;
    wire [5:0] led;
    lidar_top_monitor dut (.clk_27(clk_27), .btn_s1(btn_s1), .btn_s2(btn_s2), .echo(echo),
        .trig(trig), .pwm_pan(pwm_pan), .pwm_tilt(pwm_tilt), .led(led), .tx_pc(tx_pc));
    always #18.5185 clk_27 = ~clk_27;

    // sensor: tres ecos distintos por punto (la mediana debe ser el del medio)
    integer n_trig = 0, e;
    always @(negedge trig) if ($time > 5000) begin   // ignora el x -> 0 inicial
        n_trig = n_trig + 1;
        case (n_trig % 3) 1: e = 1749; 2: e = 2500; default: e = 1600; endcase
        if (n_trig > 3) e = e + 1500;          // el segundo punto, mas lejos
        #2_200_000 echo = 1;              // retardo medido en el clon
        #(e * 1000) echo = 0;
    end

    // receptor UART 115 385 baudios
    localparam real BIT = 234 * 37.037037;
    integer f, nlin = 0, i;
    reg [7:0] b;
    initial f = $fopen("sim/monitor_uart.txt", "w");
    always @(negedge tx_pc) begin
        #(BIT * 1.5);
        for (i = 0; i < 8; i = i + 1) begin b[i] = tx_pc; #(BIT); end
        $fwrite(f, "%c", b);
        if (b == 8'h0A) nlin = nlin + 1;
    end

    initial begin
        #10_000_000;
        btn_s1 = 0; #30_000_000; btn_s1 = 1;
        wait (nlin == 2);
        $fclose(f);
        $display("monitor: 2 lineas recibidas en sim/monitor_uart.txt");
        $display("Revisarlas con: python3 monitor/ver_memoria.py --archivo sim/monitor_uart.txt");
        $finish;
    end
    initial begin #2_000_000_000; $display("TIEMPO LIMITE"); $finish; end
endmodule
