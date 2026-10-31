import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'trasvase_pantallas.dart';
import '../modelos/selector_jerarquico_ubicacion.dart';
import 'finanzas.dart';
import 'sabana.dart';

class PantallaMisiones extends StatefulWidget {
  final String idTiendaGlobal;
  final String usuarioActual;
  const PantallaMisiones({super.key, required this.idTiendaGlobal, required this.usuarioActual});

  @override
  State<PantallaMisiones> createState() => _PantallaMisionesState();
}

class _PantallaMisionesState extends State<PantallaMisiones> {
  final TextEditingController _busquedaMisionCtrl = TextEditingController();
  String _busquedaMision = '';
  bool _actualizando = false;
  bool _verHistorial = false;
  bool _filtrosOcultosMisiones = false;
  String? _filtroProveedorMision;
  String? _filtroMuebleMision;
  int? _filtroTipoMision;
  int? _anioFiltroHistMision = DateTime.now().year;
  int? _mesFiltroHistMision = DateTime.now().month;
  int? _semanaFiltroHistMision;

  static const String kUbicacionTransito = 'EN TRÁNSITO';
  static const int kLimiteHistorialMisiones = 100;
  static const int kDiasVentanaHistorialMisiones = 92; // 3 meses

  static const Map<int, String> _nombresMesesMision = {
    1: 'Enero', 2: 'Febrero', 3: 'Marzo', 4: 'Abril',
    5: 'Mayo', 6: 'Junio', 7: 'Julio', 8: 'Agosto',
    9: 'Septiembre', 10: 'Octubre', 11: 'Noviembre', 12: 'Diciembre'
  };

  @override
  void initState() {
    super.initState();
    JerarquiaUbicacionHelper.precargarCacheUpc();
  }

  int _calcularSemanaMision(DateTime fecha) {
    return ((fecha.day - 1) ~/ 7) + 1;
  }

  CollectionReference<Map<String, dynamic>> get _refInv =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('inventario_activo');

  CollectionReference<Map<String, dynamic>> get _refMisiones =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('misiones_auditoria');

  CollectionReference<Map<String, dynamic>> get _refHist =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('historial_tratamientos');

  int _getPriority(Map<String, dynamic> m) {
    String msg = (m['mensaje'] ?? '').toString();
    if (msg.contains('CARRITO ABANDONADO')) return 0;
    if (msg.contains('REACTIVACIÓN 15 DÍAS') || m['soloMermaODevolucion'] == true) return 1;
    if (msg.contains('90 DÍAS')) return 2;
    if (msg.contains('45 días')) return 3;
    if (m['descontado'] != null) return 4;
    if (m['esArticuloNuevo'] == true || msg.contains('ARTÍCULO NUEVO')) return 5;
    return 6;
  }

  Widget _buildHeader(int priority, bool completada) {
    if (completada) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        color: Colors.green.shade800,
        width: double.infinity,
        child: const Text('✅ MISIÓN COMPLETADA (Toca ↩️ para Deshacer / Restaurar)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
      );
    }
    if (priority == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        color: Colors.deepOrangeAccent,
        width: double.infinity,
        child: const Text('🛒 URGENTE: CARRITO SIN ACOMODAR (Mantén presionado para abrir)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
      );
    }
    if (priority == 1) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        color: Colors.redAccent.shade700,
        width: double.infinity,
        child: const Text('🔥 CRÍTICO ≤15 DÍAS: REACTIVACIÓN (Solo Merma o Devolución)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
      );
    }
    if (priority == 2) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        color: Colors.pinkAccent,
        width: double.infinity,
        child: const Text('🚨 URGENTE: POLÍTICA BODEGA (Mantén presionado -> Enviar a Carrito)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
      );
    }
    if (priority == 3) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        color: Colors.orangeAccent,
        width: double.infinity,
        child: const Text('⚠️ ALERTA: CADUCIDAD 45 DÍAS (Mantén presionado -> Dar Tratamiento)', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10)),
      );
    }
    if (priority == 4) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        color: Colors.blueAccent,
        width: double.infinity,
        child: const Text('🛒 OPERACIÓN: DESCONTAR VENTA (Mantén presionado -> Opciones)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
      );
    }
    if (priority == 5) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        color: Colors.purpleAccent.shade700,
        width: double.infinity,
        child: const Text('🔎 AUDITORÍA DE CATÁLOGO: VALIDAR UPC / SKU EN ANAQUEL (Toca para editar)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
      );
    }
    return const SizedBox.shrink();
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _buscarLoteInventario(Map<String, dynamic> m) async {
    String sku = (m['sku'] ?? '').toString();
    String ubi = (m['ubicacion'] ?? '').toString();
    Timestamp? ts = m['fechaCaducidad'];

    var snap = await _refInv.where('sku', isEqualTo: sku).get();
    for (var doc in snap.docs) {
      var d = doc.data();
      if ((d['ubicacion'] ?? '') == ubi && ts != null && d['fechaCaducidad'] != null) {
        DateTime f1 = ts.toDate();
        DateTime f2 = (d['fechaCaducidad'] as Timestamp).toDate();
        if (f1.year == f2.year && f1.month == f2.month && f1.day == f2.day) return doc;
      }
    }
    for (var doc in snap.docs) {
      if ((doc.data()['ubicacion'] ?? '') == ubi) return doc;
    }
    return snap.docs.isNotEmpty ? snap.docs.first : null;
  }

  void _ejecutarAccionMision(QueryDocumentSnapshot docMision, int prioridad) {
    var m = docMision.data() as Map<String, dynamic>;
    if (prioridad == 0) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PantallaCarritoTemporal(idTiendaGlobal: widget.idTiendaGlobal, usuarioRegistra: widget.usuarioActual)));
    } else if (prioridad == 1) {
      _dialogoTratamientoDesdeMision(docMision, m, soloMermaODevolucion: true);
    } else if (prioridad == 2) {
      _dialogoEnviarBodegaACarrito(docMision, m);
    } else if (prioridad == 3) {
      _dialogoTratamientoDesdeMision(docMision, m, soloMermaODevolucion: false);
    } else if (prioridad == 4) {
      _dialogoAuditoriaVenta(docMision, m);
    } else if (prioridad == 5) {
      _dialogoValidarArticuloNuevo(docMision, m);
    }
  }

  // DESHACER / RESTAURAR MISIÓN DESDE EL HISTORIAL
  void _dialogoDeshacerMision(QueryDocumentSnapshot docMision) {
    var m = docMision.data() as Map<String, dynamic>;
    int cant = m['cantidadAfectada'] ?? m['cantidad'] ?? m['descontado'] ?? 1;
    String ubiOriginal = (m['ubicacion'] ?? 'PISO').toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.amber, width: 2)),
        title: const Text('↩️ Deshacer Misión Completada', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m['descripcion'] ?? m['sku'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Ubicación: $ubiOriginal • Cantidad: $cant pzas', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 12),
            const Text('¿Cómo deseas revertir esta misión?', style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.blueAccent, side: const BorderSide(color: Colors.blueAccent)),
            onPressed: () async {
              Navigator.pop(ctx);
              await docMision.reference.update({'estado': 'pendiente'});
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📋 Misión reabierta en Pendientes'), backgroundColor: Colors.blueAccent));
            },
            child: const Text('SOLO REABRIR MISIÓN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black),
            icon: const Icon(Icons.settings_backup_restore, size: 18),
            label: const Text('REABRIR Y RESTAURAR LOTE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.pop(ctx);
              var docInv = await _buscarLoteInventario(m);
              var batch = FirebaseFirestore.instance.batch();

              if (docInv != null) {
                int cantActual = docInv.data()['cantidad'] ?? 0;
                batch.update(docInv.reference, {
                  'cantidad': (m['accionRealizada'] == 'promocion') ? cantActual : (cantActual + cant),
                  'enPromocion': FieldValue.delete(),
                  'piezasEnPromocion': FieldValue.delete(),
                });
              } else {
                batch.set(_refInv.doc(), {
                  'sku': m['sku'],
                  'descripcion': m['descripcion'] ?? 'ND',
                  'ubicacion': ubiOriginal,
                  'cantidad': cant,
                  'fechaCaducidad': m['fechaCaducidad'],
                  'nombreProveedor': m['nombreProveedor'] ?? 'ND',
                  'nombreGpoArticulos': m['nombreGpoArticulos'] ?? 'SIN GRUPO',
                  'precioVenta': m['precioVenta'] ?? '0',
                  'oh': m['oh'] ?? '0',
                  'fechaCaptura': FieldValue.serverTimestamp(),
                  'capturista': widget.usuarioActual,
                });
              }
              if (m['accionRealizada'] == 'carrito') {
                var qTrans = await _refInv.where('ubicacion', isEqualTo: kUbicacionTransito).where('sku', isEqualTo: m['sku']).get();
                for (var dT in qTrans.docs) {
                  if ((dT.data()['ubicacionOrigen'] ?? '') == ubiOriginal) {
                    int cTrans = dT.data()['cantidad'] ?? 0;
                    if (cTrans <= cant) {
                      batch.delete(dT.reference);
                    } else {
                      batch.update(dT.reference, {'cantidad': cTrans - cant});
                    }
                    break;
                  }
                }
              }
              batch.update(docMision.reference, {'estado': 'pendiente'});
              await batch.commit();

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✅ Misión reactivada y lote restaurado en $ubiOriginal'), backgroundColor: Colors.green),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _dialogoEnviarBodegaACarrito(QueryDocumentSnapshot docMision, Map<String, dynamic> m) async {
    var docInv = await _buscarLoteInventario(m);
    if (!mounted) return;
    if (docInv == null) {
      await docMision.reference.update({'estado': 'completada', 'completadaPor': widget.usuarioActual});
      return;
    }

    var dataInv = docInv.data();
    int cantDisponible = dataInv['cantidad'] ?? 1;
    TextEditingController cantCtrl = TextEditingController(text: cantDisponible.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('🚨 Extraer al Carrito Temporal', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: cantCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Piezas a subir al Carrito (Máx: $cantDisponible)', filled: true, fillColor: Colors.white10),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent, foregroundColor: Colors.white),
            onPressed: () async {
              int cantMover = (int.tryParse(cantCtrl.text.trim()) ?? 0).clamp(0, cantDisponible);
              if (cantMover <= 0) return;
              Navigator.pop(ctx);

              var batch = FirebaseFirestore.instance.batch();
              if (cantDisponible <= cantMover) batch.delete(docInv.reference);
              else batch.update(docInv.reference, {'cantidad': cantDisponible - cantMover});

              var nuevoLote = Map<String, dynamic>.from(dataInv);
              nuevoLote['cantidad'] = cantMover;
              nuevoLote['ubicacion'] = kUbicacionTransito;
              nuevoLote['ubicacionOrigen'] = dataInv['ubicacion'];
              nuevoLote['fechaTransito'] = FieldValue.serverTimestamp();
              nuevoLote['usuarioTransito'] = widget.usuarioActual;
              batch.set(_refInv.doc(), nuevoLote);

              batch.update(docMision.reference, {
                'estado': 'completada',
                'completadaPor': widget.usuarioActual,
                'accionRealizada': 'carrito',
                'cantidadAfectada': cantMover,
              });
              await batch.commit();
            },
            child: const Text('CARGAR AL CARRITO'),
          ),
        ],
      ),
    );
  }

  void _dialogoTratamientoDesdeMision(QueryDocumentSnapshot docMision, Map<String, dynamic> m, {required bool soloMermaODevolucion}) async {
    var docInv = await _buscarLoteInventario(m);
    if (!mounted) return;
    if (docInv == null) {
      await docMision.reference.update({'estado': 'completada', 'completadaPor': widget.usuarioActual});
      return;
    }

    var d = docInv.data();
    int cantOriginal = d['cantidad'] ?? 1;
    DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
    int dias = cad.difference(DateTime.now()).inDays;
    bool restringir = soloMermaODevolucion || d['enPromocion'] == true || dias <= 15;

    TextEditingController cantCtrl = TextEditingController(text: cantOriginal.toString());
    String motivoSeleccionado = restringir ? 'Merma / Destrucción' : 'Saldado / Promoción';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool esPromocion = motivoSeleccionado == 'Saldado / Promoción';
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: Text(restringir ? '🔥 Baja Definitiva (≤ 15 Días)' : '⚠️ Tratamiento (45 Días)', style: TextStyle(color: restringir ? Colors.redAccent : Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d['descripcion'] ?? d['sku'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                if (restringir)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('⚠️ Lote reactivado / crítico (≤15 días): Solo admite Merma o Devolución.', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(height: 12),
                TextField(controller: cantCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Piezas a tratar', filled: true, fillColor: Colors.white10)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Motivo de Salida', filled: true, fillColor: Colors.white10),
                  dropdownColor: const Color(0xFF2C2C2C),
                  value: motivoSeleccionado,
                  items: [
                    if (!restringir) const DropdownMenuItem(value: 'Saldado / Promoción', child: Text('🏷️ Saldado / Promoción')),
                    const DropdownMenuItem(value: 'Merma / Destrucción', child: Text('📉 Merma / Destrucción')),
                    const DropdownMenuItem(value: 'Devolución a Proveedor', child: Text('📦 Devolución a Proveedor')),
                  ],
                  onChanged: (val) => setDialogState(() => motivoSeleccionado = val!),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                onPressed: () async {
                  int cantATratar = (int.tryParse(cantCtrl.text.trim()) ?? 0).clamp(0, cantOriginal);
                  if (cantATratar <= 0) return;
                  Navigator.pop(ctx);

                  double precio = double.tryParse((d['precioVenta'] ?? 0).toString()) ?? 0.0;
                  var batch = FirebaseFirestore.instance.batch();

                  batch.set(_refHist.doc(), {
                    'sku': d['sku'],
                    'descripcion': d['descripcion'],
                    'nombreProveedor': d['nombreProveedor'] ?? 'ND',
                    'nombreGpoArticulos': d['nombreGpoArticulos'] ?? 'SIN GRUPO',
                    'ubicacion': d['ubicacion'],
                    'cantidadTratada': cantATratar,
                    'motivo': motivoSeleccionado,
                    'costoTotal': cantATratar * precio,
                    'fechaTratamiento': FieldValue.serverTimestamp(),
                    'usuario': widget.usuarioActual,
                  });
                  FinanzasService.actualizarResumenEnBatch(
                    batch: batch,
                    idTiendaGlobal: widget.idTiendaGlobal,
                    motivo: motivoSeleccionado,
                    cantidad: cantATratar,
                    monto: cantATratar * precio,
                  );

                  if (esPromocion) {
                    batch.update(docInv.reference, {
                      'enPromocion': true,
                      'piezasEnPromocion': cantATratar,
                      if (d['comentarioCorporativo'] != null) 'instruccionCorpEjecutada': true,
                      if (d['comentarioCorporativo'] != null) 'ejecutadaPorCorp': widget.usuarioActual,
                      if (d['comentarioCorporativo'] != null) 'motivoEjecucionCorp': motivoSeleccionado,
                    });
                  } else {
                    if (cantATratar == cantOriginal) batch.delete(docInv.reference);
                    else batch.update(docInv.reference, {
                      'cantidad': cantOriginal - cantATratar,
                      if (d['comentarioCorporativo'] != null) 'instruccionCorpEjecutada': true,
                      if (d['comentarioCorporativo'] != null) 'ejecutadaPorCorp': widget.usuarioActual,
                      if (d['comentarioCorporativo'] != null) 'motivoEjecucionCorp': motivoSeleccionado,
                    });
                  }

                  batch.update(docMision.reference, {
                    'estado': 'completada',
                    'completadaPor': widget.usuarioActual,
                    'accionRealizada': esPromocion ? 'promocion' : 'retiro',
                    'cantidadAfectada': cantATratar,
                    'precioVenta': d['precioVenta'] ?? '0',
                    'oh': d['oh'] ?? '0',
                  });
                  await batch.commit();
                },
                child: const Text('APLICAR', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _dialogoValidarArticuloNuevo(QueryDocumentSnapshot docMision, Map<String, dynamic> m) {
    String codigoOriginal = (m['sku'] ?? '').toString().trim();
    String ubi = JerarquiaUbicacionHelper.formatearRutaVisual(m['ubicacion']?.toString());
    String descActual = (m['descripcion'] ?? '').toString().trim();
    bool esPlaceholder = descActual.isEmpty ||
        descActual.toLowerCase().contains('artículo nuevo') ||
        descActual.toLowerCase().contains('articulo nuevo') ||
        descActual.toLowerCase().contains('sin nombre');

    TextEditingController skuOficialCtrl = TextEditingController(text: codigoOriginal);
    TextEditingController upcCtrl = TextEditingController(text: (m['ean'] ?? (codigoOriginal.length >= 11 ? codigoOriginal : '')).toString());
    TextEditingController descCtrl = TextEditingController(text: esPlaceholder ? '' : descActual);

    Map<String, dynamic>? datosMaestrosEncontrados;
    List<Map<String, dynamic>> sugerenciasCatalogo = [];
    bool buscandoPorNombre = false;
    String mensajeEstado = 'Ingresa el SKU de SAP o escribe parte del nombre abajo y toca la lupa para buscarlo en el catálogo:';
    bool guardando = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> buscarMatchCodigo(String cod) async {
            if (cod.trim().isEmpty) return;
            var res = await JerarquiaUbicacionHelper.buscarProductoMaestro(cod.trim());
            if (res != null) {
              setModalState(() {
                datosMaestrosEncontrados = res;
                sugerenciasCatalogo.clear();
                if (res['sku'] != null && res['sku'].toString().trim().isNotEmpty) {
                  skuOficialCtrl.text = res['sku'].toString().trim();
                }
                if (res['ean'] != null && res['ean'].toString().trim().isNotEmpty && upcCtrl.text.trim().isEmpty) {
                  upcCtrl.text = res['ean'].toString().trim();
                }
                descCtrl.text = (res['descripcion'] ?? '').toString();
                mensajeEstado = '✅ ¡Match encontrado en Catálogo SAP! (${res['nombreProveedor'] ?? 'ND'})';
              });
            } else {
              setModalState(() {
                datosMaestrosEncontrados = null;
                mensajeEstado = 'ℹ️ Ese código no está en el catálogo. Puedes buscarlo por nombre en el 3er campo o escribir su descripción.';
              });
            }
          }

          Future<void> buscarEnCatalogoPorNombre(String texto) async {
            String q = texto.trim();
            if (q.length < 2) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Escribe al menos 2 letras del nombre para buscar en el catálogo.')),
              );
              return;
            }
            setModalState(() {
              buscandoPorNombre = true;
              mensajeEstado = 'Buscando "$q" en el Catálogo Maestro...';
            });

            try {
              var snap = await FirebaseFirestore.instance.collection('maestro_productos').get();
              Map<String, Map<String, dynamic>> unicosPorSku = {};
              for (var doc in snap.docs) {
                var d = doc.data();
                String s = (d['sku'] ?? '').toString().trim();
                if (s.isNotEmpty && !unicosPorSku.containsKey(s) && d['esTemporal'] != true) {
                  unicosPorSku[s] = d;
                }
              }
              var lista = JerarquiaUbicacionHelper.buscarSugerenciasSemanticasIA(q, unicosPorSku.values);
              setModalState(() {
                buscandoPorNombre = false;
                sugerenciasCatalogo = lista;
                mensajeEstado = lista.isNotEmpty
                    ? '🧠 IA Semántica encontró ${lista.length} coincidencia(s) en SAP (ordenadas por similitud):'
                    : '⚠️ No hay coincidencias en SAP para "$q". Al guardar quedará como Edición Temporal hasta que Corporativo lo dé de alta.';
              });
            } catch (e) {
              setModalState(() {
                buscandoPorNombre = false;
                mensajeEstado = 'Error al buscar: $e';
              });
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.purpleAccent, width: 2)),
            title: const Row(
              children: [
                Icon(Icons.qr_code_2, color: Colors.purpleAccent, size: 24),
                SizedBox(width: 8),
                Expanded(
                  child: Text('🔎 Validar Artículo Nuevo (Sin Match)', style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.amber.withOpacity(0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.withOpacity(0.5))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('📍 Ubicación física: $ubi', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('Código capturado originalmente: $codigoOriginal', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      mensajeEstado,
                      style: TextStyle(
                        color: datosMaestrosEncontrados != null ? Colors.greenAccent : Colors.cyanAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: skuOficialCtrl,
                      decoration: InputDecoration(
                        labelText: 'SKU Oficial SAP (o código principal)',
                        filled: true,
                        fillColor: Colors.white10,
                        border: const OutlineInputBorder(),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.search, color: Colors.amber),
                              tooltip: 'Buscar código en Catálogo Maestro',
                              onPressed: () => buscarMatchCodigo(skuOficialCtrl.text),
                            ),
                            IconButton(
                              icon: const Icon(Icons.qr_code_scanner, color: Colors.cyanAccent),
                              tooltip: 'Escanear con cámara',
                              onPressed: () async {
                                String? escaneado = await Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaEscanerRapido()));
                                if (escaneado != null && escaneado.trim().isNotEmpty) {
                                  skuOficialCtrl.text = escaneado.trim();
                                  await buscarMatchCodigo(escaneado.trim());
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      onSubmitted: buscarMatchCodigo,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: upcCtrl,
                      decoration: const InputDecoration(
                        labelText: 'UPC / Código de Barras del Empaque (EAN)',
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtrl,
                      decoration: InputDecoration(
                        labelText: 'Descripción / Nombre (o escribe para buscar en SAP)',
                        hintText: 'Ej. TE VERDE, POCKY, RAMEN...',
                        filled: true,
                        fillColor: Colors.white10,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: buscandoPorNombre
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber))
                              : const Icon(Icons.manage_search, color: Colors.amber, size: 22),
                          tooltip: 'Buscar por nombre en Catálogo SAP',
                          onPressed: buscandoPorNombre ? null : () => buscarEnCatalogoPorNombre(descCtrl.text),
                        ),
                      ),
                      onSubmitted: buscarEnCatalogoPorNombre,
                    ),
                    if (sugerenciasCatalogo.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 170),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber.withOpacity(0.5)),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: sugerenciasCatalogo.length,
                          itemBuilder: (c, idx) {
                            var item = sugerenciasCatalogo[idx];
                            return ListTile(
                              dense: true,
                              leading: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.purpleAccent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.purpleAccent),
                                ),
                                child: Text('🧠 ${item['scoreIA'] ?? 90}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                              ),
                              title: Text(item['descripcion'] ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                              subtitle: Text('SKU: ${item['sku']} • UPC: ${JerarquiaUbicacionHelper.obtenerUpcVisual(item)}\nProv: ${item['nombreProveedor'] ?? 'ND'} (${item['razonIA'] ?? 'Semántica'})', style: const TextStyle(fontSize: 10, color: Colors.amberAccent)),
                              onTap: () {
                                setModalState(() {
                                  datosMaestrosEncontrados = item;
                                  skuOficialCtrl.text = (item['sku'] ?? '').toString().trim();
                                  descCtrl.text = (item['descripcion'] ?? '').toString().trim();
                                  sugerenciasCatalogo.clear();
                                  mensajeEstado = '✅ Seleccionado: ${item['descripcion']} (SKU: ${item['sku']})';
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: guardando ? null : () => Navigator.pop(ctx),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent, foregroundColor: Colors.white),
                icon: guardando
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_as, size: 18),
                label: const Text('GUARDAR EN TODAS LAS INSTANCIAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                onPressed: guardando
                    ? null
                    : () async {
                        String skuNuevo = skuOficialCtrl.text.trim();
                        if (skuNuevo.isEmpty) return;
                        setModalState(() => guardando = true);

                        if (datosMaestrosEncontrados == null) {
                          datosMaestrosEncontrados = await JerarquiaUbicacionHelper.buscarProductoMaestro(skuNuevo);
                        }
                        if (datosMaestrosEncontrados != null && datosMaestrosEncontrados!['sku'] != null) {
                          skuNuevo = datosMaestrosEncontrados!['sku'].toString().trim();
                        }

                        String textoDesc = descCtrl.text.trim();
                        bool textoSiguePlaceholder = textoDesc.isEmpty ||
                            textoDesc.toLowerCase().contains('artículo nuevo') ||
                            textoDesc.toLowerCase().contains('articulo nuevo');

                        String descNueva = (datosMaestrosEncontrados != null && datosMaestrosEncontrados!['descripcion'] != null)
                            ? datosMaestrosEncontrados!['descripcion'].toString().trim()
                            : (!textoSiguePlaceholder ? textoDesc : '');

                        if (descNueva.isEmpty) {
                          setModalState(() => guardando = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('⚠️ Escribe el nombre del artículo o selecciona uno del catálogo antes de guardar.'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }

                        int actualizados = await JerarquiaUbicacionHelper.actualizarArticuloEnTodasLasInstancias(
                          idTiendaGlobal: widget.idTiendaGlobal,
                          codigoAnterior: codigoOriginal,
                          nuevoSku: skuNuevo,
                          nuevoEan: upcCtrl.text.trim(),
                          nuevaDescripcion: descNueva,
                          datosMaestros: datosMaestrosEncontrados,
                          usuarioActual: widget.usuarioActual,
                        );

                        if (mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✅ Artículo actualizado en $actualizados lote(s) y vinculado en la Base de Datos.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  void _dialogoAuditoriaVenta(QueryDocumentSnapshot docMision, Map<String, dynamic> m) async {
    int pendientes = m['descontado'] ?? 1;
    String ubicacionOriginal = (m['ubicacion'] ?? 'PISO').toString();
    String sku = (m['sku'] ?? '').toString();

    var snapSku = await _refInv.where('sku', isEqualTo: sku).get();
    var docMismoLote = await _buscarLoteInventario(m);

    var otrosLotes = snapSku.docs.where((d) {
      if (docMismoLote != null && d.id == docMismoLote.id) return false;
      String u = (d.data()['ubicacion'] ?? '').toString();
      return u != kUbicacionTransito;
    }).toList();

    if (!mounted) return;

    Future<void> abrirDescuentoPorUbicacion({
      required BuildContext parentCtx,
      required String nombreUbicacion,
      required bool esUbicacionOriginalFIFO,
      QueryDocumentSnapshot<Map<String, dynamic>>? docAlterno,
    }) async {
      int dispAlterno = docAlterno != null ? (docAlterno.data()['cantidad'] ?? 0) : pendientes;
      int maxDescontar = esUbicacionOriginalFIFO
          ? pendientes
          : (dispAlterno < pendientes ? dispAlterno : pendientes);
      if (maxDescontar <= 0) maxDescontar = pendientes;

      TextEditingController cantCtrl = TextEditingController(text: '1');

      Future<void> procesarDescuento(int cantElegida) async {
        int cant = cantElegida.clamp(1, maxDescontar);
        var batch = FirebaseFirestore.instance.batch();

        if (!esUbicacionOriginalFIFO && docAlterno != null) {
          // 1. Devolver esas piezas al lote FIFO original porque salieron de esta otra mesa
          if (docMismoLote != null) {
            int cantOrig = docMismoLote.data()['cantidad'] ?? 0;
            batch.update(docMismoLote.reference, {'cantidad': cantOrig + cant});
          } else {
            batch.set(_refInv.doc(), {
              'sku': sku,
              'descripcion': m['descripcion'] ?? 'ND',
              'ubicacion': ubicacionOriginal,
              'cantidad': cant,
              'fechaCaducidad': m['fechaCaducidad'],
              'nombreProveedor': m['nombreProveedor'] ?? 'ND',
              'nombreGpoArticulos': m['nombreGpoArticulos'] ?? 'SIN GRUPO',
              'fechaCaptura': FieldValue.serverTimestamp(),
              'capturista': widget.usuarioActual,
            });
          }

          // 2. Descontar de la mesa seleccionada
          if (dispAlterno <= cant) {
            batch.delete(docAlterno.reference);
          } else {
            batch.update(docAlterno.reference, {'cantidad': dispAlterno - cant});
          }
        }

        int restantes = pendientes - cant;
        if (restantes <= 0) {
          batch.update(docMision.reference, {
            'estado': 'completada',
            'completadaPor': widget.usuarioActual,
            'ubicacion': esUbicacionOriginalFIFO ? ubicacionOriginal : '$nombreUbicacion (Validado en piso)',
          });
        } else {
          batch.update(docMision.reference, {
            'descontado': restantes,
          });
        }

        await batch.commit();
        if (mounted) {
          Navigator.pop(parentCtx);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                restantes <= 0
                    ? '✅ Venta validada en $nombreUbicacion. Misión completada.'
                    : '✅ Se descontaron $cant pza(s) de $nombreUbicacion. Quedan $restantes pza(s) por descontar.',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      }

      await showDialog(
        context: parentCtx,
        builder: (subCtx) => AlertDialog(
          backgroundColor: const Color(0xFF262626),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.cyanAccent, width: 1.5)),
          title: Text('📍 $nombreUbicacion', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ventas pendientes por descontar: $pendientes pza(s)', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: cantCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Piezas a descontar aquí (Máx: $maxDescontar)',
                  filled: true,
                  fillColor: Colors.black45,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(subCtx),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.amberAccent, side: const BorderSide(color: Colors.amberAccent)),
              onPressed: () {
                int v = int.tryParse(cantCtrl.text.trim()) ?? 1;
                Navigator.pop(subCtx);
                procesarDescuento(v);
              },
              child: const Text('DESCONTAR CANTIDAD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
              onPressed: () {
                Navigator.pop(subCtx);
                procesarDescuento(maxDescontar);
              },
              child: Text('DESCONTAR TODO ($maxDescontar)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    DateTime? cadOrig = (m['fechaCaducidad'] as Timestamp?)?.toDate();
    String fOrig = cadOrig != null ? "${cadOrig.day}/${cadOrig.month}/${cadOrig.year}" : "ND";
    int restOrig = docMismoLote != null ? (docMismoLote.data()['cantidad'] ?? 0) : 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.blueAccent, width: 2)),
        title: const Text('🛒 Auditoría Física de Venta', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m['descripcion'] ?? sku, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 13)),
              const SizedBox(height: 2),
              Text('SKU: $sku', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
              Text('UPC: ${JerarquiaUbicacionHelper.obtenerUpcVisual(m)}', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w600, fontSize: 11)),
              const SizedBox(height: 6),
              Text(
                'Pendiente por validar: $pendientes pza(s) vendida(s) en SAP.',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 6),
              const Text(
                'Mantén presionada (o toca) la ubicación de donde salió la mercancía para elegir cuántas piezas descontar:',
                style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              // Tarjeta de la ubicación sugerida por FIFO
              Card(
                color: Colors.green.withOpacity(0.15),
                margin: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.greenAccent)),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.star, color: Colors.greenAccent, size: 20),
                  title: Text('$ubicacionOriginal (Sugerido FIFO)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  subtitle: Text('Cad: $fOrig • Restante en lote: $restOrig pzas', style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
                  trailing: const Icon(Icons.touch_app, size: 16, color: Colors.greenAccent),
                  onTap: () => abrirDescuentoPorUbicacion(parentCtx: ctx, nombreUbicacion: ubicacionOriginal, esUbicacionOriginalFIFO: true),
                  onLongPress: () => abrirDescuentoPorUbicacion(parentCtx: ctx, nombreUbicacion: ubicacionOriginal, esUbicacionOriginalFIFO: true),
                ),
              ),
              if (otrosLotes.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 4),
                  child: Text('Otras mesas / ubicaciones con este SKU:', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                ...otrosLotes.map((docAlt) {
                  var dAlt = docAlt.data();
                  String ubiAlt = (dAlt['ubicacion'] ?? 'ND').toString();
                  int cantAlt = dAlt['cantidad'] ?? 0;
                  DateTime cadAlt = (dAlt['fechaCaducidad'] as Timestamp).toDate();
                  String fAlt = "${cadAlt.day}/${cadAlt.month}/${cadAlt.year}";

                  return Card(
                    color: Colors.white10,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.swap_calls, color: Colors.cyanAccent, size: 20),
                      title: Text(ubiAlt, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      subtitle: Text('Cad: $fAlt • Disponible: $cantAlt pzas', style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
                      trailing: const Icon(Icons.touch_app, size: 16, color: Colors.cyanAccent),
                      onTap: () => abrirDescuentoPorUbicacion(
                        parentCtx: ctx,
                        nombreUbicacion: ubiAlt,
                        esUbicacionOriginalFIFO: false,
                        docAlterno: docAlt,
                      ),
                      onLongPress: () => abrirDescuentoPorUbicacion(
                        parentCtx: ctx,
                        nombreUbicacion: ubiAlt,
                        esUbicacionOriginalFIFO: false,
                        docAlterno: docAlt,
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CERRAR', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _generarMisionesAutomaticas() async {
    setState(() => _actualizando = true);
    try {
      var results = await Future.wait([
        _refInv.get(),
        _refMisiones.where('estado', isEqualTo: 'pendiente').get(),
      ]);
      var snapshot = results[0];
      var misionesPendSnap = results[1];

      DateTime hoy = DateTime.now();
      var batch = FirebaseFirestore.instance.batch();
      int misionesNuevas = 0;
      int misionesAutocerradas = 0;

      // 1. AUTO-CONCILIACIÓN CON SÁBANA Y TRASVASE:
      // Revisar si alguna misión pendiente (Bodega 90d, 45d, 15d o Carrito) ya fue atendida desde Trasvase o Sábana
      for (var mDoc in misionesPendSnap.docs) {
        var m = mDoc.data();
        int prio = _getPriority(m);
        if (prio == 4) continue; // Las de venta SAP se validan manualmente en piso

        String mSku = (m['sku'] ?? '').toString();
        String mUbi = (m['ubicacion'] ?? '').toString();
        Timestamp? mTs = m['fechaCaducidad'];

        if (prio == 0) {
          // Carrito abandonado: verificar si sigue en EN TRÁNSITO
          bool sigueEnCarrito = snapshot.docs.any((d) {
            var data = d.data();
            return (data['ubicacion'] ?? '') == kUbicacionTransito && (data['sku'] ?? '') == mSku;
          });
          if (!sigueEnCarrito) {
            batch.update(mDoc.reference, {
              'estado': 'completada',
              'completadaPor': 'Auto-Trasvase',
            });
            misionesAutocerradas++;
          }
          continue;
        }

        // Buscar si el lote sigue existiendo con esa misma fecha de caducidad
        QueryDocumentSnapshot<Map<String, dynamic>>? loteMismaUbicacion;
        QueryDocumentSnapshot<Map<String, dynamic>>? loteEnPiso;

        for (var d in snapshot.docs) {
          var data = d.data();
          if ((data['sku'] ?? '').toString() != mSku) continue;
          if (mTs != null && data['fechaCaducidad'] != null) {
            DateTime f1 = mTs.toDate();
            DateTime f2 = (data['fechaCaducidad'] as Timestamp).toDate();
            if (f1.year == f2.year && f1.month == f2.month && f1.day == f2.day) {
              String uActual = (data['ubicacion'] ?? '').toString();
              if (uActual == mUbi) {
                loteMismaUbicacion = d;
                break;
              } else if (uActual != kUbicacionTransito) {
                loteEnPiso = d;
              }
            }
          }
        }

        if (prio == 2) {
          // Política Bodega 90 días: si ya no está en esa bodega (porque se trasvasó a piso o carrito), se autocompleta
          if (loteMismaUbicacion == null) {
            batch.update(mDoc.reference, {
              'estado': 'completada',
              'completadaPor': 'Sincronizado por Trasvase',
              'accionRealizada': 'trasvase',
            });
            misionesAutocerradas++;
          }
        } else if (prio == 1 || prio == 3) {
          // Caducidad 45d o 15d: si ya se le dio salida total en Sábana, se autocompleta; si se movió de mueble, actualiza su ubicación
          if (loteMismaUbicacion == null) {
            if (loteEnPiso != null) {
              batch.update(mDoc.reference, {
                'ubicacion': loteEnPiso.data()['ubicacion'],
                'cantidad': loteEnPiso.data()['cantidad'],
              });
            } else {
              batch.update(mDoc.reference, {
                'estado': 'completada',
                'completadaPor': 'Sincronizado con Sábana',
              });
              misionesAutocerradas++;
            }
          } else {
            // Si en la Sábana ya le aplicaron Promoción a una de 45d, cerrar la misión de 45d
            if (prio == 3 && loteMismaUbicacion.data()['enPromocion'] == true) {
              batch.update(mDoc.reference, {
                'estado': 'completada',
                'completadaPor': 'Promoción en Sábana',
                'accionRealizada': 'promocion',
              });
              misionesAutocerradas++;
            }
          }
        }
      }

      // 2. GENERAR NUEVAS MISIONES SI HAY LOTES QUE ENTRARON EN RIESGO O SON "ARTÍCULO NUEVO" SIN MATCH
      Set<String> codigosConMisionArtNuevoActiva = misionesPendSnap.docs
          .where((m) => _getPriority(m.data()) == 5)
          .map((m) => (m.data()['sku'] ?? '').toString().trim())
          .toSet();

      for (var doc in snapshot.docs) {
        var data = doc.data();
        String ubicacion = (data['ubicacion'] ?? '').toString().toUpperCase();
        String descLote = (data['descripcion'] ?? '').toString().trim();
        String skuLote = (data['sku'] ?? '').toString().trim();

        bool esMissing = descLote == 'Artículo Nuevo' ||
            descLote == 'ARTÍCULO NUEVO / NO EN CATÁLOGO' ||
            descLote == 'Sin Nombre';

        if (esMissing && skuLote.isNotEmpty && !codigosConMisionArtNuevoActiva.contains(skuLote)) {
          codigosConMisionArtNuevoActiva.add(skuLote);
          batch.set(_refMisiones.doc(), {
            'sku': skuLote,
            'ean': data['ean'] ?? (skuLote.length >= 11 ? skuLote : ''),
            'descripcion': 'Artículo Nuevo (Validar UPC / SKU en físico)',
            'ubicacion': data['ubicacion'] ?? 'ND',
            'cantidad': data['cantidad'] ?? 1,
            'fechaCaducidad': data['fechaCaducidad'],
            'nombreProveedor': data['nombreProveedor'] ?? 'SIN MATCH EN BD',
            'nombreGpoArticulos': data['nombreGpoArticulos'] ?? 'SIN GRUPO',
            'estado': 'pendiente',
            'esArticuloNuevo': true,
            'fechaGeneracion': FieldValue.serverTimestamp(),
            'mensaje': '🔎 ARTÍCULO NUEVO SIN MATCH: Ir a la ubicación, revisar físicamente el UPC / SKU del lote y editarlo para vincularlo.',
          });
          misionesNuevas++;
        }

        if (data['fechaCaducidad'] != null) {
          DateTime cad = (data['fechaCaducidad'] as Timestamp).toDate();
          int dias = cad.difference(hoy).inDays;

          if (dias <= 15 && data['misionReactivada15d'] != true) {
            batch.set(_refMisiones.doc(), {
              'sku': data['sku'],
              'descripcion': data['descripcion'] ?? 'ND',
              'ubicacion': data['ubicacion'] ?? 'ND',
              'cantidad': data['cantidad'],
              'fechaCaducidad': data['fechaCaducidad'],
              'nombreProveedor': data['nombreProveedor'] ?? 'ND',
              'nombreGpoArticulos': data['nombreGpoArticulos'] ?? 'SIN GRUPO',
              'estado': 'pendiente',
              if (data['comentarioCorporativo'] != null) 'comentarioCorporativo': data['comentarioCorporativo'],
              if (data['autorComentarioCorp'] != null) 'autorComentarioCorp': data['autorComentarioCorp'],
              'soloMermaODevolucion': true,
              'fechaGeneracion': FieldValue.serverTimestamp(),
              'mensaje': '🔥 REACTIVACIÓN 15 DÍAS: Lote en límite crítico. Proceder únicamente con Merma o Devolución',
            });
            batch.update(doc.reference, {'misionReactivada15d': true});
            misionesNuevas++;
          } else if (dias <= 45 && dias > 15 && data['misionGenerada45d'] != true) {
            batch.set(_refMisiones.doc(), {
              'sku': data['sku'],
              'descripcion': data['descripcion'] ?? 'ND',
              'ubicacion': data['ubicacion'] ?? 'ND',
              'cantidad': data['cantidad'],
              'fechaCaducidad': data['fechaCaducidad'],
              'nombreProveedor': data['nombreProveedor'] ?? 'ND',
              'nombreGpoArticulos': data['nombreGpoArticulos'] ?? 'SIN GRUPO',
              'estado': 'pendiente',
              if (data['comentarioCorporativo'] != null) 'comentarioCorporativo': data['comentarioCorporativo'],
              if (data['autorComentarioCorp'] != null) 'autorComentarioCorp': data['autorComentarioCorp'],
              'fechaGeneracion': FieldValue.serverTimestamp(),
              'mensaje': 'Verificar lote próximo a vencer (45 días)',
            });
            batch.update(doc.reference, {'misionGenerada45d': true});
            misionesNuevas++;
          }

          if (ubicacion.contains('BODEGA') && dias <= 90 && dias > 0 && data['misionBodega90d'] != true) {
            batch.set(_refMisiones.doc(), {
              'sku': data['sku'],
              'descripcion': data['descripcion'] ?? 'ND',
              'ubicacion': data['ubicacion'] ?? 'ND',
              'cantidad': data['cantidad'],
              'fechaCaducidad': data['fechaCaducidad'],
              'nombreProveedor': data['nombreProveedor'] ?? 'ND',
              'nombreGpoArticulos': data['nombreGpoArticulos'] ?? 'SIN GRUPO',
              'estado': 'pendiente',
              if (data['comentarioCorporativo'] != null) 'comentarioCorporativo': data['comentarioCorporativo'],
              if (data['autorComentarioCorp'] != null) 'autorComentarioCorp': data['autorComentarioCorp'],
              'fechaGeneracion': FieldValue.serverTimestamp(),
              'mensaje': '🚨 POLÍTICA 90 DÍAS: Extraer de Bodega y reubicar en Piso/Display',
            });
            batch.update(doc.reference, {'misionBodega90d': true});
            misionesNuevas++;
          }
        }
      }

      if (misionesNuevas > 0 || misionesAutocerradas > 0) {
        await batch.commit();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🔄 Sincronizado: $misionesNuevas nuevas • $misionesAutocerradas actualizadas por Trasvase/Sábana',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actualizando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Misiones de Auditoría', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(
            icon: _actualizando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber)) : const Icon(Icons.refresh, color: Colors.amber),
            onPressed: _actualizando ? null : _generarMisionesAutomaticas,
          ),
        ],
      ),
      body: Column(
        children: [
          // Pestañas: Pendientes vs Historial de Misiones
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: !_verHistorial ? Colors.amber : Colors.white10,
                      foregroundColor: !_verHistorial ? Colors.black : Colors.white70,
                    ),
                    icon: const Icon(Icons.assignment_late, size: 16),
                    label: const Text('PENDIENTES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    onPressed: () => setState(() => _verHistorial = false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _verHistorial ? Colors.amber : Colors.white10,
                      foregroundColor: _verHistorial ? Colors.black : Colors.white70,
                    ),
                    icon: const Icon(Icons.history, size: 16),
                    label: const Text('HISTORIAL (DESHACER)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    onPressed: () => setState(() => _verHistorial = true),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: Colors.amber,
              onRefresh: _generarMisionesAutomaticas,
              child: StreamBuilder<QuerySnapshot>(
                stream: _refMisiones.snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.amber));

                  String estadoBuscado = _verHistorial ? 'completada' : 'pendiente';
                  DateTime hoy = DateTime.now();
                  DateTime corte3Meses = hoy.subtract(const Duration(days: kDiasVentanaHistorialMisiones));
                  List<int> aniosHistDisponibles = {hoy.year, corte3Meses.year}.toList()..sort((a, b) => b.compareTo(a));

                  var baseDocs = snapshot.data!.docs.where((doc) {
                    var d = doc.data() as Map<String, dynamic>;
                    if (d['estado'] != estadoBuscado) return false;
                    if (_verHistorial) {
                      Timestamp? ts = d['fechaGeneracion'] ?? d['fechaCaducidad'];
                      if (ts != null && ts.toDate().isBefore(corte3Meses)) {
                        return false;
                      }
                    }
                    return true;
                  }).toList();

                  var provsDisponibles = baseDocs
                      .map((d) => ((d.data() as Map<String, dynamic>)['nombreProveedor'] ?? 'ND').toString())
                      .toSet()
                      .toList()
                    ..sort();

                  Map<String, int> conteoPorUbicacionMision = {};
                  for (var doc in baseDocs) {
                    String u = ((doc.data() as Map<String, dynamic>)['ubicacion'] ?? 'ND').toString().trim();
                    if (u.isNotEmpty) {
                      conteoPorUbicacionMision[u] = (conteoPorUbicacionMision[u] ?? 0) + 1;
                    }
                  }
                  var mueblesDisponibles = JerarquiaUbicacionHelper.ordenarRutasPorJerarquia(conteoPorUbicacionMision.keys);

                  var listaFiltrada = baseDocs.where((doc) {
                    var d = doc.data() as Map<String, dynamic>;
                    String p = (d['nombreProveedor'] ?? 'ND').toString();
                    String u = (d['ubicacion'] ?? 'ND').toString();
                    bool okProv = _filtroProveedorMision == null || p == _filtroProveedorMision;
                    List<String> prefMueble = _filtroMuebleMision != null
                        ? JerarquiaUbicacionHelper.descomponerRuta(_filtroMuebleMision!)
                        : [];
                    bool okMueble = JerarquiaUbicacionHelper.coincideConPrefijoJerarquico(u, prefMueble);
                    int tipoPrio = _getPriority(d);
                    bool okTipo = _filtroTipoMision == null || tipoPrio == _filtroTipoMision;

                    bool okFechaHist = true;
                    if (_verHistorial) {
                      Timestamp? ts = d['fechaGeneracion'] ?? d['fechaCaducidad'];
                      if (ts != null) {
                        DateTime dt = ts.toDate();
                        if (_anioFiltroHistMision != null && dt.year != _anioFiltroHistMision) okFechaHist = false;
                        if (_mesFiltroHistMision != null && dt.month != _mesFiltroHistMision) okFechaHist = false;
                        if (_semanaFiltroHistMision != null && _calcularSemanaMision(dt) != _semanaFiltroHistMision) okFechaHist = false;
                      }
                    }

                    bool okBusqueda = _busquedaMision.isEmpty || JerarquiaUbicacionHelper.evaluarConsultaLenguajeNaturalIA(_busquedaMision, d);
                    return okProv && okMueble && okTipo && okFechaHist && okBusqueda;
                  }).toList();

                  listaFiltrada.sort((a, b) {
                    var dA = a.data() as Map<String, dynamic>;
                    var dB = b.data() as Map<String, dynamic>;
                    if (!_verHistorial) {
                      int pA = _getPriority(dA);
                      int pB = _getPriority(dB);
                      if (pA != pB) return pA.compareTo(pB);
                    }
                    Timestamp tA = dA['fechaGeneracion'] ?? Timestamp.now();
                    Timestamp tB = dB['fechaGeneracion'] ?? Timestamp.now();
                    return tB.compareTo(tA);
                  });

                  var lista = _verHistorial
                      ? listaFiltrada.take(kLimiteHistorialMisiones).toList()
                      : listaFiltrada;

                  bool hayFiltrosActivos = _busquedaMision.isNotEmpty || _filtroProveedorMision != null ||
                      _filtroMuebleMision != null ||
                      _filtroTipoMision != null ||
                      (_verHistorial && (_anioFiltroHistMision != hoy.year || _mesFiltroHistMision != hoy.month || _semanaFiltroHistMision != null));

                  return Column(
                    children: [
                      if (_filtrosOcultosMisiones)
                        InkWell(
                          onTap: () => setState(() => _filtrosOcultosMisiones = false),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              border: Border(bottom: BorderSide(color: Colors.amber.withOpacity(0.6), width: 1.5)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.amber, size: 20),
                                const SizedBox(width: 6),
                                Text(
                                  'Bajar Filtros (${lista.length} ${_verHistorial ? "en historial" : "misiones"})',
                                  style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.tune, color: Colors.amberAccent, size: 15),
                              ],
                            ),
                          ),
                        )
                      else
                        Container(
                          color: Colors.black,
                          padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_verHistorial) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      '⚡ Historial limitado a 3 meses (Máx. 100 misiones)',
                                      style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                    if (hayFiltrosActivos)
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        icon: const Icon(Icons.refresh, color: Colors.amberAccent, size: 14),
                                        label: const Text('Restaurar Mes', style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                        onPressed: () => setState(() {
                                          _filtroProveedorMision = null;
                                          _filtroMuebleMision = null;
                                          _filtroTipoMision = null;
                                          _anioFiltroHistMision = hoy.year;
                                          _mesFiltroHistMision = hoy.month;
                                          _semanaFiltroHistMision = null;
                                        }),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.only(left: 4, bottom: 3),
                                            child: Text('Filtro Año', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                                          ),
                                          Container(
                                            height: 40,
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                                            child: DropdownButtonHideUnderline(
                                              child: DropdownButton<int?>(
                                                isExpanded: true,
                                                dropdownColor: const Color(0xFF2C2C2C),
                                                value: aniosHistDisponibles.contains(_anioFiltroHistMision) ? _anioFiltroHistMision : null,
                                                items: [
                                                  const DropdownMenuItem(value: null, child: Text('Año: Últimos 3 meses', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                                                  ...aniosHistDisponibles.map((a) => DropdownMenuItem(value: a, child: Text('📅 Año $a', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
                                                ],
                                                onChanged: (v) => setState(() => _anioFiltroHistMision = v),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.only(left: 4, bottom: 3),
                                            child: Text('Filtro Mes', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                                          ),
                                          Container(
                                            height: 40,
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                                            child: DropdownButtonHideUnderline(
                                              child: DropdownButton<int?>(
                                                isExpanded: true,
                                                dropdownColor: const Color(0xFF2C2C2C),
                                                value: _mesFiltroHistMision,
                                                items: [
                                                  const DropdownMenuItem(value: null, child: Text('Mes: Últimos 3 meses', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                                                  ..._nombresMesesMision.entries.map((e) => DropdownMenuItem(value: e.key, child: Text('📅 ${e.value}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
                                                ],
                                                onChanged: (v) => setState(() {
                                                  _mesFiltroHistMision = v;
                                                  if (v == null) _semanaFiltroHistMision = null;
                                                }),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                const Padding(
                                  padding: EdgeInsets.only(left: 4, bottom: 3),
                                  child: Text('Filtro Semana del Mes', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                                ),
                                Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int?>(
                                      isExpanded: true,
                                      dropdownColor: const Color(0xFF2C2C2C),
                                      value: _semanaFiltroHistMision,
                                      items: const [
                                        DropdownMenuItem(value: null, child: Text('Semana: Todas las semanas del mes', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                                        DropdownMenuItem(value: 1, child: Text('Semana 1 (Días 1 al 7)', style: TextStyle(fontSize: 12))),
                                        DropdownMenuItem(value: 2, child: Text('Semana 2 (Días 8 al 14)', style: TextStyle(fontSize: 12))),
                                        DropdownMenuItem(value: 3, child: Text('Semana 3 (Días 15 al 21)', style: TextStyle(fontSize: 12))),
                                        DropdownMenuItem(value: 4, child: Text('Semana 4 (Días 22 al 28)', style: TextStyle(fontSize: 12))),
                                        DropdownMenuItem(value: 5, child: Text('Semana 5 (Días 29 al 31)', style: TextStyle(fontSize: 12))),
                                      ],
                                      onChanged: (v) => setState(() => _semanaFiltroHistMision = v),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                              ],
                              TextField(
                                controller: _busquedaMisionCtrl,
                                decoration: InputDecoration(
                                  hintText: '💬 Buscar SKU, UPC o frase IA (ej. "bodega enero", "< 15 dias")...',
                                  hintStyle: const TextStyle(fontSize: 11, color: Colors.white54),
                                  prefixIcon: const Icon(Icons.search, color: Colors.amber, size: 18),
                                  suffixIcon: _busquedaMision.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 16, color: Colors.white54),
                                          onPressed: () {
                                            _busquedaMisionCtrl.clear();
                                            setState(() => _busquedaMision = '');
                                          },
                                        )
                                      : null,
                                  filled: true,
                                  fillColor: Colors.white10,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                ),
                                onChanged: (val) => setState(() => _busquedaMision = val),
                              ),
                              const SizedBox(height: 6),
                              // RENGLÓN 1: TIPO DE MISIÓN (100% ANCHO)
                              const Padding(
                                padding: EdgeInsets.only(left: 4, bottom: 3),
                                child: Text('Filtro Tipo de Misión', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                              ),
                              Container(
                                height: 42,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _filtroTipoMision != null ? Colors.amber : Colors.white12),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int?>(
                                    isExpanded: true,
                                    dropdownColor: const Color(0xFF2C2C2C),
                                    value: _filtroTipoMision,
                                    hint: const Text('Tipo de Misión', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                    items: const [
                                      DropdownMenuItem(value: null, child: Text('📋 Tipo: Todas las Misiones', style: TextStyle(fontSize: 12, color: Colors.amberAccent, fontWeight: FontWeight.bold))),
                                      DropdownMenuItem(value: 0, child: Text('🛒 Carrito Abandonado', style: TextStyle(fontSize: 12, color: Colors.deepOrangeAccent, fontWeight: FontWeight.bold))),
                                      DropdownMenuItem(value: 1, child: Text('🔥 Crítico ≤ 15 Días (Reactivación)', style: TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold))),
                                      DropdownMenuItem(value: 2, child: Text('🚨 Política Bodega (90 Días)', style: TextStyle(fontSize: 12, color: Colors.pinkAccent, fontWeight: FontWeight.bold))),
                                      DropdownMenuItem(value: 3, child: Text('⚠️ Caducidad Cercana (45 Días)', style: TextStyle(fontSize: 12, color: Colors.orangeAccent, fontWeight: FontWeight.bold))),
                                      DropdownMenuItem(value: 4, child: Text('🛒 Descontar Venta (SAP)', style: TextStyle(fontSize: 12, color: Colors.blueAccent, fontWeight: FontWeight.bold))),
                                      DropdownMenuItem(value: 5, child: Text('🔎 Validar Artículo Nuevo (Sin Match)', style: TextStyle(fontSize: 12, color: Colors.purpleAccent, fontWeight: FontWeight.bold))),
                                    ],
                                    onChanged: (v) => setState(() => _filtroTipoMision = v),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              // RENGLÓN 2: PROVEEDOR (100% ANCHO)
                              const Padding(
                                padding: EdgeInsets.only(left: 4, bottom: 3),
                                child: Text('Filtro Proveedor', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                              ),
                              Container(
                                height: 42,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String?>(
                                    isExpanded: true,
                                    dropdownColor: const Color(0xFF2C2C2C),
                                    value: provsDisponibles.contains(_filtroProveedorMision) ? _filtroProveedorMision : null,
                                    hint: const Text('Filtro Proveedor', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                    items: [
                                      const DropdownMenuItem(value: null, child: Text('Proveedor: Todos los Proveedores', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                                      ...provsDisponibles.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))),
                                    ],
                                    onChanged: (v) => setState(() => _filtroProveedorMision = v),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              // RENGLÓN 3: UBICACIÓN / MUEBLE JERÁRQUICO (100% ANCHO)
                              const Padding(
                                padding: EdgeInsets.only(left: 4, bottom: 3),
                                child: Text('Filtro Ubicación / Mueble (Desplegable por Nivel)', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                              ),
                              SelectorJerarquicoUbicacion(
                                todasLasRutas: mueblesDisponibles,
                                rutaSeleccionada: _filtroMuebleMision,
                                permitirSeleccionParcial: true,
                                textoRaizVacio: '📍 Mueble: Mostrar Todo (PISO / BODEGA / DISPLAY)',
                                conteoLotesPorRuta: conteoPorUbicacionMision,
                                onRutaCambiada: (v) => setState(() => _filtroMuebleMision = v),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  if (hayFiltrosActivos) ...[
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.redAccent,
                                          side: const BorderSide(color: Colors.redAccent),
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                        ),
                                        icon: const Icon(Icons.filter_alt_off, size: 16),
                                        label: const Text('Limpiar Filtros', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        onPressed: () => setState(() {
                                          _filtroProveedorMision = null;
                                          _filtroMuebleMision = null;
                                          _filtroTipoMision = null;
                                          _anioFiltroHistMision = hoy.year;
                                          _mesFiltroHistMision = hoy.month;
                                          _semanaFiltroHistMision = null;
                                        }),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    flex: 2,
                                    child: InkWell(
                                      onTap: () => setState(() => _filtrosOcultosMisiones = true),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: Colors.amber.withOpacity(0.4)),
                                        ),
                                        child: const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.keyboard_arrow_up_rounded, color: Colors.amber, size: 18),
                                            SizedBox(width: 4),
                                            Text('Subir / Ocultar Filtros', style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: lista.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      hayFiltrosActivos
                                          ? 'No hay misiones que coincidan con este filtro.'
                                          : (_verHistorial ? 'Aún no hay misiones en el historial de este periodo.' : '¡Piso Limpio!\nSin misiones pendientes.'),
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                                      textAlign: TextAlign.center,
                                    ),
                                    if (hayFiltrosActivos) ...[
                                      const SizedBox(height: 14),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                                        icon: const Icon(Icons.filter_alt_off, size: 18),
                                        label: const Text('MOSTRAR TODAS', style: TextStyle(fontWeight: FontWeight.bold)),
                                        onPressed: () => setState(() {
                                          _filtroProveedorMision = null;
                                          _filtroMuebleMision = null;
                                          _filtroTipoMision = null;
                                          _anioFiltroHistMision = null;
                                          _mesFiltroHistMision = null;
                                          _semanaFiltroHistMision = null;
                                        }),
                                      ),
                                    ],
                                  ],
                                ),
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: lista.length,
                                itemBuilder: (context, i) {
                                  var docMision = lista[i];
                                  var m = docMision.data() as Map<String, dynamic>;
                                  int prioridad = _getPriority(m);
                                  int? cantidad = m['cantidad'] ?? m['descontado'];
                                  DateTime? cad = (m['fechaCaducidad'] as Timestamp?)?.toDate();

                                  Color borderColor = _verHistorial
                                      ? Colors.green
                                      : (prioridad <= 1 ? Colors.redAccent : (prioridad == 2 ? Colors.pinkAccent : (prioridad == 3 ? Colors.orangeAccent : (prioridad == 4 ? Colors.blueAccent : Colors.purpleAccent))));

                                  return Card(
                                    color: Colors.white10,
                                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    clipBehavior: Clip.antiAlias,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: borderColor, width: 2)),
                                    child: Column(
                                      children: [
                            _buildHeader(prioridad, _verHistorial),
                            ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              onTap: _verHistorial ? () => _dialogoDeshacerMision(docMision) : () => _ejecutarAccionMision(docMision, prioridad),
                              onLongPress: _verHistorial ? () => _dialogoDeshacerMision(docMision) : () => _ejecutarAccionMision(docMision, prioridad),
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m['descripcion'] ?? m['sku'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  Text('SKU: ${m['sku'] ?? 'ND'} • Prov: ${m['nombreProveedor'] ?? 'ND'}', style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                                  Text('UPC: ${JerarquiaUbicacionHelper.obtenerUpcVisual(m)}', style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 6),
                                  Text('📍 Ubicación: ${JerarquiaUbicacionHelper.formatearRutaVisual(m['ubicacion']?.toString())} • 📦 Piezas: ${cantidad ?? 1}', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                                  if (m['otrasUbicaciones'] != null && (m['otrasUbicaciones'] as List).isNotEmpty)
                                    Text('🔀 También en: ${(m['otrasUbicaciones'] as List).join(', ')}', style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                                  if (cad != null) Text('📅 Caducidad: ${cad.day}/${cad.month}/${cad.year}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  if (m['comentarioCorporativo'] != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3, bottom: 2),
                                      child: Text('🏢 INSTRUCCIÓN (${m['autorComentarioCorp'] ?? 'CORP'}): ${m['comentarioCorporativo']}', style: const TextStyle(color: Colors.pinkAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ),
                                  if (m['mensaje'] != null) Text(m['mensaje'], style: TextStyle(color: borderColor, fontSize: 11, fontStyle: FontStyle.italic)),
                                  if (_verHistorial && m['completadaPor'] != null) Text('👤 Cerrada por: ${m['completadaPor']}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                ],
                              ),
                              trailing: _verHistorial
                                  ? IconButton(
                                      icon: const Icon(Icons.undo, color: Colors.orangeAccent, size: 30),
                                      tooltip: 'Deshacer / Restaurar',
                                      onPressed: () => _dialogoDeshacerMision(docMision),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.play_circle_fill, color: Colors.greenAccent, size: 34),
                                      tooltip: 'Procesar misión',
                                      onPressed: () => _ejecutarAccionMision(docMision, prioridad),
                                    ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
            ),
          ),
        ],
      ),
    );
  }
}
