#!/bin/bash
# =====================================================================
# simular.sh  -  corre los testbenches con Icarus Verilog (Ubuntu)
#
# Uso (en una terminal, dentro de la carpeta lidar_scanner):
#   ./simular.sh              corre TODOS los testbenches
#   ./simular.sh servo_pwm    corre solo uno (tick_gen, sync_ff, debounce,
#                             grid_walker, servo_pwm, scan_fsm, hcsr04_ctrl, median3,
#                             echo_to_mm, depth_quant, depth_ram, uart_tx,
#                             mem_monitor o lidar_top)
#   ./simular.sh monitor      sistema con el monitor por USB (no corre con
#                             "todos"; tarda ~2 minutos)
#
# lidar_top simula el sistema completo a velocidad real: tarda ~1 minuto.
#
# Todo queda guardado en sim/resultados.txt
# =====================================================================
cd "$(dirname "$0")" || exit 1
mkdir -p sim
R=sim/resultados.txt

# archivos de rtl/ que necesita cada testbench
fuentes() {
    case "$1" in
        scan_fsm)  echo "rtl/grid_walker.v rtl/hcsr04_ctrl.v rtl/median3.v rtl/echo_to_mm.v rtl/depth_quant.v rtl/depth_ram.v rtl/scan_fsm.v" ;;
        por_gen)     echo "rtl/por_gen.v" ;;
        mem_monitor) echo "rtl/uart_tx.v rtl/depth_ram.v rtl/mem_monitor.v" ;;
        monitor)   echo "rtl/por_gen.v rtl/tick_gen.v rtl/sync_ff.v rtl/debounce.v rtl/grid_walker.v rtl/servo_pwm.v rtl/scan_fsm.v rtl/hcsr04_ctrl.v rtl/median3.v rtl/echo_to_mm.v rtl/depth_quant.v rtl/depth_ram.v rtl/uart_tx.v rtl/mem_monitor.v monitor/lidar_top_monitor.v" ;;
        lidar_top) echo "rtl/por_gen.v rtl/tick_gen.v rtl/sync_ff.v rtl/debounce.v rtl/grid_walker.v rtl/servo_pwm.v rtl/scan_fsm.v rtl/hcsr04_ctrl.v rtl/median3.v rtl/echo_to_mm.v rtl/depth_quant.v rtl/depth_ram.v rtl/lidar_top.v" ;;
        *)        echo "rtl/$1.v" ;;
    esac
}

simular() {
    echo "Simulando $1 ..."
    { echo; echo "---------------- $1 ----------------"; } >> "$R"
    if iverilog -o "sim/tb_$1.vvp" $(fuentes "$1") "tb/tb_$1.v" >> "$R" 2>&1; then
        vvp "sim/tb_$1.vvp" >> "$R" 2>&1
    else
        echo "ERROR DE COMPILACION en $1" >> "$R"
    fi
}

if ! command -v iverilog > /dev/null; then
    echo "No encuentro iverilog. Instalenlo con:  sudo apt install iverilog gtkwave"
    exit 1
fi

{ echo "RESULTADOS DE SIMULACION"; date; iverilog -V 2>&1 | head -1; } > "$R"

if [ $# -eq 0 ]; then
    MODULOS="por_gen tick_gen sync_ff debounce grid_walker servo_pwm hcsr04_ctrl median3 echo_to_mm depth_quant depth_ram scan_fsm uart_tx mem_monitor lidar_top"
else
    MODULOS="$*"
fi

for m in $MODULOS; do
    if [ ! -f "tb/tb_$m.v" ]; then
        echo "No existe tb/tb_$m.v (revisen el nombre del modulo)"
        exit 1
    fi
    simular "$m"
done

{ echo; echo "========== RESUMEN =========="; grep -E "PRUEBA|COMPILACION" "$R"; } > "$R.tmp"
cat "$R.tmp" >> "$R"; rm -f "$R.tmp"

cat "$R"
echo
echo "Listo. El resultado completo quedo en $R"
