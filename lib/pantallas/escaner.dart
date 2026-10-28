import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:universal_html/html.dart' as html;

import 'ingreso.dart';
import 'login.dart';
import 'trasvase_pantallas.dart';
import '../modelos/selector_jerarquico_ubicacion.dart';

class PantallaEscaner extends StatefulWidget {
  final bool estaActiva;
  final String usuarioRegistra;
  final String idTiendaGlobal;

  const PantallaEscaner({
    super.key,
    this.estaActiva = true,
    required this.usuarioRegistra,
    required this.idTiendaGlobal,
  });

  @override
  State<PantallaEscaner> createState() => _PantallaEscanerState();
}

class _PantallaEscanerState extends State<PantallaEscaner> with SingleTickerProviderStateMixin {
  final TextEditingController _skuController = TextEditingController();
  final FocusNode _skuManualFocus = FocusNode();
  String? _ubicacionDestino;
  bool _modoTrasvase = false;
  bool _camaraActiva = true;

  late AnimationController _laserController;
  late Animation<double> _laserAnimation;
  bool _bloquearEscaneo = false;
  bool _enSubPantalla = false;

  static const String kUbicacionTransito = 'EN TRÁNSITO';

  CollectionReference<Map<String, dynamic>> get _refInv =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('inventario_activo');

  CollectionReference<Map<String, dynamic>> get _refUbi =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('ubicaciones');

  @override
  void initState() {
    super.initState();
    try {
      String? camPref = html.window.localStorage['gg_camara_activa'];
      if (camPref != null) _camaraActiva = camPref == 'true';
    } catch (_) {}
    _laserController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    if (_camaraActiva) _laserController.repeat(reverse: true);
    _laserAnimation = Tween<double>(begin: 10.0, end: 180.0).animate(_laserController);
  }

  @override
  void dispose() {
    _laserController.dispose();
    _skuController.dispose();
    _skuManualFocus.dispose();
    super.dispose();
  }

  Future<String> _obtenerSkuOficial(String codigo) async {
    var data = await JerarquiaUbicacionHelper.buscarProductoMaestro(codigo);
    if (data != null && data['sku'] != null && data['sku'].toString().trim().isNotEmpty) {
      return data['sku'].toString().trim();
    }
    return codigo.trim();
  }

  Future<void> _irATrasvaseMasivo({String? ubicacionInicial, String? skuFiltroInicial}) async {
    setState(() => _enSubPantalla = true);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PantallaTrasvaseMasivo(
          idTiendaGlobal: widget.idTiendaGlobal,
          usuarioRegistra: widget.usuarioRegistra,
          ubicacionInicial: ubicacionInicial,
          skuFiltroInicial: skuFiltroInicial,
        ),
      ),
    );
    if (mounted) setState(() => _enSubPantalla = false);
  }

  Future<void> _irACarritoTemporal({String? destinoPreseleccionado}) async {
    setState(() => _enSubPantalla = true);
    String? nuevoDestino = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => PantallaCarritoTemporal(
          idTiendaGlobal: widget.idTiendaGlobal,
          usuarioRegistra: widget.usuarioRegistra,
          destinoPreseleccionado: destinoPreseleccionado ?? _ubicacionDestino,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _enSubPantalla = false;
        if (nuevoDestino != null) _ubicacionDestino = nuevoDestino;
      });
    }
  }

  // Si se escanea un QR de un mueble padre que tiene sub-niveles (Macro-QR), permite elegir el nivel/entrepaño exacto
  Future<String?> _resolverMacroQR(String muebleEscaneado, List<String> todasUbis, {bool permitirExtraerTodo = true}) async {
    List<String> subRamas = todasUbis.where((u) => u.startsWith('$muebleEscaneado > ')).toList();
    List<String> hojas = subRamas.where((u) => !todasUbis.any((otra) => otra.startsWith('$u > '))).toList();
    hojas = JerarquiaUbicacionHelper.ordenarRutasPorJerarquia(hojas);

    if (hojas.isEmpty) return muebleEscaneado;

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.amber, width: 2)),
        title: Text('📍 ${JerarquiaUbicacionHelper.formatearRutaVisual(muebleEscaneado)}', style: const TextStyle(color: Colors.amber, fontSize: 15, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Selecciona el nivel / entrepaño exacto:', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: hojas.length,
                  itemBuilder: (c, idx) {
                    String h = hojas[idx];
                    String etiquetaHija = h.substring(muebleEscaneado.length + 3).replaceAll(' > ', ' ➔ ');
                    return Card(
                      color: Colors.white10,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.subdirectory_arrow_right, color: Colors.greenAccent, size: 18),
                        title: Text(etiquetaHija, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 13, color: Colors.amber),
                        onTap: () => Navigator.pop(ctx, h),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
          ),
          if (permitirExtraerTodo)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
              icon: const Icon(Icons.outbox, size: 16),
              label: const Text('EXTRAER DE TODO EL MUEBLE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: () => Navigator.pop(ctx, '__EXTRAER_PADRE__'),
            ),
        ],
      ),
    );
  }

  Future<int?> _pedirCantidadManualTrasvase(int actual, int maximo, String descripcion) async {
    TextEditingController ctrl = TextEditingController(text: actual > 0 ? actual.toString() : '');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: Text(descripcion, style: const TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold), maxLines: 2),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Piezas a trasvasar (Máx: $maximo)',
            filled: true,
            fillColor: Colors.black45,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
            onPressed: () {
              int val = int.tryParse(ctrl.text.trim()) ?? 0;
              Navigator.pop(ctx, val.clamp(0, maximo));
            },
            child: const Text('ACEPTAR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // MODAL DE TRASVASE RÁPIDO DIRECTO (UBICACIÓN A UBICACIÓN SIN PASAR POR EL CARRITO)
  Future<void> _mostrarDialogoTrasvaseRapido(String skuOficial) async {
    setState(() => _enSubPantalla = true);
    try {
      var results = await Future.wait([
        _refInv.where('sku', isEqualTo: skuOficial).get(),
        _refUbi.orderBy('nombre').get(),
      ]);

      var invSnap = results[0];
      var ubiSnap = results[1];

      var lotesDisponibles = invSnap.docs.where((d) {
        String u = (d.data()['ubicacion'] ?? '').toString();
        int cant = (d.data()['cantidad'] ?? 0) as int;
        return u != kUbicacionTransito && cant > 0;
      }).toList();

      if (lotesDisponibles.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ No hay lotes activos del SKU $skuOficial disponibles para trasvasar.'),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        }
        return;
      }

      // Ordenar lotes por FIFO (más próximo a caducar primero)
      lotesDisponibles.sort((a, b) {
        Timestamp tA = a.data()['fechaCaducidad'] ?? Timestamp.now();
        Timestamp tB = b.data()['fechaCaducidad'] ?? Timestamp.now();
        return tA.compareTo(tB);
      });

      List<String> todasUbis = ubiSnap.docs.map((d) => d['nombre'].toString()).where((n) => n != kUbicacionTransito).toList();
      List<String> ubicacionesHoja = todasUbis.where((u) => !todasUbis.any((otra) => otra.startsWith('$u > '))).toList();
      ubicacionesHoja = JerarquiaUbicacionHelper.ordenarRutasPorJerarquia(ubicacionesHoja);

      String? destinoModal = (_ubicacionDestino != null && _ubicacionDestino != 'Sin anclar') ? _ubicacionDestino : null;
      if (destinoModal != null && !ubicacionesHoja.contains(destinoModal)) {
        ubicacionesHoja.add(destinoModal);
      }

      String descProducto = (lotesDisponibles.first.data()['descripcion'] ?? skuOficial).toString();
      Map<String, int> cantidadesSeleccionadas = {};

      // Si solo existe 1 lote en otra ubicación, pre-seleccionamos 1 pieza para agilizar aún más
      if (lotesDisponibles.length == 1) {
        String uUnica = (lotesDisponibles.first.data()['ubicacion'] ?? '').toString();
        if (uUnica != destinoModal) {
          cantidadesSeleccionadas[lotesDisponibles.first.id] = 1;
        }
      }

      bool ejecutando = false;

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) {
            int totalPiezas = 0;
            int totalLotes = 0;
            for (var doc in lotesDisponibles) {
              String uOrig = (doc.data()['ubicacion'] ?? '').toString();
              if (destinoModal != null && uOrig == destinoModal) continue;
              int c = cantidadesSeleccionadas[doc.id] ?? 0;
              if (c > 0) {
                totalPiezas += c;
                totalLotes++;
              }
            }

            Future<void> escanearQRDestinoDentroDeModal() async {
              String? qrRaw = await Navigator.push<String>(
                context,
                MaterialPageRoute(builder: (_) => const PantallaEscanerQRUbicacion()),
              );
              if (qrRaw == null || qrRaw.trim().isEmpty) return;
              String limpio = qrRaw.trim();
              String rutaCandidata = limpio.startsWith('LOC:') ? limpio.substring(4).trim() : limpio;

              String? hojaResuelta = await _resolverMacroQR(rutaCandidata, todasUbis, permitirExtraerTodo: false);
              if (hojaResuelta != null && hojaResuelta != '__EXTRAER_PADRE__') {
                setModalState(() {
                  if (!ubicacionesHoja.contains(hojaResuelta)) {
                    ubicacionesHoja.add(hojaResuelta);
                  }
                  destinoModal = hojaResuelta;
                  // Si algún lote estaba en la misma ubicación recién elegida, poner su cantidad en 0
                  for (var doc in lotesDisponibles) {
                    if ((doc.data()['ubicacion'] ?? '') == destinoModal) {
                      cantidadesSeleccionadas[doc.id] = 0;
                    }
                  }
                });
              }
            }

            Future<void> confirmarTrasvaseDirecto() async {
              if (destinoModal == null || totalPiezas <= 0 || ejecutando) return;
              setModalState(() => ejecutando = true);

              try {
                var destinoSnap = await _refInv
                    .where('sku', isEqualTo: skuOficial)
                    .where('ubicacion', isEqualTo: destinoModal)
                    .get();

                // Mapa por fecha (YYYY-MM-DD) para fusionar limpiamente si llegan lotes con la misma caducidad al destino
                Map<String, Map<String, dynamic>> lotesEnDestinoPorFecha = {};
                for (var d in destinoSnap.docs) {
                  DateTime f = (d.data()['fechaCaducidad'] as Timestamp).toDate();
                  String keyFecha = "${f.year}-${f.month}-${f.day}";
                  lotesEnDestinoPorFecha[keyFecha] = {
                    'ref': d.reference,
                    'cantidad': (d.data()['cantidad'] ?? 0) as int,
                  };
                }

                var misionesSnap = await FirebaseFirestore.instance
                    .collection('tiendas')
                    .doc(widget.idTiendaGlobal)
                    .collection('misiones_auditoria')
                    .where('estado', isEqualTo: 'pendiente')
                    .where('sku', isEqualTo: skuOficial)
                    .get();

                var batch = FirebaseFirestore.instance.batch();

                for (var docOrigen in lotesDisponibles) {
                  int cantMover = cantidadesSeleccionadas[docOrigen.id] ?? 0;
                  if (cantMover <= 0) continue;

                  var dataOrig = docOrigen.data();
                  String ubiOrig = (dataOrig['ubicacion'] ?? '').toString();
                  if (ubiOrig == destinoModal) continue;

                  int cantActual = (dataOrig['cantidad'] ?? 0) as int;
                  if (cantMover > cantActual) cantMover = cantActual;

                  DateTime fCad = (dataOrig['fechaCaducidad'] as Timestamp).toDate();
                  String keyFecha = "${fCad.year}-${fCad.month}-${fCad.day}";

                  // 1. Restar o eliminar del lote origen
                  if (cantActual <= cantMover) {
                    batch.delete(docOrigen.reference);
                  } else {
                    batch.update(docOrigen.reference, {'cantidad': cantActual - cantMover});
                  }

                  // 2. Sumar o crear directamente en la ubicación destino
                  if (lotesEnDestinoPorFecha.containsKey(keyFecha)) {
                    int nuevaCantDestino = (lotesEnDestinoPorFecha[keyFecha]!['cantidad'] as int) + cantMover;
                    lotesEnDestinoPorFecha[keyFecha]!['cantidad'] = nuevaCantDestino;
                    batch.update(
                      lotesEnDestinoPorFecha[keyFecha]!['ref'] as DocumentReference,
                      {'cantidad': nuevaCantDestino},
                    );
                  } else {
                    var nuevoRef = _refInv.doc();
                    var nuevoMapa = Map<String, dynamic>.from(dataOrig);
                    nuevoMapa['cantidad'] = cantMover;
                    nuevoMapa['ubicacion'] = destinoModal;
                    nuevoMapa['fechaCaptura'] = FieldValue.serverTimestamp();
                    nuevoMapa['capturista'] = widget.usuarioRegistra;
                    batch.set(nuevoRef, nuevoMapa);

                    lotesEnDestinoPorFecha[keyFecha] = {
                      'ref': nuevoRef,
                      'cantidad': cantMover,
                    };
                  }

                  // 3. Conciliar misiones activas de este lote
                  for (var mDoc in misionesSnap.docs) {
                    var mData = mDoc.data();
                    if ((mData['ubicacion'] ?? '') != ubiOrig) continue;
                    String msg = (mData['mensaje'] ?? '').toString();

                    if (msg.contains('90 DÍAS') && !destinoModal!.toUpperCase().contains('BODEGA')) {
                      batch.update(mDoc.reference, {
                        'estado': 'completada',
                        'completadaPor': '${widget.usuarioRegistra} (Trasvase Rápido)',
                        'accionRealizada': 'trasvase_rapido',
                      });
                    } else if (cantActual <= cantMover) {
                      batch.update(mDoc.reference, {'ubicacion': destinoModal});
                    }
                  }
                }

                await batch.commit();

                if (mounted) {
                  setState(() => _ubicacionDestino = destinoModal);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '⚡ Trasvase Rápido: $totalPiezas pza(s) movidas directo a ${JerarquiaUbicacionHelper.formatearRutaVisual(destinoModal)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: Colors.green.shade700,
                    ),
                  );
                }
              } catch (e) {
                setModalState(() => ejecutando = false);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error en trasvase rápido: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.blueAccent, width: 2)),
              titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.bolt, color: Colors.amber, size: 22),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Trasvase Rápido Directo',
                          style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(descProducto, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text('SKU: $skuOficial', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(color: Colors.white24, height: 12),
                      // PASO 1: UBICACIÓN DESTINO (PRE-ANCLADA O PARA ELEGIR/ESCANEAR AL MOMENTO)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            destinoModal != null ? '🎯 1. Ubicación Destino (Anclada):' : '🎯 1. Selecciona o Escanea el Destino:',
                            style: TextStyle(
                              color: destinoModal != null ? Colors.greenAccent : Colors.amberAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
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
                            onPressed: escanearQRDestinoDentroDeModal,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectorJerarquicoUbicacion(
                        todasLasRutas: ubicacionesHoja,
                        rutaSeleccionada: destinoModal,
                        permitirSeleccionParcial: false,
                        textoRaizVacio: '📍 Elige Área Destino (PISO, BODEGA o DISPLAY)...',
                        onRutaCambiada: (val) {
                          setModalState(() {
                            destinoModal = val;
                            for (var doc in lotesDisponibles) {
                              if ((doc.data()['ubicacion'] ?? '') == destinoModal) {
                                cantidadesSeleccionadas[doc.id] = 0;
                              }
                            }
                          });
                        },
                      ),
                      if (destinoModal != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.greenAccent.withOpacity(0.6)),
                            ),
                            child: Text(
                              '✅ Se dejará en: ${JerarquiaUbicacionHelper.formatearRutaVisual(destinoModal)}',
                              style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      const Divider(color: Colors.white24, height: 18),
                      // PASO 2: SELECCIONAR DE QUÉ LOTE Y QUÉ CANTIDAD EXTRAER
                      const Text(
                        '📦 2. Selecciona de qué ubicación/lote y qué cantidad deseas mover:',
                        style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      ...lotesDisponibles.map((doc) {
                        var d = doc.data();
                        String docId = doc.id;
                        String ubiLote = (d['ubicacion'] ?? 'SIN UBICACIÓN').toString();
                        int maxDisp = (d['cantidad'] ?? 0) as int;
                        DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
                        int dias = cad.difference(DateTime.now()).inDays;
                        String fCad = "${cad.day.toString().padLeft(2, '0')}/${cad.month.toString().padLeft(2, '0')}/${cad.year}";

                        bool esMismoDestino = (destinoModal != null && ubiLote == destinoModal);
                        int cantElegida = esMismoDestino ? 0 : (cantidadesSeleccionadas[docId] ?? 0);
                        bool activo = cantElegida > 0;

                        return Card(
                          color: esMismoDestino
                              ? Colors.white.withOpacity(0.04)
                              : (activo ? Colors.blueAccent.withOpacity(0.22) : Colors.white10),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: esMismoDestino
                                  ? Colors.white12
                                  : (activo ? Colors.blueAccent : Colors.white24),
                              width: activo ? 1.8 : 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (!esMismoDestino)
                                      Checkbox(
                                        visualDensity: VisualDensity.compact,
                                        value: activo,
                                        activeColor: Colors.blueAccent,
                                        onChanged: (v) {
                                          setModalState(() {
                                            cantidadesSeleccionadas[docId] = (v == true) ? maxDisp : 0;
                                          });
                                        },
                                      ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '📍 ${JerarquiaUbicacionHelper.formatearRutaVisual(ubiLote)}',
                                            style: TextStyle(
                                              color: esMismoDestino ? Colors.white54 : Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '📅 Cad: $fCad ($dias d)  •  📦 Disponible: $maxDisp pzas',
                                            style: TextStyle(
                                              color: dias <= 15 ? Colors.redAccent : Colors.amberAccent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (esMismoDestino)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4, left: 4),
                                    child: Text(
                                      'ℹ️ Este lote ya se encuentra en la ubicación destino seleccionada.',
                                      style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontStyle: FontStyle.italic),
                                    ),
                                  )
                                else
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        InkWell(
                                          onTap: () => setModalState(() => cantidadesSeleccionadas[docId] = maxDisp),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
                                          icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 26),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: cantElegida > 0
                                              ? () => setModalState(() => cantidadesSeleccionadas[docId] = cantElegida - 1)
                                              : null,
                                        ),
                                        const SizedBox(width: 8),
                                        InkWell(
                                          onTap: () async {
                                            int? manual = await _pedirCantidadManualTrasvase(cantElegida, maxDisp, descProducto);
                                            if (manual != null) {
                                              setModalState(() => cantidadesSeleccionadas[docId] = manual);
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
                                              cantElegida.toString(),
                                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent, size: 26),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: cantElegida < maxDisp
                                              ? () => setModalState(() => cantidadesSeleccionadas[docId] = cantElegida + 1)
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: ejecutando ? null : () => Navigator.pop(ctx),
                  child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: ejecutando
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.bolt, size: 18),
                  label: Text(
                    ejecutando
                        ? 'MOVIENDO...'
                        : (destinoModal == null
                            ? 'ELIGE DESTINO ARRIBA'
                            : 'MOVER A DESTINO ($totalLotes lote${totalLotes == 1 ? '' : 's'} • $totalPiezas pzas)'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  onPressed: (destinoModal == null || totalPiezas <= 0 || ejecutando) ? null : confirmarTrasvaseDirecto,
                ),
              ],
            );
          },
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _enSubPantalla = false);
        if (!_camaraActiva) _skuManualFocus.requestFocus();
      }
    }
  }

  void _procesarEscaneo(String codigo) async {
    String codigoLimpio = codigo.trim();

    if (codigoLimpio.startsWith('LOC:')) {
      String muebleEscaneado = codigoLimpio.substring(4).trim();
      var ubiSnap = await _refUbi.orderBy('nombre').get();
      List<String> todasUbis = ubiSnap.docs.map((d) => d['nombre'].toString()).toList();

      String? resuelto = await _resolverMacroQR(muebleEscaneado, todasUbis, permitirExtraerTodo: true);
      if (resuelto == null) {
        if (mounted) setState(() => _bloquearEscaneo = false);
        return;
      } else if (resuelto == '__EXTRAER_PADRE__') {
        await _irATrasvaseMasivo(ubicacionInicial: muebleEscaneado);
        if (mounted) setState(() => _bloquearEscaneo = false);
        return;
      } else {
        muebleEscaneado = resuelto;
      }

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.amber, width: 2)),
          title: Text('📍 ${JerarquiaUbicacionHelper.formatearRutaVisual(muebleEscaneado)}', style: const TextStyle(color: Colors.amber, fontSize: 15, fontWeight: FontWeight.bold)),
          content: Text(
            _modoTrasvase
                ? 'Modo Trasvase Rápido activo: ¿Deseas anclar esta ubicación como destino para escanear los productos que dejarás aquí?'
                : '¿Qué acción deseas realizar con esta ubicación?',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
              ),
              icon: const Icon(Icons.push_pin, size: 18),
              label: Text(
                _modoTrasvase ? 'ANCLAR DESTINO (TRASVASE RÁPIDO)' : 'ANCLAR DESTINO AQUÍ',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _ubicacionDestino = muebleEscaneado;
                  _skuController.clear();
                });
                if (!_camaraActiva) _skuManualFocus.requestFocus();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _modoTrasvase
                          ? '⚡ Destino anclado: ${JerarquiaUbicacionHelper.formatearRutaVisual(_ubicacionDestino)}. Ahora escanea el SKU/UPC a traer aquí.'
                          : '📍 Ubicación anclada: ${JerarquiaUbicacionHelper.formatearRutaVisual(_ubicacionDestino)}',
                    ),
                    backgroundColor: Colors.green.shade700,
                  ),
                );
              },
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.deepOrangeAccent, side: const BorderSide(color: Colors.deepOrangeAccent)),
              icon: const Icon(Icons.local_shipping, size: 16),
              label: const Text('VACIAR CARRITO AQUÍ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.pop(context);
                setState(() => _ubicacionDestino = muebleEscaneado);
                _irACarritoTemporal(destinoPreseleccionado: muebleEscaneado);
              },
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.blueAccent, side: const BorderSide(color: Colors.blueAccent)),
              icon: const Icon(Icons.outbox, size: 16),
              label: const Text('IR A TRASVASE MASIVO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.pop(context);
                _irATrasvaseMasivo(ubicacionInicial: muebleEscaneado);
              },
            ),
          ],
        ),
      );
    } else if (codigoLimpio.isNotEmpty) {
      if (_modoTrasvase) {
        String skuOficial = await _obtenerSkuOficial(codigoLimpio);
        await _mostrarDialogoTrasvaseRapido(skuOficial);
      } else {
        setState(() => _enSubPantalla = true);
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PantallaRegistro(
              skuEscaneado: codigoLimpio,
              ubicacionPredefinida: _ubicacionDestino,
              usuarioRegistra: widget.usuarioRegistra,
              idTiendaGlobal: widget.idTiendaGlobal,
            ),
          ),
        );
        if (mounted) setState(() => _enSubPantalla = false);
      }
      _skuController.clear();
    }

    if (mounted) setState(() => _bloquearEscaneo = false);
  }

  @override
  Widget build(BuildContext context) {
    bool mostrarCamara = widget.estaActiva && !_enSubPantalla && _camaraActiva;

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 118,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              padding: const EdgeInsets.only(left: 6),
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
              tooltip: 'Cerrar sesión',
              onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const PantallaLogin())),
            ),
            const SizedBox(width: 4),
            const Text("CÁM", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white70)),
            Transform.scale(
              scale: 0.78,
              child: Switch(
                value: _camaraActiva,
                activeColor: Colors.greenAccent,
                onChanged: (v) {
                  setState(() => _camaraActiva = v);
                  try {
                    html.window.localStorage['gg_camara_activa'] = v.toString();
                  } catch (_) {}
                  if (v) {
                    _laserController.repeat(reverse: true);
                  } else {
                    _laserController.stop();
                    _skuManualFocus.requestFocus();
                  }
                },
              ),
            ),
          ],
        ),
        titleSpacing: 0,
        centerTitle: true,
        title: const Text('Operaciones de Piso', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 14)),
        actions: [
          const Center(child: Text("TRASVASE", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white70))),
          Transform.scale(
            scale: 0.78,
            child: Switch(
              value: _modoTrasvase,
              onChanged: (v) {
                setState(() => _modoTrasvase = v);
                if (!_camaraActiva) _skuManualFocus.requestFocus();
              },
              activeColor: Colors.blueAccent,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                icon: const Icon(Icons.inventory_2, size: 20),
                label: const Text('INGRESO DE MERCANCÍA (MANIFIESTO)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.8)),
                onPressed: () async {
                  setState(() => _enSubPantalla = true);
                  await Navigator.push(context, MaterialPageRoute(builder: (context) => PantallaIngreso(usuario: widget.usuarioRegistra, idTiendaGlobal: widget.idTiendaGlobal)));
                  if (mounted) setState(() => _enSubPantalla = false);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                      label: const Text('TRASVASE MASIVO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      onPressed: () => _irATrasvaseMasivo(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _refInv.where('ubicacion', isEqualTo: kUbicacionTransito).snapshots(),
                    builder: (context, snap) {
                      int lotesEnCarrito = snap.hasData ? snap.data!.docs.length : 0;
                      int pzasEnCarrito = 0;
                      if (snap.hasData) {
                        for (var doc in snap.data!.docs) {
                          pzasEnCarrito += ((doc.data() as Map<String, dynamic>)['cantidad'] ?? 0) as int;
                        }
                      }
                      bool tieneCarga = lotesEnCarrito > 0;

                      return SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: tieneCarga ? Colors.deepOrangeAccent : Colors.white12,
                            foregroundColor: tieneCarga ? Colors.white : Colors.white70,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            side: BorderSide(color: tieneCarga ? Colors.amberAccent : Colors.white24, width: tieneCarga ? 1.5 : 1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: Icon(tieneCarga ? Icons.shopping_cart_checkout : Icons.shopping_cart_outlined, size: 18),
                          label: Text(
                            tieneCarga ? 'EN TRÁNSITO ($lotesEnCarrito • ${pzasEnCarrito}pz)' : 'CARRITO TEMPORAL (0)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () => _irACarritoTemporal(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_modoTrasvase)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.6)),
                ),
                child: Text(
                  (_ubicacionDestino != null && _ubicacionDestino != 'Sin anclar')
                      ? '⚡ Trasvase Rápido: Destino anclado en ${JerarquiaUbicacionHelper.formatearRutaVisual(_ubicacionDestino)}. Escanea el SKU/UPC para traer mercancía aquí.'
                      : '⚡ Trasvase Rápido Directo: Ancla la ubicación destino abajo (o con QR) o escanea directo el SKU/UPC.',
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _refUbi.orderBy('nombre').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const LinearProgressIndicator(color: Colors.amber);
                      List<String> listaMuebles = snapshot.data!.docs.map((d) => d['nombre'] as String).where((n) => n != kUbicacionTransito).toList();
                      if (_ubicacionDestino != null && !listaMuebles.contains(_ubicacionDestino)) listaMuebles.add(_ubicacionDestino!);
                      List<String> hojas = listaMuebles.where((u) => !listaMuebles.any((otra) => otra.startsWith('$u > '))).toList();
                      return SelectorJerarquicoUbicacion(
                        todasLasRutas: hojas,
                        rutaSeleccionada: _ubicacionDestino,
                        permitirSeleccionParcial: false,
                        textoRaizVacio: _modoTrasvase
                            ? '🎯 Sin anclar (Elige Destino para Trasvase Rápido: PISO, BODEGA, DISPLAY)'
                            : '📍 Sin anclar (Selecciona PISO, BODEGA o DISPLAY)',
                        onRutaCambiada: (val) => setState(() => _ubicacionDestino = val),
                      );
                    },
                  ),
                ),
                if (_ubicacionDestino != null && _ubicacionDestino != "Sin anclar")
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.redAccent),
                    tooltip: "Desanclar ubicación",
                    onPressed: () => setState(() => _ubicacionDestino = null),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: _modoTrasvase ? Colors.blueAccent : Colors.amber, width: 2.5)),
              clipBehavior: Clip.hardEdge,
              child: mostrarCamara
                  ? Stack(
                      children: [
                        MobileScanner(
                          onDetect: (capture) {
                            if (_bloquearEscaneo) return;
                            final barcode = capture.barcodes.first;
                            if (barcode.rawValue != null) {
                              setState(() => _bloquearEscaneo = true);
                              _procesarEscaneo(barcode.rawValue!);
                            }
                          },
                        ),
                        Center(
                          child: SizedBox(
                            width: 200,
                            height: 200,
                            child: Stack(
                              children: [
                                Container(decoration: BoxDecoration(border: Border.all(color: Colors.white30, width: 2), borderRadius: BorderRadius.circular(16))),
                                AnimatedBuilder(
                                  animation: _laserAnimation,
                                  builder: (context, child) => Positioned(
                                    top: _laserAnimation.value,
                                    left: 10,
                                    right: 10,
                                    child: Container(height: 3, decoration: BoxDecoration(color: Colors.redAccent, boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.8), blurRadius: 10, spreadRadius: 2)])),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.videocam_off, size: 50, color: Colors.white24),
                          const SizedBox(height: 8),
                          Text(
                            _camaraActiva
                                ? 'Cámara en pausa\n(Modo alto rendimiento)'
                                : 'Cámara desactivada (Ahorro de RAM y Batería)\nListo para usar con escáner físico abajo',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              height: 48,
              child: TextField(
                controller: _skuController,
                focusNode: _skuManualFocus,
                decoration: InputDecoration(
                  hintText: _modoTrasvase ? 'Escanea SKU / UPC para Trasvase Rápido...' : 'SKU / UPC Manual...',
                  filled: true,
                  fillColor: Colors.white10,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.search, color: _modoTrasvase ? Colors.blueAccent : Colors.amber),
                    onPressed: () {
                      if (_skuController.text.isNotEmpty) {
                        setState(() => _bloquearEscaneo = true);
                        _procesarEscaneo(_skuController.text);
                      }
                    },
                  ),
                ),
                onSubmitted: (val) {
                  if (val.isNotEmpty) {
                    setState(() => _bloquearEscaneo = true);
                    _procesarEscaneo(val);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PantallaEscanerQRUbicacion extends StatefulWidget {
  const PantallaEscanerQRUbicacion({super.key});
  @override
  State<PantallaEscanerQRUbicacion> createState() => _PantallaEscanerQRUbicacionState();
}

class _PantallaEscanerQRUbicacionState extends State<PantallaEscanerQRUbicacion> {
  bool _detectado = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR de Ubicación Destino', style: TextStyle(color: Colors.amber, fontSize: 15, fontWeight: FontWeight.bold))),
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

class PantallaRegistro extends StatefulWidget {
  final String skuEscaneado;
  final String? ubicacionPredefinida;
  final String usuarioRegistra;
  final String idTiendaGlobal;
  const PantallaRegistro({super.key, required this.skuEscaneado, this.ubicacionPredefinida, required this.usuarioRegistra, required this.idTiendaGlobal});
  @override
  State<PantallaRegistro> createState() => _PantallaRegistroState();
}

class _PantallaRegistroState extends State<PantallaRegistro> {
  DateTime? _fechaSeleccionada;
  String? _ubicacionSeleccionada;
  bool _guardando = false;
  final TextEditingController _cantidadController = TextEditingController(text: "1");
  String _descripcion = "Buscando...";
  late String _skuOficial;
  Map<String, dynamic>? _datosMaestros;

  @override
  void initState() {
    super.initState();
    _skuOficial = widget.skuEscaneado.trim();
    if (widget.ubicacionPredefinida != null && widget.ubicacionPredefinida != "Sin anclar") _ubicacionSeleccionada = widget.ubicacionPredefinida;
    _buscarDatosOriginales();
  }

  Future<void> _buscarDatosOriginales() async {
    try {
      String codigo = widget.skuEscaneado.trim();
      _datosMaestros = await JerarquiaUbicacionHelper.buscarProductoMaestro(codigo);
      if (mounted) {
        setState(() {
          if (_datosMaestros != null) {
            if (_datosMaestros!['sku'] != null && _datosMaestros!['sku'].toString().trim().isNotEmpty) {
              _skuOficial = _datosMaestros!['sku'].toString().trim();
            }
            _descripcion = _datosMaestros?['descripcion'] ?? "Sin Nombre";
          } else {
            _descripcion = "Artículo Nuevo";
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _descripcion = "Error");
    }
  }

  Future<void> _guardarEnNube() async {
    if (_ubicacionSeleccionada == null || _fechaSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Revisa Fecha y Mueble'), backgroundColor: Colors.redAccent));
      return;
    }
    setState(() => _guardando = true);
    try {
      int cantNueva = int.tryParse(_cantidadController.text) ?? 1;
      var refInv = FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('inventario_activo');
      var existentes = await refInv.where('sku', isEqualTo: _skuOficial).where('ubicacion', isEqualTo: _ubicacionSeleccionada).get();

      QueryDocumentSnapshot? loteIgual;
      for (var d in existentes.docs) {
        DateTime fDoc = (d['fechaCaducidad'] as Timestamp).toDate();
        if (fDoc.year == _fechaSeleccionada!.year && fDoc.month == _fechaSeleccionada!.month && fDoc.day == _fechaSeleccionada!.day) {
          loteIgual = d;
          break;
        }
      }

      if (loteIgual != null) {
        int cantActual = loteIgual['cantidad'] ?? 0;
        await loteIgual.reference.update({'cantidad': cantActual + cantNueva});
      } else {
        bool esTemp = _datosMaestros == null || _datosMaestros!['esTemporal'] == true;
        var map = <String, dynamic>{
          'sku': _skuOficial,
          'codigoOriginalCapturado': widget.skuEscaneado.trim(),
          if (esTemp && _descripcion != 'Artículo Nuevo') 'edicionTemporal': true,
          'descripcion': _descripcion,
          'ubicacion': _ubicacionSeleccionada,
          'cantidad': cantNueva,
          'fechaCaducidad': Timestamp.fromDate(_fechaSeleccionada!),
          'fechaCaptura': FieldValue.serverTimestamp(),
          'capturista': widget.usuarioRegistra,
        };
        if (_datosMaestros != null) {
          map.addAll(_datosMaestros!);
          map['sku'] = _skuOficial;
        }
        await refInv.add(map);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _guardando = false);
    }
  }

  DateTime? _parsearFechaManual(String input) {
    String raw = input.trim();
    if (raw.isEmpty) return null;

    int? dia, mes, anio;
    if (RegExp(r'[.,/\-\s]').hasMatch(raw)) {
      List<String> partes = raw.split(RegExp(r'[.,/\-\s]+')).where((s) => s.isNotEmpty).toList();
      if (partes.length == 3) {
        dia = int.tryParse(partes[0]);
        mes = int.tryParse(partes[1]);
        anio = int.tryParse(partes[2]);
      }
    } else {
      String clean = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (clean.length == 8) {
        dia = int.tryParse(clean.substring(0, 2));
        mes = int.tryParse(clean.substring(2, 4));
        anio = int.tryParse(clean.substring(4, 8));
      } else if (clean.length == 6) {
        dia = int.tryParse(clean.substring(0, 2));
        mes = int.tryParse(clean.substring(2, 4));
        int? y2 = int.tryParse(clean.substring(4, 6));
        if (y2 != null) anio = 2000 + y2;
      }
    }

    if (dia == null || mes == null || anio == null) return null;
    if (anio < 100) anio += 2000;
    if (mes < 1 || mes > 12 || dia < 1 || dia > 31 || anio < 2020 || anio > 2100) return null;

    DateTime fecha = DateTime(anio, mes, dia);
    if (fecha.year != anio || fecha.month != mes || fecha.day != dia) return null;
    return fecha;
  }

  void _mostrarDialogoIngresoFechaManual() {
    final TextEditingController manualFechaCtrl = TextEditingController();

    void confirmarTexto(BuildContext dialogCtx) {
      DateTime? fechaParseada = _parsearFechaManual(manualFechaCtrl.text);
      if (fechaParseada != null) {
        setState(() => _fechaSeleccionada = fechaParseada);
        Navigator.pop(dialogCtx);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Formato inválido. Usa 01.01.2026, 01,01,2026, 01012026 o 01/01/2026'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.amber, width: 1.5)),
        title: const Row(
          children: [
            Icon(Icons.dialpad, color: Colors.amber, size: 22),
            SizedBox(width: 8),
            Expanded(child: Text('Ingreso Manual de Caducidad', style: TextStyle(color: Colors.amber, fontSize: 15, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Formatos aceptados: 01.01.2026 • 01,01,2026 • 01012026 • 01/01/2026',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: manualFechaCtrl,
              autofocus: true,
              keyboardType: TextInputType.datetime,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.amberAccent),
              decoration: const InputDecoration(
                labelText: 'Escribe la fecha de caducidad',
                hintText: 'Ej. 01012026 o 01.01.2026',
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => confirmarTexto(ctx),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => confirmarTexto(ctx),
          ),
        ],
      ),
    );
  }

  void _mostrarSelectorFechaFluido() {
    DateTime tempDate = _fechaSeleccionada ?? DateTime.now();
    DateTime hoy = DateTime.now();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          height: 370,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text('Fecha de Caducidad', style: TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Expanded(
                child: CalendarDatePicker(
                  initialDate: tempDate,
                  firstDate: DateTime(hoy.year, hoy.month, hoy.day),
                  lastDate: DateTime(hoy.year + 10, hoy.month, hoy.day),
                  onDateChanged: (DateTime newDate) => tempDate = newDate,
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.cyanAccent,
                      side: const BorderSide(color: Colors.cyanAccent),
                    ),
                    icon: const Icon(Icons.dialpad, size: 16),
                    label: const Text('Ingreso Manual', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: () {
                      Navigator.pop(context);
                      _mostrarDialogoIngresoFechaManual();
                    },
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                    onPressed: () {
                      setState(() => _fechaSeleccionada = tempDate);
                      Navigator.pop(context);
                    },
                    child: const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar Entrada')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text(_descripcion, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.amber), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('SKU Oficial: $_skuOficial', style: const TextStyle(fontSize: 14, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 25),
            TextField(controller: _cantidadController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad de Piezas', filled: true)),
            const SizedBox(height: 20),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('ubicaciones').orderBy('nombre').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                List<String> todas = snapshot.data!.docs.map((d) => d['nombre'] as String).where((n) => n != 'EN TRÁNSITO').toList();
                List<String> listaMuebles = todas.where((u) => !todas.any((otra) => otra.startsWith('$u > '))).toList();
                if (_ubicacionSeleccionada != null && !listaMuebles.contains(_ubicacionSeleccionada)) listaMuebles.add(_ubicacionSeleccionada!);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ubicación Exacta (Jerarquía):', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    SelectorJerarquicoUbicacion(
                      todasLasRutas: listaMuebles,
                      rutaSeleccionada: _ubicacionSeleccionada,
                      permitirSeleccionParcial: false,
                      textoRaizVacio: '1. Selecciona Área (Piso / Bodega / Display)...',
                      onRutaCambiada: (val) => setState(() => _ubicacionSeleccionada = val),
                    ),
                    if (_ubicacionSeleccionada != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '✅ Destino seleccionado: ${JerarquiaUbicacionHelper.formatearRutaVisual(_ubicacionSeleccionada)}',
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.calendar_month),
              label: Text(
                _fechaSeleccionada == null ? 'Seleccionar Fecha' : "${_fechaSeleccionada!.day.toString().padLeft(2, '0')} / ${_fechaSeleccionada!.month.toString().padLeft(2, '0')} / ${_fechaSeleccionada!.year}",
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.white10, foregroundColor: Colors.white),
              onPressed: _mostrarSelectorFechaFluido,
            ),
            const SizedBox(height: 50),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: (_fechaSeleccionada == null || _guardando) ? null : _guardarEnNube,
                child: _guardando ? const CircularProgressIndicator() : const Text('CONFIRMAR Y GUARDAR'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
