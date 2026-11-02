import os
from datetime import datetime

archivo_salida = "Codigo_Completo_GourmetGuard.txt"
archivos_raiz = ["pubspec.yaml", "firebase.json"]
carpeta_codigo = "lib"

with open(archivo_salida, "w", encoding="utf-8") as out:

    out.write("====================================================================\n")
    out.write("RESPALDO DE CÓDIGO FUENTE - GOURMET GUARD\n")
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
            out.write("====================================================================\n\n")

            with open(cfg, "r", encoding="utf-8") as f:
                out.write(f.read())
                out.write("\n\n")

    # 3. Incluir el contenido de todos los archivos Dart
    for root, dirs, files in os.walk(carpeta_codigo):
        dirs.sort()
        files.sort()

        for archivo in files:
            if archivo.endswith(".dart"):
                ruta = os.path.join(root, archivo)

                out.write("====================================================================\n")
                out.write(f"ARCHIVO: {ruta}\n")
                out.write("====================================================================\n\n")

                try:
                    with open(ruta, "r", encoding="utf-8") as f:
                        out.write(f.read())
                        out.write("\n\n")
                except Exception as e:
                    out.write(f"ERROR AL LEER ARCHIVO: {e}\n\n")

print(f"Respaldo generado correctamente: {archivo_salida}")
