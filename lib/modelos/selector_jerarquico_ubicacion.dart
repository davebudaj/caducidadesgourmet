import 'package:flutter/material.dart';

class JerarquiaUbicacionHelper {
  // Convierte cualquier ubicación ("PISO MESA DE CAFES > NIVEL1" o "PISO > MESA > NIVEL1") en lista de niveles
  static List<String> descomponerRuta(String raw) {
    String limpia = raw.trim();
    if (limpia.isEmpty) return ['SIN UBICACIÓN'];

    List<String> partes = limpia.split('>').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (partes.isEmpty) return [limpia];

    String primero = partes.first.toUpperCase();
    for (String pref in ['PISO', 'BODEGA', 'DISPLAY']) {
      if (primero.startsWith('$pref ') && primero.length > pref.length + 1) {
        String resto = partes.first.substring(pref.length + 1).trim();
        return [pref, resto, ...partes.sublist(1)];
      }
    }
    return partes;
  }

  static String formatearRutaVisual(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'ND';
    return descomponerRuta(raw).join(' > ');
  }

  static bool coincideConPrefijoJerarquico(String rutaReal, List<String> nivelesSeleccionados) {
    if (nivelesSeleccionados.isEmpty) return true;
    List<String> nivelesRuta = descomponerRuta(rutaReal);
    if (nivelesRuta.length < nivelesSeleccionados.length) return false;
    for (int i = 0; i < nivelesSeleccionados.length; i++) {
      if (nivelesRuta[i].toUpperCase() != nivelesSeleccionados[i].toUpperCase()) return false;
    }
    return true;
  }
}

class SelectorJerarquicoUbicacion extends StatefulWidget {
  final List<String> todasLasRutas;
  final String? rutaSeleccionada;
  final bool permitirSeleccionParcial;
  final String textoRaizVacio;
  final Map<String, int>? conteoLotesPorRuta;
  final ValueChanged<String?> onRutaCambiada;

  const SelectorJerarquicoUbicacion({
    super.key,
    required this.todasLasRutas,
    required this.rutaSeleccionada,
    required this.onRutaCambiada,
    this.permitirSeleccionParcial = false,
    this.textoRaizVacio = 'Todas las ubicaciones',
    this.conteoLotesPorRuta,
  });

  @override
  State<SelectorJerarquicoUbicacion> createState() => _SelectorJerarquicoUbicacionState();
}

class _SelectorJerarquicoUbicacionState extends State<SelectorJerarquicoUbicacion> {
  List<String> _nivelesElegidos = [];

  @override
  void initState() {
    super.initState();
    _sincronizarDesdeRuta(widget.rutaSeleccionada);
  }

  @override
  void didUpdateWidget(covariant SelectorJerarquicoUbicacion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rutaSeleccionada != widget.rutaSeleccionada) {
      _sincronizarDesdeRuta(widget.rutaSeleccionada);
    }
  }

  void _sincronizarDesdeRuta(String? ruta) {
    if (ruta == null || ruta.isEmpty || ruta == 'Sin anclar') {
      _nivelesElegidos = [];
    } else {
      _nivelesElegidos = JerarquiaUbicacionHelper.descomponerRuta(ruta);
    }
  }

  int _contarLotesBajoPrefijo(List<String> prefijo) {
    if (widget.conteoLotesPorRuta == null) return 0;
    int total = 0;
    for (var entry in widget.conteoLotesPorRuta!.entries) {
      if (JerarquiaUbicacionHelper.coincideConPrefijoJerarquico(entry.key, prefijo)) {
        total += entry.value;
      }
    }
    return total;
  }

  String? _resolverValorParaCallback() {
    if (_nivelesElegidos.isEmpty) return null;

    // Buscar si existe una ruta exacta en la BD con estos niveles
    for (String r in widget.todasLasRutas) {
      List<String> nr = JerarquiaUbicacionHelper.descomponerRuta(r);
      if (nr.length == _nivelesElegidos.length) {
        bool igual = true;
        for (int i = 0; i < nr.length; i++) {
          if (nr[i].toUpperCase() != _nivelesElegidos[i].toUpperCase()) {
            igual = false;
            break;
          }
        }
        if (igual) return r;
      }
    }

    if (widget.permitirSeleccionParcial) {
      return _nivelesElegidos.join(' > ');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    List<List<String>> rutasDescompuestas = widget.todasLasRutas
        .map((r) => JerarquiaUbicacionHelper.descomponerRuta(r))
        .toList();

    List<Widget> selectores = [];
    int nivelActual = 0;

    while (true) {
      List<String> prefijo = _nivelesElegidos.take(nivelActual).toList();
      Set<String> opcionesSet = {};

      for (var nr in rutasDescompuestas) {
        if (nr.length > nivelActual) {
          bool coincide = true;
          for (int i = 0; i < nivelActual; i++) {
            if (nr[i].toUpperCase() != prefijo[i].toUpperCase()) {
              coincide = false;
              break;
            }
          }
          if (coincide) {
            opcionesSet.add(nr[nivelActual]);
          }
        }
      }

      List<String> opciones = opcionesSet.toList()..sort();
      if (opciones.isEmpty) break;

      String? valorActual = _nivelesElegidos.length > nivelActual ? _nivelesElegidos[nivelActual] : null;
      if (valorActual != null && !opciones.contains(valorActual)) {
        valorActual = null;
      }

      String etiquetaNivel = nivelActual == 0
          ? '1. Área (Piso / Bodega / Display)'
          : (nivelActual == 1 ? '2. Mueble / Ubicación' : '${nivelActual + 1}. Nivel / Cara / Entrepaño');

      int idxCopia = nivelActual;

      selectores.add(
        Padding(
          padding: EdgeInsets.only(top: idxCopia == 0 ? 0 : 8),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: idxCopia == 0 ? Colors.blueAccent.withOpacity(0.12) : Colors.white10,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: valorActual != null ? Colors.amberAccent.withOpacity(0.7) : Colors.white24,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                dropdownColor: const Color(0xFF2C2C2C),
                value: valorActual,
                hint: Text(etiquetaNivel, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      idxCopia == 0
                          ? widget.textoRaizVacio
                          : (widget.permitirSeleccionParcial ? 'Todos los sub-niveles de ${_nivelesElegidos[idxCopia - 1]}' : 'Selecciona $etiquetaNivel...'),
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.permitirSeleccionParcial ? Colors.greenAccent : Colors.white54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ...opciones.map((op) {
                    List<String> prefOp = [...prefijo, op];
                    int cantLotes = _contarLotesBajoPrefijo(prefOp);
                    return DropdownMenuItem<String?>(
                      value: op,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              idxCopia == 0 ? '📍 $op' : '↳ $op',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.conteoLotesPorRuta != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: cantLotes > 0 ? Colors.greenAccent.withOpacity(0.2) : Colors.white10,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$cantLotes lotes',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cantLotes > 0 ? Colors.greenAccent : Colors.white38,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
                onChanged: (val) {
                  setState(() {
                    _nivelesElegidos = _nivelesElegidos.take(idxCopia).toList();
                    if (val != null) {
                      _nivelesElegidos.add(val);
                    }
                  });
                  widget.onRutaCambiada(_resolverValorParaCallback());
                },
              ),
            ),
          ),
        ),
      );

      if (valorActual == null) break;
      nivelActual++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: selectores,
    );
  }
}
