import 'package:flutter/material.dart';

class EtiquetaMes {
  static Map<int, Map<String, dynamic>> colores = {
    1: {'nombre': 'AZUL', 'color': Colors.blue},
    2: {'nombre': 'ROSA', 'color': Colors.pinkAccent},
    3: {'nombre': 'AMARILLO', 'color': Colors.yellow},
    4: {'nombre': 'VERDE', 'color': Colors.green},
    5: {'nombre': 'NARANJA', 'color': Colors.orange},
    6: {'nombre': 'MORADO', 'color': Colors.purple},
    7: {'nombre': 'CELESTE', 'color': Colors.cyan},
    8: {'nombre': 'ROJO', 'color': Colors.red},
    9: {'nombre': 'CAFÉ', 'color': Colors.brown},
    10: {'nombre': 'GRIS', 'color': Colors.grey},
    11: {'nombre': 'LIMA', 'color': Colors.lightGreen},
    12: {'nombre': 'BLANCO', 'color': Colors.white},
  };
  static Map<String, dynamic> obtener(DateTime? fecha) {
    if (fecha == null) return {'nombre': 'NINGUNO', 'color': Colors.transparent};
    return colores[fecha.month] ?? {'nombre': 'BLANCO', 'color': Colors.white};
  }
}
