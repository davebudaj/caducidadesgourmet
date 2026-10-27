import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class JerarquiaUbicacionHelper {
  // Normaliza texto quitando acentos, diéresis, comas, puntos y apóstrofes para búsquedas rápidas
  static String normalizarTextoBusqueda(String input) {
    if (input.isEmpty) return '';
    String s = input.toLowerCase();
    const mapaAcentos = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
      'ñ': 'n',
    };
    mapaAcentos.forEach((k, v) {
      s = s.replaceAll(k, v);
    });
    // Quitar comas, puntos, comillas simples/dobles y exceso de espacios
    s = s.replaceAll(RegExp(r"[^a-z0-9\s]"), " ");
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static bool coincideBusquedaInteligente(String consultaRaw, List<String?> camposDocumento) {
    String q = normalizarTextoBusqueda(consultaRaw);
    if (q.isEmpty) return true;
    List<String> palabras = q.split(' ').where((w) => w.isNotEmpty).toList();
    String acumulado = camposDocumento
        .map((c) => normalizarTextoBusqueda(c ?? ''))
        .join(' ');
    for (String p in palabras) {
      if (!acumulado.contains(p)) return false;
    }
    return true;
  }

  // Actualiza el SKU, UPC/EAN y Descripción de un artículo en TODAS las instancias de la tienda y crea el puente en maestro_productos
  static Future<int> actualizarArticuloEnTodasLasInstancias({
    required String idTiendaGlobal,
    required String codigoAnterior,
    required String nuevoSku,
    String? nuevoEan,
    String? nuevaDescripcion,
    Map<String, dynamic>? datosMaestros,
    String? usuarioActual,
  }) async {
    var db = FirebaseFirestore.instance;
    var refTienda = db.collection('tiendas').doc(idTiendaGlobal);

    String skuFinal = nuevoSku.trim();
    String codigoViejo = codigoAnterior.trim();
    // Si antes tenía un código largo tipo UPC/EAN (11-14 dígitos) y ahora ponen el SKU de SAP, conservamos ese UPC como EAN
    String eanFinal = (nuevoEan != null && nuevoEan.trim().isNotEmpty)
        ? nuevoEan.trim()
        : (datosMaestros?['ean']?.toString().trim() ?? (codigoViejo.length >= 11 && codigoViejo != skuFinal ? codigoViejo : ''));

    String descFinal = (nuevaDescripcion != null && nuevaDescripcion.trim().isNotEmpty && nuevaDescripcion.trim() != 'Artículo Nuevo')
        ? nuevaDescripcion.trim().toUpperCase()
        : (datosMaestros?['descripcion']?.toString().trim() ?? 'SIN NOMBRE');

    WriteBatch batch = db.batch();
    int ops = 0;
    int lotesActualizados = 0;

    Future<void> checkBatch() async {
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    }

    // 1. Guardar puente en maestro_productos para que futuros escaneos de este UPC o SKU hagan match automático
    Map<String, dynamic> fichaMaestra = {
      'sku': skuFinal,
      'ean': eanFinal,
      'descripcion': descFinal,
      'idProveedor': datosMaestros?['idProveedor'] ?? 'ND',
      'nombreProveedor': datosMaestros?['nombreProveedor'] ?? 'POR ASIGNAR',
      'idCategoria': datosMaestros?['idCategoria'] ?? 'ND',
      'nombreGpoArticulos': datosMaestros?['nombreGpoArticulos'] ?? 'SIN GRUPO',
      'precioVenta': datosMaestros?['precioVenta'] ?? '0',
      'oh': datosMaestros?['oh'] ?? '0',
    };

    if (skuFinal.isNotEmpty) {
      batch.set(db.collection('maestro_productos').doc(skuFinal), fichaMaestra, SetOptions(merge: true));
      await checkBatch();
    }
    if (eanFinal.isNotEmpty && eanFinal != '0') {
      batch.set(db.collection('maestro_productos').doc(eanFinal), fichaMaestra, SetOptions(merge: true));
      await checkBatch();
    }
    if (codigoViejo.isNotEmpty && codigoViejo != skuFinal && codigoViejo != eanFinal) {
      batch.set(db.collection('maestro_productos').doc(codigoViejo), fichaMaestra, SetOptions(merge: true));
      await checkBatch();
    }

    // 2. Actualizar TODAS las instancias en inventario_activo
    var invSnap = await refTienda.collection('inventario_activo').get();
    for (var doc in invSnap.docs) {
      var d = doc.data();
      String sDoc = (d['sku'] ?? '').toString().trim();
      String eDoc = (d['ean'] ?? '').toString().trim();

      if (sDoc == codigoViejo || (codigoViejo.isNotEmpty && eDoc == codigoViejo) || sDoc == skuFinal) {
        Map<String, dynamic> cambios = {
          'sku': skuFinal,
          'descripcion': descFinal,
          'misionArticuloNuevo': FieldValue.delete(),
        };
        if (eanFinal.isNotEmpty) cambios['ean'] = eanFinal;
        if (datosMaestros != null) {
          cambios['idProveedor'] = fichaMaestra['idProveedor'];
          cambios['nombreProveedor'] = fichaMaestra['nombreProveedor'];
          cambios['idCategoria'] = fichaMaestra['idCategoria'];
          cambios['nombreGpoArticulos'] = fichaMaestra['nombreGpoArticulos'];
          cambios['precioVenta'] = fichaMaestra['precioVenta'];
          cambios['oh'] = fichaMaestra['oh'];
        }
        batch.update(doc.reference, cambios);
        lotesActualizados++;
        await checkBatch();
      }
    }

    // 3. Actualizar todas las misiones en misiones_auditoria y autocompletar las de "VALIDAR ARTÍCULO NUEVO" de este código
    var misSnap = await refTienda.collection('misiones_auditoria').get();
    for (var mDoc in misSnap.docs) {
      var m = mDoc.data();
      String mSku = (m['sku'] ?? '').toString().trim();
      String mEan = (m['ean'] ?? '').toString().trim();
      if (mSku == codigoViejo || (codigoViejo.isNotEmpty && mEan == codigoViejo) || mSku == skuFinal) {
        String msg = (m['mensaje'] ?? '').toString();
        bool esMisionArticuloNuevo = m['esArticuloNuevo'] == true || msg.contains('ARTÍCULO NUEVO');

        Map<String, dynamic> cambiosMision = {
          'sku': skuFinal,
          'descripcion': descFinal,
          if (eanFinal.isNotEmpty) 'ean': eanFinal,
          if (datosMaestros != null) 'nombreProveedor': fichaMaestra['nombreProveedor'],
          if (datosMaestros != null) 'nombreGpoArticulos': fichaMaestra['nombreGpoArticulos'],
        };

        if (esMisionArticuloNuevo && m['estado'] == 'pendiente') {
          cambiosMision['estado'] = 'completada';
          cambiosMision['completadaPor'] = usuarioActual ?? 'Validado en Sistema';
          cambiosMision['accionRealizada'] = 'validacion_sku';
        }

        batch.update(mDoc.reference, cambiosMision);
        await checkBatch();
      }
    }

    // 4. Actualizar registros en historial_tratamientos
    var histSnap = await refTienda.collection('historial_tratamientos').get();
    for (var hDoc in histSnap.docs) {
      var h = hDoc.data();
      String hSku = (h['sku'] ?? '').toString().trim();
      if (hSku == codigoViejo) {
        batch.update(hDoc.reference, {
          'sku': skuFinal,
          'descripcion': descFinal,
        });
        await checkBatch();
      }
    }

    if (ops > 0) await batch.commit();
    return lotesActualizados;
  }

  static List<String> generarVariantesCodigo(String codigoRaw) {
    String limpio = codigoRaw.trim();
    if (limpio.isEmpty) return [];
    String sinCeros = limpio.replaceFirst(RegExp(r'^0+'), '');
    return <String>{
      limpio,
      if (sinCeros.isNotEmpty) sinCeros,
      if (sinCeros.isNotEmpty) '0$sinCeros',
      if (sinCeros.isNotEmpty) '00$sinCeros',
    }.toList();
  }

  static Future<Map<String, dynamic>?> buscarProductoMaestro(String codigoRaw) async {
    List<String> candidatos = generarVariantesCodigo(codigoRaw);
    if (candidatos.isEmpty) return null;
    var col = FirebaseFirestore.instance.collection('maestro_productos');

    // 1. Buscar por ID directo de documento (EAN o SKU)
    for (String cand in candidatos) {
      var doc = await col.doc(cand).get();
      if (doc.exists && doc.data() != null) return doc.data();
    }
    // 2. Respaldo por campo interno 'ean'
    for (String cand in candidatos) {
      var qEan = await col.where('ean', isEqualTo: cand).limit(1).get();
      if (qEan.docs.isNotEmpty) return qEan.docs.first.data();
    }
    // 3. Respaldo por campo interno 'sku'
    for (String cand in candidatos) {
      var qSku = await col.where('sku', isEqualTo: cand).limit(1).get();
      if (qSku.docs.isNotEmpty) return qSku.docs.first.data();
    }
    return null;
  }

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

  static int _prioridadArea(String area) {
    String u = area.toUpperCase().trim();
    if (u == 'PISO') return 0;
    if (u == 'BODEGA') return 1;
    if (u == 'DISPLAY') return 2;
    return 3;
  }

  static int _compararTextoNatural(String a, String b) {
    RegExp reg = RegExp(r'(\d+)|(\D+)');
    var mA = reg.allMatches(a.toUpperCase()).map((m) => m.group(0)!).toList();
    var mB = reg.allMatches(b.toUpperCase()).map((m) => m.group(0)!).toList();
    int len = mA.length < mB.length ? mA.length : mB.length;
    for (int i = 0; i < len; i++) {
      int? nA = int.tryParse(mA[i]);
      int? nB = int.tryParse(mB[i]);
      int cmp = (nA != null && nB != null) ? nA.compareTo(nB) : mA[i].compareTo(mB[i]);
      if (cmp != 0) return cmp;
    }
    return mA.length.compareTo(mB.length);
  }

  static int compararRutasJerarquicas(String rutaA, String rutaB) {
    List<String> nivA = descomponerRuta(rutaA);
    List<String> nivB = descomponerRuta(rutaB);

    int prioA = _prioridadArea(nivA.first);
    int prioB = _prioridadArea(nivB.first);
    if (prioA != prioB) return prioA.compareTo(prioB);

    int minLen = nivA.length < nivB.length ? nivA.length : nivB.length;
    for (int i = 0; i < minLen; i++) {
      int cmp = _compararTextoNatural(nivA[i], nivB[i]);
      if (cmp != 0) return cmp;
    }
    return nivA.length.compareTo(nivB.length);
  }

  static List<String> ordenarRutasPorJerarquia(Iterable<String> rutas) {
    List<String> lista = rutas.toList();
    lista.sort(compararRutasJerarquicas);
    return lista;
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
  String? _ultimaRutaEmitida;

  @override
  void initState() {
    super.initState();
    _ultimaRutaEmitida = widget.rutaSeleccionada;
    _sincronizarDesdeRuta(widget.rutaSeleccionada);
  }

  @override
  void didUpdateWidget(covariant SelectorJerarquicoUbicacion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rutaSeleccionada != _ultimaRutaEmitida) {
      _ultimaRutaEmitida = widget.rutaSeleccionada;
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

      if (nivelActual == 0) {
        // Garantizar que siempre inicie con PISO, BODEGA, DISPLAY
        opcionesSet.addAll(['PISO', 'BODEGA', 'DISPLAY']);
      }

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

      List<String> opciones = opcionesSet.toList();
      if (nivelActual == 0) {
        opciones.sort((a, b) {
          int pA = JerarquiaUbicacionHelper._prioridadArea(a);
          int pB = JerarquiaUbicacionHelper._prioridadArea(b);
          if (pA != pB) return pA.compareTo(pB);
          return a.compareTo(b);
        });
      } else {
        opciones.sort(JerarquiaUbicacionHelper._compararTextoNatural);
      }

      if (opciones.isEmpty) break;

      String? valorActual = _nivelesElegidos.length > nivelActual ? _nivelesElegidos[nivelActual] : null;
      if (valorActual != null && !opciones.contains(valorActual)) {
        valorActual = null;
      }

      String etiquetaNivel = nivelActual == 0
          ? '1. Área (PISO / BODEGA / DISPLAY)'
          : (nivelActual == 1 ? '2. Mueble / Ubicación' : '${nivelActual + 1}. Nivel / Cara / Entrepaño');

      int idxCopia = nivelActual;

      selectores.add(
        Padding(
          padding: EdgeInsets.only(top: idxCopia == 0 ? 0 : 6),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: idxCopia == 0 ? Colors.white10 : Colors.blueAccent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: valorActual != null ? Colors.greenAccent.withOpacity(0.8) : Colors.white24,
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
                          : (widget.permitirSeleccionParcial ? 'Todo ${_nivelesElegidos[idxCopia - 1]}' : 'Selecciona $etiquetaNivel...'),
                      style: TextStyle(
                        fontSize: 12,
                        color: idxCopia == 0 ? Colors.white54 : Colors.amberAccent,
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
                              maxLines: 2,
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
                  String? resuelta = _resolverValorParaCallback();
                  _ultimaRutaEmitida = resuelta;
                  widget.onRutaCambiada(resuelta);
                },
              ),
            ),
          ),
        ),
      );

      if (valorActual == null) break;
      // Si el nivel actual ya no tiene sub-ramas en las rutas existentes, terminamos de desplegar
      bool tieneSubRamas = rutasDescompuestas.any((nr) {
        if (nr.length <= nivelActual + 1) return false;
        for (int i = 0; i <= nivelActual; i++) {
          if (nr[i].toUpperCase() != _nivelesElegidos[i].toUpperCase()) return false;
        }
        return true;
      });
      if (!tieneSubRamas) break;
      nivelActual++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: selectores,
    );
  }
}
