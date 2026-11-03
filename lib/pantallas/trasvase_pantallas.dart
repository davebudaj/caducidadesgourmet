import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../modelos/selector_jerarquico_ubicacion.dart';

class PantallaTrasvaseMasivo extends StatefulWidget {
  final String idTiendaGlobal;
  final String usuarioRegistra;
  final String? ubicacionInicial;
  final String? skuFiltroInicial;

  const PantallaTrasvaseMasivo({
    super.key,
    required this.idTiendaGlobal,
    required this.usuarioRegistra,
    this.ubicacionInicial,
    this.skuFiltroInicial,
  });

  @override
  State<PantallaTrasvaseMasivo> createState() => _PantallaTrasvaseMasivoState();
}

class _PantallaTrasvaseMasivoState extends State<PantallaTrasvaseMasivo> {
  static const String kUbicacionTransito = 'EN TRÁNSITO';

  final TextEditingController _skuCtrl = TextEditingController();
  final FocusNode _skuFocusNode = FocusNode();

  String _filtroTextoSku = '';
  String? _ubicacionOrigenFiltro;
  final Map<String, int> _cantidadesElegidas = {};
  bool _procesandoEnvio = false;

  late Stream<QuerySnapshot> _invStream;
  late Stream<QuerySnapshot> _ubiStream;

  CollectionReference<Map<String, dynamic>> get _refInv =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('inventario_activo');

  CollectionReference<Map<String, dynamic>> get _refUbi =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('ubicaciones');

  @override
  void initState() {
    super.initState();
    JerarquiaUbicacionHelper.precargarCacheUpc();
    _ubicacionOrigenFiltro = widget.ubicacionInicial;
    if (widget.skuFiltroInicial != null && widget.skuFiltroInicial!.trim().isNotEmpty) {
      _skuCtrl.text = widget.skuFiltroInicial!.trim();
      _filtroTextoSku = widget.skuFiltroInicial!.trim().toLowerCase();
    }
    _invStream = _refInv.orderBy('fechaCaducidad').snapshots();
    _ubiStream = _refUbi.orderBy('nombre').snapshots();

    // Al entrar a Trasvase Masivo, enfocar automáticamente el cuadro de SKU / UPC
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _skuFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _skuCtrl.dispose();
    _skuFocusNode.dispose();
    super.dispose();
  }

  Future<void> _procesarCodigoEscaneado(String rawCode) async {
    String limpio = rawCode.trim();
    if (limpio.isEmpty) {
      setState(() => _filtroTextoSku = '');
      return;
    }

    if (limpio.startsWith('LOC:')) {
      String ubi = limpio.substring(4).trim();
      setState(() {
        _ubicacionOrigenFiltro = ubi;
        _skuCtrl.clear();
        _filtroTextoSku = '';
      });
      _skuFocusNode.requestFocus();
      return;
    }

    var maestro = await JerarquiaUbicacionHelper.buscarProductoMaestro(limpio);
    String skuTraducido = (maestro != null && maestro['sku'] != null && maestro['sku'].toString().trim().isNotEmpty)
        ? maestro['sku'].toString().trim()
        : limpio;

    if (!mounted) return;
    setState(() {
      _skuCtrl.text = skuTraducido;
      _filtroTextoSku = skuTraducido.toLowerCase();
    });

    // Seleccionar todo el texto para que el siguiente disparo de láser lo reemplace o permita seguir escaneando
    _skuCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _skuCtrl.text.length);
  }

  void _limpiarParaSiguienteSku() {
    setState(() {
      _skuCtrl.clear();
      _filtroTextoSku = '';
      _cantidadesElegidas.clear();
    });
    _skuFocusNode.requestFocus();
  }

  Future<int?> _pedirCantidadManual(int actual, int maximo, String desc) async {
    final TextEditingController ctrl = TextEditingController(text: actual > 0 ? '$actual' : '');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF262626),
        title: Text(desc, style: const TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold), maxLines: 2),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Piezas a subir al carrito (Máx: $maximo)',
            filled: true,
            fillColor: Colors.black45,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
            onPressed: () {
              int v = int.tryParse(ctrl.text.trim()) ?? 0;
              Navigator.pop(ctx, v.clamp(0, maximo));
            },
            child: const Text('ACEPTAR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _enviarSeleccionadosAlCarrito(List<QueryDocumentSnapshot> docsVisibles) async {
    if (_procesandoEnvio) return;

    List<QueryDocumentSnapshot> lotesAMover = [];
    int totalPiezas = 0;

    for (var doc in docsVisibles) {
      int cant = _cantidadesElegidas[doc.id] ?? 0;
      if (cant > 0) {
        lotesAMover.add(doc);
        totalPiezas += cant;
      }
    }

    if (lotesAMover.isEmpty) return;

    setState(() => _procesandoEnvio = true);

    try {
      var batch = FirebaseFirestore.instance.batch();

      for (var doc in lotesAMover) {
        var d = doc.data() as Map<String, dynamic>;
        int cantDisp = (d['cantidad'] ?? 0) as int;
        int cantMover = (_cantidadesElegidas[doc.id] ?? 0).clamp(1, cantDisp);

        if (cantDisp <= cantMover) {
          batch.delete(doc.reference);
        } else {
          batch.update(doc.reference, {'cantidad': cantDisp - cantMover});
        }

        var nuevoEnCarrito = Map<String, dynamic>.from(d);
        nuevoEnCarrito['cantidad'] = cantMover;
        nuevoEnCarrito['ubicacion'] = kUbicacionTransito;
        nuevoEnCarrito['ubicacionOrigen'] = d['ubicacion'] ?? 'TIENDA';
        nuevoEnCarrito['fechaTransito'] = FieldValue.serverTimestamp();
        nuevoEnCarrito['usuarioTransito'] = widget.usuarioRegistra;

        batch.set(_refInv.doc(), nuevoEnCarrito);
      }

      await batch.commit();

      if (!mounted) return;

      // Auto-limpiar el SKU/UPC y las cantidades después de enviar al carrito temporal,
      // y devolver el foco al cuadro de escaneo para escanear el siguiente SKU de inmediato
      setState(() {
        _procesandoEnvio = false;
        _cantidadesElegidas.clear();
        if (_filtroTextoSku.isNotEmpty) {
          _skuCtrl.clear();
          _filtroTextoSku = '';
        }
      });

      _skuFocusNode.requestFocus();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🛒 $totalPiezas pza(s) enviadas al Carrito Temporal. Listo para escanear el siguiente SKU.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _procesandoEnvio = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar al carrito: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trasvase Masivo (Extraer)', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: _refInv.where('ubicacion', isEqualTo: kUbicacionTransito).snapshots(),
            builder: (context, snap) {
              int lotesEnCarrito = snap.hasData ? snap.data!.docs.length : 0;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: lotesEnCarrito > 0 ? Colors.deepOrangeAccent : Colors.white12,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.shopping_cart_checkout, size: 16),
                  label: Text('Carrito ($lotesEnCarrito)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PantallaCarritoTemporal(
                          idTiendaGlobal: widget.idTiendaGlobal,
                          usuarioRegistra: widget.usuarioRegistra,
                        ),
                      ),
                    );
                    if (mounted) _skuFocusNode.requestFocus();
                  },
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _invStream,
        builder: (context, invSnap) {
          if (!invSnap.hasData) return const Center(child: CircularProgressIndicator(color: Colors.amber));

          var docsActivos = invSnap.data!.docs.where((doc) {
            var d = doc.data() as Map<String, dynamic>;
            String u = (d['ubicacion'] ?? '').toString();
            int c = (d['cantidad'] ?? 0) as int;
            return u != kUbicacionTransito && c > 0;
          }).toList();

          Map<String, int> conteoPorRuta = {};
          for (var doc in docsActivos) {
            String u = ((doc.data() as Map<String, dynamic>)['ubicacion'] ?? 'ND').toString();
            conteoPorRuta[u] = (conteoPorRuta[u] ?? 0) + 1;
          }

          List<String> prefijoOrigen = _ubicacionOrigenFiltro != null
              ? JerarquiaUbicacionHelper.descomponerRuta(_ubicacionOrigenFiltro!)
              : [];

          var docsFiltrados = docsActivos.where((doc) {
            var d = doc.data() as Map<String, dynamic>;
            String u = (d['ubicacion'] ?? 'ND').toString();
            bool okUbi = JerarquiaUbicacionHelper.coincideConPrefijoJerarquico(u, prefijoOrigen);
            bool okSku = _filtroTextoSku.isEmpty ||
                JerarquiaUbicacionHelper.coincideBusquedaInteligente(
                  _filtroTextoSku,
                  [
                    d['sku']?.toString(),
                    d['ean']?.toString(),
                    JerarquiaUbicacionHelper.obtenerUpcVisual(d),
                    d['codigoOriginalCapturado']?.toString(),
                    d['descripcion']?.toString(),
                  ],
                );
            return okUbi && okSku;
          }).toList();

          int totalLotesSeleccionados = 0;
          int totalPiezasSeleccionadas = 0;
          for (var doc in docsFiltrados) {
            int c = _cantidadesElegidas[doc.id] ?? 0;
            if (c > 0) {
              totalLotesSeleccionados++;
              totalPiezasSeleccionadas += c;
            }
          }

          return Column(
            children: [
              Container(
                color: Colors.black,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // CUADRO DE INGRESO ACTIVO POR DEFECTO PARA ESCANEAR SKU / UPC
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: TextField(
                              controller: _skuCtrl,
                              focusNode: _skuFocusNode,
                              autofocus: true,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                labelText: 'Escanear SKU o UPC (Activo para escáner)...',
                                labelStyle: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                prefixIcon: const Icon(Icons.qr_code_scanner, color: Colors.cyanAccent, size: 20),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.camera_alt, color: Colors.amber, size: 18),
                                  tooltip: 'Escanear con cámara',
                                  onPressed: () async {
                                    String? code = await Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const _EscanerCamaraAuxiliar()),
                                    );
                                    if (code != null && code.trim().isNotEmpty) {
                                      await _procesarCodigoEscaneado(code);
                                    }
                                  },
                                ),
                                filled: true,
                                fillColor: Colors.blueAccent.withOpacity(0.12),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.5),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Colors.amber, width: 2),
                                ),
                              ),
                              onChanged: (val) {
                                setState(() => _filtroTextoSku = val.trim().toLowerCase());
                              },
                              onSubmitted: (val) => _procesarCodigoEscaneado(val),
                            ),
                          ),
                        ),
                        if (_filtroTextoSku.isNotEmpty || _cantidadesElegidas.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          SizedBox(
                            height: 44,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.amberAccent,
                                side: const BorderSide(color: Colors.amberAccent),
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                              label: const Text('Limpiar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: _limpiarParaSiguienteSku,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<QuerySnapshot>(
                      stream: _ubiStream,
                      builder: (context, ubiSnap) {
                        List<String> rutas = ubiSnap.hasData
                            ? ubiSnap.data!.docs.map((d) => d['nombre'].toString()).where((n) => n != kUbicacionTransito).toList()
                            : conteoPorRuta.keys.toList();
                        rutas = JerarquiaUbicacionHelper.ordenarRutasPorJerarquia(rutas);
                        return Row(
                          children: [
                            Expanded(
                              child: SelectorJerarquicoUbicacion(
                                todasLasRutas: rutas,
                                rutaSeleccionada: _ubicacionOrigenFiltro,
                                permitirSeleccionParcial: true,
                                textoRaizVacio: '📍 Filtrar Mueble Origen (Opcional: Todos)',
                                conteoLotesPorRuta: conteoPorRuta,
                                onRutaCambiada: (val) => setState(() => _ubicacionOrigenFiltro = val),
                              ),
                            ),
                            if (_ubicacionOrigenFiltro != null)
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                                tooltip: 'Quitar filtro de ubicación',
                                onPressed: () {
                                  setState(() => _ubicacionOrigenFiltro = null);
                                  _skuFocusNode.requestFocus();
                                },
                              ),
                          ],
                        );
                      },
                    ),
                    if (docsFiltrados.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Mostrando ${docsFiltrados.length} lote(s) disponible(s)',
                              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            Row(
                              children: [
                                TextButton(
                                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                  onPressed: () {
                                    setState(() {
                                      for (var doc in docsFiltrados) {
                                        int maxD = ((doc.data() as Map<String, dynamic>)['cantidad'] ?? 0) as int;
                                        _cantidadesElegidas[doc.id] = maxD;
                                      }
                                    });
                                  },
                                  child: const Text('Seleccionar Todo', style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 6),
                                TextButton(
                                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                  onPressed: () => setState(() => _cantidadesElegidas.clear()),
                                  child: const Text('Desmarcar', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: docsFiltrados.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.qr_code_scanner, size: 46, color: Colors.white24),
                              const SizedBox(height: 10),
                              Text(
                                _filtroTextoSku.isNotEmpty
                                    ? 'No se encontraron lotes activos para "$_filtroTextoSku".\nEscanea el siguiente SKU / UPC.'
                                    : 'Escanea un SKU / UPC arriba o selecciona un mueble para extraer mercancía al Carrito Temporal.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 85, top: 6),
                        itemCount: docsFiltrados.length,
                        itemBuilder: (context, i) {
                          var doc = docsFiltrados[i];
                          var d = doc.data() as Map<String, dynamic>;
                          String docId = doc.id;
                          int maxDisp = (d['cantidad'] ?? 0) as int;
                          int cantElegida = _cantidadesElegidas[docId] ?? 0;
                          bool activo = cantElegida > 0;

                          DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
                          int dias = cad.difference(DateTime.now()).inDays;
                          String fCad = "${cad.day.toString().padLeft(2, '0')}/${cad.month.toString().padLeft(2, '0')}/${cad.year}";
                          String upc = JerarquiaUbicacionHelper.obtenerUpcVisual(d);

                          return Card(
                            elevation: 0,
                            color: activo ? Colors.blueAccent.withOpacity(0.20) : Colors.white10,
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: activo ? Colors.cyanAccent : Colors.white24, width: activo ? 1.8 : 1),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Checkbox(
                                        visualDensity: VisualDensity.compact,
                                        activeColor: Colors.cyanAccent,
                                        checkColor: Colors.black,
                                        value: activo,
                                        onChanged: (v) {
                                          setState(() {
                                            _cantidadesElegidas[docId] = (v == true) ? maxDisp : 0;
                                          });
                                        },
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              d['descripcion'] ?? d['sku'],
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                            ),
                                            const SizedBox(height: 2),
                                            Text('SKU: ${d['sku'] ?? 'ND'}', style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                            Text('UPC: $upc', style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 3),
                                            Text(
                                              '📍 Origen: ${JerarquiaUbicacionHelper.formatearRutaVisual(d['ubicacion']?.toString())}',
                                              style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                            Text(
                                              'Caducidad: $fCad ($dias d)  •  Disponible: $maxDisp pzas',
                                              style: TextStyle(color: dias <= 15 ? Colors.redAccent : Colors.white70, fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      InkWell(
                                        onTap: () => setState(() => _cantidadesElegidas[docId] = maxDisp),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: cantElegida == maxDisp ? Colors.amber : Colors.amber.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.amber),
                                          ),
                                          child: Text(
                                            'TODO ($maxDisp)',
                                            style: TextStyle(
                                              color: cantElegida == maxDisp ? Colors.black : Colors.amber,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 24),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: cantElegida > 0
                                            ? () => setState(() => _cantidadesElegidas[docId] = cantElegida - 1)
                                            : null,
                                      ),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () async {
                                          int? manual = await _pedirCantidadManual(cantElegida, maxDisp, (d['descripcion'] ?? '').toString());
                                          if (manual != null) {
                                            setState(() => _cantidadesElegidas[docId] = manual);
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.white24),
                                          ),
                                          child: Text(
                                            '$cantElegida',
                                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent, size: 24),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: cantElegida < maxDisp
                                            ? () => setState(() => _cantidadesElegidas[docId] = cantElegida + 1)
                                            : null,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: StreamBuilder<QuerySnapshot>(
        stream: _invStream,
        builder: (context, invSnap) {
          if (!invSnap.hasData) return const SizedBox.shrink();
          var docsActivos = invSnap.data!.docs.where((doc) {
            var d = doc.data() as Map<String, dynamic>;
            String u = (d['ubicacion'] ?? '').toString();
            int c = (d['cantidad'] ?? 0) as int;
            return u != kUbicacionTransito && c > 0;
          }).toList();

          List<String> prefijoOrigen = _ubicacionOrigenFiltro != null
              ? JerarquiaUbicacionHelper.descomponerRuta(_ubicacionOrigenFiltro!)
              : [];

          var docsVisibles = docsActivos.where((doc) {
            var d = doc.data() as Map<String, dynamic>;
            String u = (d['ubicacion'] ?? 'ND').toString();
            bool okUbi = JerarquiaUbicacionHelper.coincideConPrefijoJerarquico(u, prefijoOrigen);
            bool okSku = _filtroTextoSku.isEmpty ||
                JerarquiaUbicacionHelper.coincideBusquedaInteligente(
                  _filtroTextoSku,
                  [
                    d['sku']?.toString(),
                    d['ean']?.toString(),
                    JerarquiaUbicacionHelper.obtenerUpcVisual(d),
                    d['codigoOriginalCapturado']?.toString(),
                    d['descripcion']?.toString(),
                  ],
                );
            return okUbi && okSku;
          }).toList();

          int lotesSel = 0;
          int pzasSel = 0;
          for (var doc in docsVisibles) {
            int c = _cantidadesElegidas[doc.id] ?? 0;
            if (c > 0) {
              lotesSel++;
              pzasSel += c;
            }
          }

          if (pzasSel <= 0) return const SizedBox.shrink();

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrangeAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _procesandoEnvio
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.shopping_cart_checkout, size: 22),
                  label: Text(
                    _procesandoEnvio
                        ? 'ENVIANDO AL CARRITO...'
                        : 'MANDAR AL CARRITO TEMPORAL ($lotesSel lote${lotesSel == 1 ? '' : 's'} • $pzasSel pzas)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: _procesandoEnvio ? null : () => _enviarSeleccionadosAlCarrito(docsVisibles),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class PantallaCarritoTemporal extends StatefulWidget {
  final String idTiendaGlobal;
  final String usuarioRegistra;
  final String? destinoPreseleccionado;

  const PantallaCarritoTemporal({
    super.key,
    required this.idTiendaGlobal,
    required this.usuarioRegistra,
    this.destinoPreseleccionado,
  });

  @override
  State<PantallaCarritoTemporal> createState() => _PantallaCarritoTemporalState();
}

class _PantallaCarritoTemporalState extends State<PantallaCarritoTemporal> {
  static const String kUbicacionTransito = 'EN TRÁNSITO';

  String? _ubicacionDestino;
  final Set<String> _seleccionadosParaAcomodar = {};
  bool _procesando = false;

  CollectionReference<Map<String, dynamic>> get _refInv =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('inventario_activo');

  CollectionReference<Map<String, dynamic>> get _refUbi =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('ubicaciones');

  @override
  void initState() {
    super.initState();
    JerarquiaUbicacionHelper.precargarCacheUpc();
    if (widget.destinoPreseleccionado != null && widget.destinoPreseleccionado != 'Sin anclar') {
      _ubicacionDestino = widget.destinoPreseleccionado;
    }
  }

  Future<void> _devolverLoteAOrigen(QueryDocumentSnapshot docCarrito) async {
    var d = docCarrito.data() as Map<String, dynamic>;
    String origen = (d['ubicacionOrigen'] ?? 'PISO').toString();
    String sku = (d['sku'] ?? '').toString();
    int cant = (d['cantidad'] ?? 0) as int;
    DateTime fCad = (d['fechaCaducidad'] as Timestamp).toDate();

    var snapOrig = await _refInv.where('sku', isEqualTo: sku).where('ubicacion', isEqualTo: origen).get();
    QueryDocumentSnapshot? loteIgual;
    for (var doc in snapOrig.docs) {
      DateTime f2 = (doc.data()['fechaCaducidad'] as Timestamp).toDate();
      if (f2.year == fCad.year && f2.month == fCad.month && f2.day == fCad.day) {
        loteIgual = doc;
        break;
      }
    }

    var batch = FirebaseFirestore.instance.batch();
    if (loteIgual != null) {
      int cantOrig = ((loteIgual.data() as Map<String, dynamic>)['cantidad'] ?? 0) as int;
      batch.update(loteIgual.reference, {'cantidad': cantOrig + cant});
    } else {
      var restaurado = Map<String, dynamic>.from(d);
      restaurado['ubicacion'] = origen;
      restaurado.remove('ubicacionOrigen');
      restaurado.remove('fechaTransito');
      restaurado.remove('usuarioTransito');
      batch.set(_refInv.doc(), restaurado);
    }
    batch.delete(docCarrito.reference);
    await batch.commit();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('↩️ Lote devuelto a $origen'), backgroundColor: Colors.blueAccent),
      );
    }
  }

  Future<void> _depositarEnUbicacionDestino(List<QueryDocumentSnapshot> docsEnCarrito) async {
    if (_ubicacionDestino == null || _procesando) return;

    List<QueryDocumentSnapshot> objetivos = _seleccionadosParaAcomodar.isEmpty
        ? docsEnCarrito
        : docsEnCarrito.where((d) => _seleccionadosParaAcomodar.contains(d.id)).toList();

    if (objetivos.isEmpty) return;

    setState(() => _procesando = true);

    try {
      var existentesSnap = await _refInv.where('ubicacion', isEqualTo: _ubicacionDestino).get();
      Map<String, Map<String, dynamic>> existentesMapa = {};
      for (var doc in existentesSnap.docs) {
        var data = doc.data();
        DateTime f = (data['fechaCaducidad'] as Timestamp).toDate();
        String key = "${data['sku']}_${f.year}-${f.month}-${f.day}";
        existentesMapa[key] = {
          'ref': doc.reference,
          'cantidad': (data['cantidad'] ?? 0) as int,
        };
      }

      var batch = FirebaseFirestore.instance.batch();
      int pzasMovidas = 0;

      for (var docC in objetivos) {
        var d = docC.data() as Map<String, dynamic>;
        int cant = (d['cantidad'] ?? 0) as int;
        pzasMovidas += cant;
        DateTime f = (d['fechaCaducidad'] as Timestamp).toDate();
        String key = "${d['sku']}_${f.year}-${f.month}-${f.day}";

        if (existentesMapa.containsKey(key)) {
          int nuevaCant = (existentesMapa[key]!['cantidad'] as int) + cant;
          existentesMapa[key]!['cantidad'] = nuevaCant;
          batch.update(existentesMapa[key]!['ref'] as DocumentReference, {'cantidad': nuevaCant});
        } else {
          var nuevoRef = _refInv.doc();
          var nuevoMapa = Map<String, dynamic>.from(d);
          nuevoMapa['ubicacion'] = _ubicacionDestino;
          nuevoMapa.remove('ubicacionOrigen');
          nuevoMapa.remove('fechaTransito');
          nuevoMapa.remove('usuarioTransito');
          batch.set(nuevoRef, nuevoMapa);
          existentesMapa[key] = {'ref': nuevoRef, 'cantidad': cant};
        }
        batch.delete(docC.reference);
      }

      await batch.commit();

      if (mounted) {
        setState(() {
          _procesando = false;
          _seleccionadosParaAcomodar.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $pzasMovidas pza(s) acomodadas en ${JerarquiaUbicacionHelper.formatearRutaVisual(_ubicacionDestino)}'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _procesando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al depositar carrito: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Carrito Temporal (En Tránsito)', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _refInv.where('ubicacion', isEqualTo: kUbicacionTransito).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Colors.amber));
          var docs = snap.data!.docs;

          return Column(
            children: [
              Container(
                color: Colors.black,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '🎯 Ubicación Destino para vaciar carrito:',
                          style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.cyanAccent,
                            side: const BorderSide(color: Colors.cyanAccent),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.qr_code_scanner, size: 15),
                          label: const Text('Escanear QR Destino', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          onPressed: () async {
                            String? qr = await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const _EscanerCamaraAuxiliar()),
                            );
                            if (qr != null && qr.trim().isNotEmpty) {
                              String limpio = qr.trim();
                              if (limpio.startsWith('LOC:')) limpio = limpio.substring(4).trim();
                              setState(() => _ubicacionDestino = limpio);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    StreamBuilder<QuerySnapshot>(
                      stream: _refUbi.orderBy('nombre').snapshots(),
                      builder: (context, ubiSnap) {
                        if (!ubiSnap.hasData) return const LinearProgressIndicator(color: Colors.amber);
                        List<String> todas = ubiSnap.data!.docs
                            .map((d) => d['nombre'].toString())
                            .where((n) => n != kUbicacionTransito)
                            .toList();
                        List<String> hojas = todas.where((u) => !todas.any((otra) => otra.startsWith('$u > '))).toList();
                        hojas = JerarquiaUbicacionHelper.ordenarRutasPorJerarquia(hojas);
                        if (_ubicacionDestino != null && !hojas.contains(_ubicacionDestino)) {
                          hojas.add(_ubicacionDestino!);
                        }
                        return SelectorJerarquicoUbicacion(
                          todasLasRutas: hojas,
                          rutaSeleccionada: _ubicacionDestino,
                          permitirSeleccionParcial: false,
                          textoRaizVacio: '1. Selecciona Área Destino (PISO / BODEGA / DISPLAY)...',
                          onRutaCambiada: (val) => setState(() => _ubicacionDestino = val),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: docs.isEmpty
                    ? const Center(
                        child: Text('El Carrito Temporal está vacío.', style: TextStyle(color: Colors.greenAccent, fontSize: 15, fontWeight: FontWeight.bold)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 85, top: 6),
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          var doc = docs[i];
                          var d = doc.data() as Map<String, dynamic>;
                          bool sel = _seleccionadosParaAcomodar.contains(doc.id);
                          DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
                          String fCad = "${cad.day.toString().padLeft(2, '0')}/${cad.month.toString().padLeft(2, '0')}/${cad.year}";

                          return Card(
                            elevation: 0,
                            color: sel ? Colors.green.withOpacity(0.18) : Colors.white10,
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            child: ListTile(
                              leading: Checkbox(
                                activeColor: Colors.greenAccent,
                                checkColor: Colors.black,
                                value: sel,
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      _seleccionadosParaAcomodar.add(doc.id);
                                    } else {
                                      _seleccionadosParaAcomodar.remove(doc.id);
                                    }
                                  });
                                },
                              ),
                              title: Text(d['descripcion'] ?? d['sku'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('SKU: ${d['sku']} • Cad: $fCad\nUPC: ${JerarquiaUbicacionHelper.obtenerUpcVisual(d)}', style: const TextStyle(color: Colors.greenAccent, fontSize: 11)),
                                  Text('📦 ${d['cantidad']} pzas • Origen: ${d['ubicacionOrigen'] ?? 'ND'}', style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.undo, color: Colors.orangeAccent),
                                tooltip: 'Devolver a su ubicación origen',
                                onPressed: () => _devolverLoteAOrigen(doc),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (docs.isNotEmpty)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                    child: SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.archive_rounded, size: 20),
                        label: Text(
                          _ubicacionDestino == null
                              ? 'SELECCIONA UBICACIÓN DESTINO ARRIBA'
                              : (_seleccionadosParaAcomodar.isEmpty
                                  ? 'VACIAR TODO EL CARRITO AQUÍ (${docs.length} lotes)'
                                  : 'DEPOSITAR SELECCIONADOS AQUÍ (${_seleccionadosParaAcomodar.length})'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        onPressed: (_ubicacionDestino == null || _procesando) ? null : () => _depositarEnUbicacionDestino(docs),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EscanerCamaraAuxiliar extends StatefulWidget {
  const _EscanerCamaraAuxiliar();
  @override
  State<_EscanerCamaraAuxiliar> createState() => _EscanerCamaraAuxiliarState();
}

class _EscanerCamaraAuxiliarState extends State<_EscanerCamaraAuxiliar> {
  bool _detectado = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear Código', style: TextStyle(color: Colors.amber, fontSize: 15))),
      body: MobileScanner(
        onDetect: (capture) {
          if (_detectado) return;
          final barcode = capture.barcodes.first;
          if (barcode.rawValue != null && barcode.rawValue!.trim().isNotEmpty) {
            setState(() => _detectado = true);
            Navigator.pop(context, barcode.rawValue!.trim());
          }
        },
      ),
    );
  }
}
