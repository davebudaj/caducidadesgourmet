import os

file_path = 'lib/pantallas/sabana.dart'
with open(file_path, 'r') as f:
    content = f.read()

target = "child: Text(d['cantidad'].toString() + ' pzas • Ubicación: ' + d['ubicacion'].toString(), style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),"
replacement = """child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d['cantidad'].toString() + ' pzas • Ubicación: ' + d['ubicacion'].toString(), style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
                                    if (d['comentarioCorporativo'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text('INSTRUCCIÓN: ${d['comentarioCorporativo']}', style: const TextStyle(color: Colors.pinkAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                      )
                                  ],
                                ),"""

if "Instrucción Corp" not in content and "INSTRUCCIÓN:" not in content:
    content = content.replace(target, replacement)
    with open(file_path, 'w') as f:
        f.write(content)
        print("✅ sabana.dart modificado con éxito para mostrar instrucciones corporativas.")
else:
    print("✅ sabana.dart ya estaba configurado.")
