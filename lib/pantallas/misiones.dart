import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'trasvase_pantallas.dart';
import 'finanzas.dart';

class PantallaMisiones extends StatefulWidget {
  final String idTiendaGlobal;
  final String usuarioActual;
  const PantallaMisiones({super.key, required this.idTiendaGlobal, required this.usuarioActual});

  @override
  State<PantallaMisiones> createState() => _PantallaMisionesState();
}

class _PantallaMisionesState extends State<PantallaMisiones> {
  bool _actualizando = false;
  bool _verHistorial = false;
  static const String kUbicacionTransito = 'EN TRÁNSITO';

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
    return 5;
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
                    batch.update(docInv.reference, {'enPromocion': true, 'piezasEnPromocion': cantATratar});
                  } else {
                    if (cantATratar == cantOriginal) batch.delete(docInv.reference);
                    else batch.update(docInv.reference, {'cantidad': cantOriginal - cantATratar});
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

  void _dialogoAuditoriaVenta(QueryDocumentSnapshot docMision, Map<String, dynamic> m) async {
    int descontado = m['descontado'] ?? 1;
    String ubicacionOriginal = (m['ubicacion'] ?? 'PISO').toString();
    String sku = (m['sku'] ?? '').toString();

    var snapSku = await _refInv.where('sku', isEqualTo: sku).get();
    var docMismoLote = await _buscarLoteInventario(m);

    // Filtrar otros lotes activos del mismo SKU en otras ubicaciones o fechas
    var otrosLotes = snapSku.docs.where((d) {
      if (docMismoLote != null && d.id == docMismoLote.id) return false;
      String u = (d.data()['ubicacion'] ?? '').toString();
      return u != kUbicacionTransito;
    }).toList();

    if (!mounted) return;

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
              const SizedBox(height: 6),
              Text(
                'SAP descontó $descontado pza(s) de $ubicacionOriginal (por ser el lote más próximo a vencer).',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (otrosLotes.isNotEmpty) ...[
                const Divider(color: Colors.white24, height: 20),
                const Text(
                  '🔀 Si el lote en este mueble sigue completo, selecciona de qué otra ubicación tomó el cliente el producto:',
                  style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11),
                ),
                const SizedBox(height: 8),
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
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.cyanAccent),
                      onTap: () async {
                        Navigator.pop(ctx);
                        var batch = FirebaseFirestore.instance.batch();

                        // 1. Devolver las piezas al lote FIFO original que sigue intacto
                        if (docMismoLote != null) {
                          int cantOrig = docMismoLote.data()['cantidad'] ?? 0;
                          batch.update(docMismoLote.reference, {'cantidad': cantOrig + descontado});
                        } else {
                          batch.set(_refInv.doc(), {
                            'sku': sku,
                            'descripcion': m['descripcion'] ?? 'ND',
                            'ubicacion': ubicacionOriginal,
                            'cantidad': descontado,
                            'fechaCaducidad': m['fechaCaducidad'],
                            'nombreProveedor': m['nombreProveedor'] ?? 'ND',
                            'nombreGpoArticulos': m['nombreGpoArticulos'] ?? 'SIN GRUPO',
                            'fechaCaptura': FieldValue.serverTimestamp(),
                            'capturista': widget.usuarioActual,
                          });
                        }

                        // 2. Descontar las piezas de la ubicación alterna real
                        if (cantAlt <= descontado) {
                          batch.delete(docAlt.reference);
                        } else {
                          batch.update(docAlt.reference, {'cantidad': cantAlt - descontado});
                        }

                        // 3. Cerrar misión dejando rastro del cambio de ubicación
                        batch.update(docMision.reference, {
                          'estado': 'completada',
                          'completadaPor': widget.usuarioActual,
                          'ubicacion': '$ubiAlt (Reasignado desde $ubicacionOriginal)',
                        });

                        await batch.commit();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('🔀 Venta reasignada a $ubiAlt y lote restaurado en $ubicacionOriginal'), backgroundColor: Colors.cyan.shade700),
                          );
                        }
                      },
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CERRAR', style: TextStyle(color: Colors.white54))),
          OutlinedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              var batch = FirebaseFirestore.instance.batch();
              if (docMismoLote != null) {
                batch.update(docMismoLote.reference, {'cantidad': (docMismoLote.data()['cantidad'] ?? 0) + descontado});
              } else {
                batch.set(_refInv.doc(), {
                  'sku': sku,
                  'descripcion': m['descripcion'] ?? 'ND',
                  'ubicacion': ubicacionOriginal,
                  'cantidad': descontado,
                  'fechaCaducidad': m['fechaCaducidad'],
                  'nombreProveedor': m['nombreProveedor'] ?? 'ND',
                  'nombreGpoArticulos': m['nombreGpoArticulos'] ?? 'SIN GRUPO',
                  'fechaCaptura': FieldValue.serverTimestamp(),
                  'capturista': widget.usuarioActual,
                });
              }
              batch.update(docMision.reference, {'estado': 'completada', 'completadaPor': widget.usuarioActual});
              await batch.commit();
            },
            child: const Text('SOLO RESTAURAR AQUÍ', style: TextStyle(color: Colors.orangeAccent, fontSize: 11)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
            onPressed: () async {
              Navigator.pop(ctx);
              await docMision.reference.update({'estado': 'completada', 'completadaPor': widget.usuarioActual});
            },
            child: const Text('SÍ SALIÓ DE AQUÍ (OK)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Future<void> _generarMisionesAutomaticas() async {
    setState(() => _actualizando = true);
    try {
      var snapshot = await _refInv.get();
      DateTime hoy = DateTime.now();
      var batch = FirebaseFirestore.instance.batch();
      int misionesNuevas = 0;

      for (var doc in snapshot.docs) {
        var data = doc.data();
        String ubicacion = (data['ubicacion'] ?? '').toString().toUpperCase();

        if (data['fechaCaducidad'] != null) {
          DateTime cad = (data['fechaCaducidad'] as Timestamp).toDate();
          int dias = cad.difference(hoy).inDays;

          // Reactivación crítica a los 15 días (Solo Merma o Devolución)
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
              'fechaGeneracion': FieldValue.serverTimestamp(),
              'mensaje': '🚨 POLÍTICA 90 DÍAS: Extraer de Bodega y reubicar en Piso/Display',
            });
            batch.update(doc.reference, {'misionBodega90d': true});
            misionesNuevas++;
          }
        }
      }
      if (misionesNuevas > 0) await batch.commit();
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
                  var lista = snapshot.data!.docs.where((doc) => (doc.data() as Map<String, dynamic>)['estado'] == estadoBuscado).toList();

                  if (lista.isEmpty) {
                    return Center(
                      child: Text(
                        _verHistorial ? 'Aún no hay misiones en el historial.' : '¡Piso Limpio!\nSin misiones pendientes.',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  lista.sort((a, b) {
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

                  return ListView.builder(
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
                          : (prioridad <= 1 ? Colors.redAccent : (prioridad == 2 ? Colors.pinkAccent : (prioridad == 3 ? Colors.orangeAccent : Colors.blueAccent)));

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
                              title: Text(m['descripcion'] ?? m['sku'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 6),
                                  Text('📍 Ubicación: ${m['ubicacion'] ?? 'ND'} • 📦 Piezas: ${cantidad ?? 1}', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                                  if (m['otrasUbicaciones'] != null && (m['otrasUbicaciones'] as List).isNotEmpty)
                                    Text('🔀 También en: ${(m['otrasUbicaciones'] as List).join(', ')}', style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                                  if (cad != null) Text('📅 Caducidad: ${cad.day}/${cad.month}/${cad.year}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
