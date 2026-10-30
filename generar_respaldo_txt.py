import os
from datetime import datetime

archivo_salida = "Codigo_Completo_GourmetGuard.txt"
archivos_raiz = ["pubspec.yaml", "firebase.json"]
carpeta_codigo = "lib"

with open(archivo_salida, "w", encoding="utf-8") as out:
out.write("====================================================================\n")
out.write(f"RESPALDO DE CÓDIGO FUENTE - GOURMET GUARD\n")
out.write(f"Generado: {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}\n")
out.write("====================================================================\n\n")

# 1. Escribir el mapa visual de carpetas y archivos
out.write("### ESTRUCTURA DE CARPETAS Y ARCHIVOS ###\n")
for root, dirs, files in os.walk(carpeta_codigo):
dirs.sort()
files.sort()
nivel = root.replace(carpeta_codigo, "").count(os.sep)
indent = "  " * nivel
out.write(f"{indent}📁 {os.path.basename(root)}/\n")
sub_indent = "  " * (nivel + 1)
for f in files:
if f.endswith(".dart"):
out.write(f"{sub_indent}📄 {f}\n")
out.write("\n\n")

# 2. Incluir archivos de configuración clave de la raíz
for cfg in archivos_raiz:
if os.path.exists(cfg):
out.write("====================================================================\n")
out.write(f"ARCHIVO: {cfg}\n")
out.write("====================================================================\n")
with open(cfg, "r", encoding="utf-8", errors="replace") as f:
out.write(f.read() + "\n\n")

# 3. Recorrer todas las carpetas dentro de lib/ y guardar cada archivo .dart
total_archivos = 0
for root, dirs, files in os.walk(carpeta_codigo):
dirs.sort()
files.sort()
for file in files:
if file.endswith(".dart"):
ruta_completa = os.path.join(root, file)
out.write("====================================================================\n")
out.write(f"ARCHIVO: {ruta_completa}\n")
out.write("====================================================================\n")
with open(ruta_completa, "r", encoding="utf-8", errors="replace") as f:
out.write(f.read() + "\n\n")
total_archivos += 1

print(f"✅ Listo: {total_archivos} archivos .dart empaquetados en '{archivo_salida}'")
