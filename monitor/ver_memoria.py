#!/usr/bin/env python3
# =============================================================================
# ver_memoria.py  (TEMPORAL, demostracion)
#
# Muestra EN VIVO el contenido de depth_ram que la FPGA envia por el USB.
# Cada vez que se guarda un punto llega una linea con los datos del punto y
# las 144 palabras de la memoria; la ventana redibuja la rejilla de 12 x 12.
#
# Uso:
#   python ver_memoria.py COM5            (Windows; el puerto de la tarjeta)
#   python ver_memoria.py /dev/ttyUSB1    (Linux)
#   python ver_memoria.py --puertos       lista los puertos disponibles
#   python ver_memoria.py --demo          prueba la ventana sin la tarjeta
#   python ver_memoria.py --archivo f.txt imprime en texto los paquetes de f
#
# Teclas en la ventana:  h = espejo horizontal,  v = espejo vertical
# Requiere: pip install pyserial   (tkinter ya viene con Python en Windows)
# =============================================================================
import sys, threading, queue, time, random

BAUD = 115200
FILAS = COLS = 12
PALETA = ["#FF0000", "#FF5500", "#FFAA00", "#FFFF00", "#AAFF00", "#55FF00",
          "#00FF00", "#00FF55", "#00FFAA", "#00FFFF", "#00AAFF", "#0055FF",
          "#0000FF", "#5500FF", "#AA00FF", "#000000"]


def interpretar(linea):
    """Devuelve un dict con el paquete o None si la linea esta danada.
    Formato: 'P' + 22 digitos de cabecera + 256 digitos de la RAM (dir. 0..255)."""
    linea = linea.strip()
    if len(linea) != 1 + 22 + 256 or linea[0] != "P":
        return None
    try:
        h = lambda a, b: int(linea[a:b], 16)
        mem = [int(ch, 16) for ch in linea[23:]]
        # direccion = {fila, col} = fila*16 + col; las columnas 12..15 no se usan
        ram = [mem[f * 16 + c] for f in range(FILAS) for c in range(COLS)]
        return {"fila": h(1, 2), "col": h(2, 3), "idx": h(3, 4),
                "t": [h(4, 8), h(8, 12), h(12, 16)], "med": h(16, 20),
                "mm": h(20, 23), "ram": ram}
    except ValueError:
        return None


def texto(p):
    return ("punto (fila %d, col %d)  mediciones %s us  mediana %d us  "
            "%d mm  color %d" % (p["fila"], p["col"], p["t"], p["med"], p["mm"], p["idx"]))


# ---------------------------------------------------------------- fuentes
def leer_serial(puerto, q):
    import serial
    s = serial.Serial(puerto, BAUD, timeout=1)
    buf = b""
    while True:
        buf += s.read(s.in_waiting or 1)
        while b"\n" in buf:
            linea, buf = buf.split(b"\n", 1)
            p = interpretar(linea.decode("ascii", "replace"))
            q.put(p if p else "danado")


def demo(q):
    """Genera paquetes falsos con el mismo formato, en serpentina."""
    ram = [15] * 144
    while True:
        for f in range(FILAS):
            orden = range(COLS) if f % 2 == 0 else range(COLS - 1, -1, -1)
            for c in orden:
                mm = 250 + int(400 * (abs(c - 6) + abs(f - 6)) / 12) + random.randint(-20, 20)
                idx = 15 if mm >= 680 else max(0, (mm - 200) // 32)
                ram[f * COLS + c] = idx
                t = int(mm / 0.1715)
                mem = ["F"] * 256
                for ff in range(FILAS):
                    for cc in range(COLS):
                        mem[ff * 16 + cc] = "%X" % ram[ff * COLS + cc]
                linea = "P%X%X%X%04X%04X%04X%04X%03X%s" % (
                    f, c, idx, t - 30, t + 40, t, t, mm, "".join(mem))
                q.put(interpretar(linea))
                time.sleep(0.3)


# ---------------------------------------------------------------- ventana
def ventana(fuente, arg):
    import tkinter as tk
    q = queue.Queue()
    threading.Thread(target=fuente, args=(arg, q) if arg else (q,), daemon=True).start()

    L = 44
    raiz = tk.Tk()
    raiz.title("depth_ram en vivo")
    raiz.configure(bg="#202020")
    lienzo = tk.Canvas(raiz, width=COLS * L + 40, height=FILAS * L + 40,
                       bg="#202020", highlightthickness=0)
    lienzo.grid(row=0, column=0, padx=10, pady=10)
    panel = tk.Frame(raiz, bg="#202020")
    panel.grid(row=0, column=1, sticky="n", padx=10, pady=10)
    info = tk.Label(panel, justify="left", anchor="w", font=("Consolas", 12),
                    fg="white", bg="#202020", text="esperando datos...")
    info.pack(anchor="w")
    muestra = tk.Canvas(panel, width=200, height=30, bg="#202020", highlightthickness=0)
    muestra.pack(anchor="w", pady=8)
    ley = tk.Canvas(panel, width=230, height=16 * 20, bg="#202020", highlightthickness=0)
    ley.pack(anchor="w")
    for i, col in enumerate(PALETA):
        ley.create_rectangle(0, i * 20, 30, i * 20 + 18, fill=col, outline="gray")
        rango = "fondo (>= 680 mm)" if i == 15 else "%d a %d mm" % (200 + 32 * i, 231 + 32 * i)
        if i == 0: rango = "< 232 mm"
        ley.create_text(40, i * 20 + 9, anchor="w", fill="white", text="%2d  %s" % (i, rango))

    estado = {"ram": [15] * 144, "ultimo": None, "n": 0, "malos": 0, "fx": False, "fy": False}

    def dibujar():
        lienzo.delete("all")
        for f in range(FILAS):
            for c in range(COLS):
                x = (COLS - 1 - c if estado["fx"] else c) * L + 30
                y = (FILAS - 1 - f if estado["fy"] else f) * L + 30
                v = estado["ram"][f * COLS + c]
                ult = estado["ultimo"] == (f, c)
                lienzo.create_rectangle(x, y, x + L - 2, y + L - 2, fill=PALETA[v],
                                        outline="white" if ult else "#404040",
                                        width=4 if ult else 1)
                lienzo.create_text(x + L / 2, y + L / 2, text=str(v),
                                   fill="white" if v >= 12 else "black")
        for i in range(COLS):
            x = (COLS - 1 - i if estado["fx"] else i) * L + 30 + L / 2
            lienzo.create_text(x, 15, text=str(i), fill="gray")
        for i in range(FILAS):
            y = (FILAS - 1 - i if estado["fy"] else i) * L + 30 + L / 2
            lienzo.create_text(15, y, text=str(i), fill="gray")

    def revisar():
        while not q.empty():
            p = q.get()
            if p == "danado":
                estado["malos"] += 1
                continue
            estado["ram"] = p["ram"]
            estado["ultimo"] = (p["fila"], p["col"])
            estado["n"] += 1
            info.config(text=("Punto escrito: fila %d, columna %d\n\n"
                              "Mediciones:  %5d us\n             %5d us\n             %5d us\n"
                              "Mediana:     %5d us\nDistancia:   %5d mm\nColor:       %5d\n\n"
                              "Paquetes: %d   danados: %d") % (
                p["fila"], p["col"], *p["t"], p["med"], p["mm"], p["idx"],
                estado["n"], estado["malos"]))
            muestra.delete("all")
            muestra.create_rectangle(0, 0, 200, 30, fill=PALETA[p["idx"]], outline="white")
            print(texto(p))
        dibujar()
        raiz.after(100, revisar)

    def tecla(e):
        if e.char == "h": estado["fx"] = not estado["fx"]
        if e.char == "v": estado["fy"] = not estado["fy"]
    raiz.bind("<Key>", tecla)
    revisar()
    raiz.mainloop()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Uso: python ver_memoria.py COM5   (o --demo, --puertos, --archivo f.txt)")
    elif sys.argv[1] == "--puertos":
        from serial.tools import list_ports
        for p in list_ports.comports():
            print(p.device, "-", p.description)
    elif sys.argv[1] == "--archivo":
        for linea in open(sys.argv[2]):
            p = interpretar(linea)
            print(texto(p) if p else "linea danada")
            if p:
                for f in range(FILAS):
                    print("   " + " ".join("%2d" % v for v in p["ram"][f * COLS:(f + 1) * COLS]))
    elif sys.argv[1] == "--demo":
        ventana(demo, None)
    else:
        ventana(leer_serial, sys.argv[1])
