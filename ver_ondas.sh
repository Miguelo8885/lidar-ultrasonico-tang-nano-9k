#!/bin/bash
# =====================================================================
# ver_ondas.sh  -  abre GTKWave con las senales ya agregadas
#
# Uso (dentro de lidar_scanner, DESPUES de ./simular.sh):
#   ./ver_ondas.sh tick_gen
#   ./ver_ondas.sh servo_pwm
#   ./ver_ondas.sh <cualquier modulo>                 (sin senales precargadas)

# =====================================================================
cd "$(dirname "$0")" || exit 1
m="$1"
if [ -z "$m" ]; then echo "Uso: ./ver_ondas.sh <modulo>"; exit 1; fi
if [ ! -f "sim/tb_$m.vcd" ]; then
    echo "No existe sim/tb_$m.vcd. Primero corran:  ./simular.sh $m"
    exit 1
fi
if [ -f "ondas/$m.gtkw" ]; then
    gtkwave "sim/tb_$m.vcd" "ondas/$m.gtkw" > /dev/null 2>&1 &
else
    gtkwave "sim/tb_$m.vcd" > /dev/null 2>&1 &
fi
