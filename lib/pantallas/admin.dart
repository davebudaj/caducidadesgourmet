import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:universal_html/html.dart' as html;
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../modelos/selector_jerarquico_ubicacion.dart';

class PantallaAdmin extends StatefulWidget {
  final String idTiendaGlobal;
  final String nombreTienda;

  const PantallaAdmin({
    super.key,
    required this.idTiendaGlobal,
    required this.nombreTienda
  });

  @override
  State<PantallaAdmin> createState() => _PantallaAdminState();
}

class _PantallaAdminState extends State<PantallaAdmin> {
  final TextEditingController _muebleController = TextEditingController();
  final TextEditingController _numEmpleadoController = TextEditingController();
  final TextEditingController _nombreUsuarioController = TextEditingController();
  
  String _prefijoMueble = 'PISO';
  String _rolSeleccionado = 'piso';
  
  bool _procesando = false;
  String _estado = "Listo para cargar archivos CSV";
  final GlobalKey _qrKey = GlobalKey(); 

  late DocumentReference _refTienda;
  String _ultimaActualizacion = "Buscando...";
  String _ultimaCargaVentas = "Ventas sin cargar";
  String _ultimoBackup = "Sin respaldo reciente";
  final Set<String> _ramasContraidas = {};
  List<String> _rutasConHijosActuales = [];

  @override
  void initState() {
    super.initState();
    _refTienda = FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal);
    _obtenerUltimaActualizacion();
    _obtenerUltimaCargaVentas();
    _obtenerUltimoBackup();
  }

  Future<void> _obtenerUltimaActualizacion() async {
    try {
      var doc = await FirebaseFirestore.instance.collection('sistema').doc('catalogo_metadata').get();
      if (doc.exists) {
        Timestamp? ts = doc.data()?['ultima_carga'];
        if (ts != null) {
          DateTime dt = ts.toDate();
          if(mounted) setState(() => _ultimaActualizacion = 'Última carga: ${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year} a las ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}');
          return;
        }
      }
      if(mounted) setState(() => _ultimaActualizacion = 'Catálogo sin cargar');
    } catch (e) {
      if(mounted) setState(() => _ultimaActualizacion = 'Error al leer fecha');
    }
  }


  Future<void> _obtenerUltimoBackup() async {
    try {
      var doc = await FirebaseFirestore.instance.collection('sistema').doc('backup_metadata').get();
      if (doc.exists) {
        Timestamp? ts = doc.data()?['ultimo_backup'];
        if (ts != null) {
          DateTime dt = ts.toDate();
          if (mounted) {
            setState(() => _ultimoBackup = 'Último backup global: ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}');
          }
          return;
        }
      }
    } catch (_) {}
  }

  dynamic _serializarDato(dynamic valor) {
    if (valor is Timestamp) {
      return {'__tipo__': 'timestamp', 'iso': valor.toDate().toIso8601String()};
    } else if (valor is Map) {
      return valor.map((k, v) => MapEntry(k.toString(), _serializarDato(v)));
    } else if (valor is List) {
      return valor.map((e) => _serializarDato(e)).toList();
    }
    return valor;
  }

  dynamic _deserializarDato(dynamic valor) {
    if (valor is Map) {
      if (valor['__tipo__'] == 'timestamp' && valor['iso'] != null) {
        return Timestamp.fromDate(DateTime.parse(valor['iso'].toString()));
      }
      return valor.map((k, v) => MapEntry(k.toString(), _deserializarDato(v)));
    } else if (valor is List) {
      return valor.map((e) => _deserializarDato(e)).toList();
    }
    return valor;
  }

  Future<void> _exportarBackupJSON() async {
    setState(() {
      _procesando = true;
      _estado = "Empaquetando Backup Multitienda (Todas las sucursales)...";
    });
    try {
      List<String> tiendasIds = [
        'Z9_0012', 'Z9_0014', 'Z9_0019', 'Z9_0021', 'Z9_0075', 'Z9_0076', 'Z9_0079',
        'Z9_0102', 'Z9_0134', 'Z9_0191', 'Z9_0304', 'Z9_0307', 'Z9_0458', 'Z9_0472'
      ];
      List<String> colecciones = [
        'inventario_activo', 'misiones_auditoria', 'historial_tratamientos',
        'ubicaciones', 'colaboradores', 'resumen_financiero'
      ];

      Map<String, dynamic> backupData = {
        'version_esquema': '3.0_multitienda',
        'fecha_exportacion': DateTime.now().toIso8601String(),
        'tiendas': <String, dynamic>{},
      };

      int totalDocumentos = 0;
      var db = FirebaseFirestore.instance;

      for (String idTienda in tiendasIds) {
        Map<String, dynamic> colsTienda = {};
        bool tiendaTieneDatos = false;

        for (String col in colecciones) {
          var snap = await db.collection('tiendas').doc(idTienda).collection(col).get();
          if (snap.docs.isNotEmpty) {
            tiendaTieneDatos = true;
            Map<String, dynamic> docsMap = {};
            for (var doc in snap.docs) {
              docsMap[doc.id] = _serializarDato(doc.data());
              totalDocumentos++;
            }
            colsTienda[col] = docsMap;
          }
        }
        if (tiendaTieneDatos) {
          backupData['tiendas'][idTienda] = colsTienda;
        }
      }

      String jsonStr = const JsonEncoder.withIndent('  ').convert(backupData);
      final bytes = utf8.encode(jsonStr);
      final blob = html.Blob([bytes], 'application/json');
      final url = html.Url.createObjectUrlFromBlob(blob);

      DateTime hoy = DateTime.now();
      String fechaArchivo = "${hoy.year}${hoy.month.toString().padLeft(2, '0')}${hoy.day.toString().padLeft(2, '0')}_${hoy.hour.toString().padLeft(2, '0')}${hoy.minute.toString().padLeft(2, '0')}";
      String nombreArchivo = "Backup_Multitienda_Zona9_$fechaArchivo.json";

      html.AnchorElement(href: url)
        ..setAttribute("download", nombreArchivo)
        ..click();
      html.Url.revokeObjectUrl(url);

      await db.collection('sistema').doc('backup_metadata').set({
        'ultimo_backup': FieldValue.serverTimestamp(),
        'generado_desde': widget.nombreTienda,
      }, SetOptions(merge: true));
      await _obtenerUltimoBackup();

      setState(() {
        _procesando = false;
        _estado = "✅ Backup Multitienda descargado ($totalDocumentos registros protegidos).";
      });
    } catch (e) {
      setState(() {
        _procesando = false;
        _estado = "Error generando backup: $e";
      });
    }
  }

  Future<void> _restaurarBackupJSON() async {
    try {
      FilePickerResult? resultado = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'JSON'],
      );
      if (resultado == null || resultado.files.single.bytes == null) return;

      setState(() {
        _procesando = true;
        _estado = "Restaurando base de datos multitienda...";
      });

      String contenido = utf8.decode(resultado.files.single.bytes!);
      Map<String, dynamic> backupData = jsonDecode(contenido);
      var db = FirebaseFirestore.instance;

      WriteBatch batch = db.batch();
      int opCount = 0;
      int totalRestaurados = 0;

      // Soporta formato Multitienda (v3.0) y formato individual (v2.0)
      Map<String, dynamic> mapaTiendas = {};
      if (backupData.containsKey('tiendas')) {
        mapaTiendas = Map<String, dynamic>.from(backupData['tiendas']);
      } else if (backupData.containsKey('colecciones')) {
        String idT = (backupData['id_tienda_global'] ?? widget.idTiendaGlobal).toString();
        mapaTiendas[idT] = backupData['colecciones'];
      }

      for (var entryTienda in mapaTiendas.entries) {
        String idTienda = entryTienda.key;
        Map<String, dynamic> colecciones = Map<String, dynamic>.from(entryTienda.value);

        for (var entryCol in colecciones.entries) {
          String nombreCol = entryCol.key;
          Map<String, dynamic> docsMap = Map<String, dynamic>.from(entryCol.value);

          for (var docEntry in docsMap.entries) {
            String docId = docEntry.key;
            Map<String, dynamic> docData = Map<String, dynamic>.from(_deserializarDato(docEntry.value));

            batch.set(db.collection('tiendas').doc(idTienda).collection(nombreCol).doc(docId), docData);
            opCount++;
            totalRestaurados++;

            if (opCount >= 400) {
              await batch.commit();
              batch = db.batch();
              opCount = 0;
            }
          }
        }
      }

      if (opCount > 0) {
        await batch.commit();
      }

      setState(() {
        _procesando = false;
        _estado = "✅ Restauración exitosa: $totalRestaurados registros cargados en todas las tiendas.";
      });
    } catch (e) {
      setState(() {
        _procesando = false;
        _estado = "Error al restaurar backup: $e";
      });
    }
  }

  void _solicitarPasswordBackup(String nombreAccion, VoidCallback accionAutorizada) {
    final TextEditingController passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.cyanAccent, width: 1.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.lock_outline, color: Colors.amber, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Autorizar: $nombreAccion',
                style: const TextStyle(color: Colors.amber, fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Contraseña de seguridad',
            hintText: 'Ingresa la clave maestra',
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (val) {
            if (val.trim() == 'ADMIN777') {
              Navigator.pop(ctx);
              accionAutorizada();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('🔒 Contraseña incorrecta. Acceso denegado.'), backgroundColor: Colors.redAccent),
              );
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
            onPressed: () {
              if (passCtrl.text.trim() == 'ADMIN777') {
                Navigator.pop(ctx);
                accionAutorizada();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🔒 Contraseña incorrecta. Acceso denegado.'), backgroundColor: Colors.redAccent),
                );
              }
            },
            child: const Text('CONFIRMAR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<bool> _verificarPermisoAdminCatalogo() async {
    bool autorizado = false;
    final TextEditingController passCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.amber, width: 1.5)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
            SizedBox(width: 8),
            Expanded(child: Text('Catálogo ya actualizado hoy', style: TextStyle(color: Colors.amber, fontSize: 15, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('El Catálogo Maestro Zonal ya fue cargado el día de hoy en esta tienda.', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 12),
            const Text('Para realizar una recarga el mismo día, ingresa la clave maestra de autorización:', style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: passCtrl,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Clave Maestra',
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
            onPressed: () {
              if (passCtrl.text.trim() == 'ADMIN777') {
                autorizado = true;
                Navigator.pop(ctx);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🔒 Clave incorrecta.'), backgroundColor: Colors.redAccent));
              }
            },
            child: const Text('AUTORIZAR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return autorizado;
  }

  void _agregarSubRamaDialog(String rutaPadre, List<String> existentes) {
    final TextEditingController subCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.greenAccent, width: 1.5)),
        title: const Text('🌿 Agregar Sub-nivel / Rama', style: TextStyle(color: Colors.greenAccent, fontSize: 15, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dentro de: $rutaPadre', style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Puedes escribir uno o varios separados por coma (,):', style: TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 8),
            TextField(
              controller: subCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Ej. CARA 1, CARA 2  o  ENTREPAÑO 1, ENTREPAÑO 2',
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
            icon: const Icon(Icons.account_tree, size: 18),
            label: const Text('CREAR RAMA(S)', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              String raw = subCtrl.text.trim().toUpperCase();
              if (raw.isEmpty) return;
              Navigator.pop(ctx);

              List<String> partes = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
              var batch = FirebaseFirestore.instance.batch();
              int creados = 0;

              for (String p in partes) {
                String nuevaRuta = '$rutaPadre > $p';
                if (!existentes.contains(nuevaRuta)) {
                  batch.set(_refTienda.collection('ubicaciones').doc(), {'nombre': nuevaRuta});
                  creados++;
                }
              }
              if (creados > 0) {
                await batch.commit();
                setState(() => _ramasContraidas.remove(rutaPadre));
              }
            },
          ),
        ],
      ),
    );
  }

  void _renombrarUbicacionDialog(QueryDocumentSnapshot docActual, List<QueryDocumentSnapshot> todosDocsUbicaciones) {
    String rutaVieja = docActual['nombre'].toString();
    List<String> niveles = rutaVieja.contains(' > ') ? rutaVieja.split(' > ') : [rutaVieja];
    String nombreNodoActual = niveles.last;
    String prefijoPadre = niveles.length > 1 ? niveles.sublist(0, niveles.length - 1).join(' > ') : '';

    final TextEditingController renameCtrl = TextEditingController(text: nombreNodoActual);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.amber, width: 1.5)),
        title: const Row(
          children: [
            Icon(Icons.edit_location_alt, color: Colors.amber, size: 22),
            SizedBox(width: 8),
            Expanded(child: Text('Renombrar Ubicación', style: TextStyle(color: Colors.amber, fontSize: 15, fontWeight: FontWeight.bold))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (prefijoPadre.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text('Ruta base: ${prefijoPadre.replaceAll(' > ', ' ➔ ')}', style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            const Text('El cambio actualizará este mueble, sus sub-niveles y todos los lotes guardados en él:', style: TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 10),
            TextField(
              controller: renameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nuevo nombre',
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
            icon: const Icon(Icons.save, size: 18),
            label: const Text('GUARDAR CAMBIO', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              String nuevoTexto = renameCtrl.text.trim().toUpperCase();
              if (nuevoTexto.isEmpty) return;
              Navigator.pop(ctx);

              String rutaNueva = prefijoPadre.isNotEmpty ? '$prefijoPadre > $nuevoTexto' : nuevoTexto;
              if (rutaNueva == rutaVieja) return;

              setState(() {
                _procesando = true;
                _estado = 'Actualizando ubicación y migrando lotes vinculados...';
              });

              try {
                String reemplazarPrefijo(String original) {
                  if (original == rutaVieja) return rutaNueva;
                  if (original.startsWith('$rutaVieja > ')) {
                    return '$rutaNueva > ${original.substring(rutaVieja.length + 3)}';
                  }
                  return original;
                }

                WriteBatch batch = FirebaseFirestore.instance.batch();
                int opCount = 0;
                int lotesMigrados = 0;

                Future<void> checkBatch() async {
                  opCount++;
                  if (opCount >= 400) {
                    await batch.commit();
                    batch = FirebaseFirestore.instance.batch();
                    opCount = 0;
                  }
                }

                // 1. Actualizar esta ubicación y sus sub-ramas en 'ubicaciones' (sin duplicar)
                for (var uDoc in todosDocsUbicaciones) {
                  String uNombre = uDoc['nombre'].toString();
                  if (uNombre == rutaVieja || uNombre.startsWith('$rutaVieja > ')) {
                    String uActualizado = reemplazarPrefijo(uNombre);
                    batch.update(uDoc.reference, {'nombre': uActualizado});
                    await checkBatch();
                  }
                }

                // 2. Actualizar lotes en 'inventario_activo' (tanto ubicacion actual como ubicacionOrigen en carrito)
                var invSnap = await _refTienda.collection('inventario_activo').get();
                for (var iDoc in invSnap.docs) {
                  var data = iDoc.data();
                  String ubi = (data['ubicacion'] ?? '').toString();
                  String ubiOrig = (data['ubicacionOrigen'] ?? '').toString();
                  Map<String, dynamic> cambios = {};

                  if (ubi == rutaVieja || ubi.startsWith('$rutaVieja > ')) {
                    cambios['ubicacion'] = reemplazarPrefijo(ubi);
                    lotesMigrados++;
                  }
                  if (ubiOrig == rutaVieja || ubiOrig.startsWith('$rutaVieja > ')) {
                    cambios['ubicacionOrigen'] = reemplazarPrefijo(ubiOrig);
                  }
                  if (cambios.isNotEmpty) {
                    batch.update(iDoc.reference, cambios);
                    await checkBatch();
                  }
                }

                // 3. Actualizar misiones en 'misiones_auditoria'
                var misSnap = await _refTienda.collection('misiones_auditoria').get();
                for (var mDoc in misSnap.docs) {
                  var data = mDoc.data();
                  String ubi = (data['ubicacion'] ?? '').toString();
                  Map<String, dynamic> cambios = {};

                  if (ubi == rutaVieja || ubi.startsWith('$rutaVieja > ')) {
                    cambios['ubicacion'] = reemplazarPrefijo(ubi);
                  }
                  if (data['otrasUbicaciones'] is List) {
                    List<String> listaOtras = (data['otrasUbicaciones'] as List).map((e) => e.toString()).toList();
                    bool cambioEnLista = false;
                    List<String> nuevaLista = listaOtras.map((u) {
                      if (u == rutaVieja || u.startsWith('$rutaVieja > ')) {
                        cambioEnLista = true;
                        return reemplazarPrefijo(u);
                      }
                      return u;
                    }).toList();
                    if (cambioEnLista) cambios['otrasUbicaciones'] = nuevaLista;
                  }
                  if (cambios.isNotEmpty) {
                    batch.update(mDoc.reference, cambios);
                    await checkBatch();
                  }
                }

                // 4. Actualizar registros en 'historial_tratamientos'
                var histSnap = await _refTienda.collection('historial_tratamientos').get();
                for (var hDoc in histSnap.docs) {
                  var data = hDoc.data();
                  String ubi = (data['ubicacion'] ?? '').toString();
                  if (ubi == rutaVieja || ubi.startsWith('$rutaVieja > ')) {
                    batch.update(hDoc.reference, {'ubicacion': reemplazarPrefijo(ubi)});
                    await checkBatch();
                  }
                }

                if (opCount > 0) await batch.commit();

                setState(() {
                  if (_ramasContraidas.contains(rutaVieja)) {
                    _ramasContraidas.remove(rutaVieja);
                    _ramasContraidas.add(rutaNueva);
                  }
                  _procesando = false;
                  _estado = '✅ Ubicación renombrada a "$rutaNueva" ($lotesMigrados lotes sincronizados).';
                });

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Ubicación renombrada y $lotesMigrados lote(s) actualizados sin perder datos.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                setState(() {
                  _procesando = false;
                  _estado = 'Error al renombrar ubicación: $e';
                });
              }
            },
          ),
        ],
      ),
    );
  }

  void _confirmarEliminarRama(QueryDocumentSnapshot docActual, List<QueryDocumentSnapshot> todosDocs) {
    String ruta = docActual['nombre'].toString();
    var subRamas = todosDocs.where((d) => d['nombre'].toString().startsWith('$ruta > ')).toList();

    if (subRamas.isEmpty) {
      docActual.reference.delete();
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('¿Eliminar Ubicación y Sub-niveles?', style: TextStyle(color: Colors.redAccent, fontSize: 15, fontWeight: FontWeight.bold)),
        content: Text('"$ruta" tiene ${subRamas.length} sub-nivel(es) adentro.\n\n¿Deseas eliminar toda la rama completa? (Los productos en inventario no se borrarán).', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              var batch = FirebaseFirestore.instance.batch();
              batch.delete(docActual.reference);
              for (var sub in subRamas) {
                batch.delete(sub.reference);
              }
              await batch.commit();
            },
            child: const Text('ELIMINAR RAMA COMPLETA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Future<void> _obtenerUltimaCargaVentas() async {
    try {
      var doc = await _refTienda.get();
      if (doc.exists) {
        var data = doc.data() as Map<String, dynamic>?;
        Timestamp? ts = data?['ultima_carga_ventas'];
        if (ts != null) {
          DateTime dt = ts.toDate();
          if (mounted) {
            setState(() => _ultimaCargaVentas = 'Última carga: ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} a las ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}');
          }
          return;
        }
      }
      if (mounted) setState(() => _ultimaCargaVentas = 'Ventas sin cargar');
    } catch (_) {}
  }

  void _abrirSelectorImpresionQRs() async {
    var snap = await _refTienda.collection('ubicaciones').get();
    List<String> todas = snap.docs
        .map((d) => d['nombre'].toString())
        .where((n) => n != 'EN TRÁNSITO')
        .toList();

    todas = JerarquiaUbicacionHelper.ordenarRutasPorJerarquia(todas);

    if (!mounted) return;
    Set<String> elegidas = {};
    Set<String> contraidasModal = {};
    String? filtroAreaModal;
    String? ultimaRutaClick;

    // Devuelve las sub-ubicaciones finales (hojas) debajo de una rama padre
    List<String> obtenerHojasDeRama(String rutaPadre) {
      var subRamas = todas.where((otra) => otra.startsWith('$rutaPadre > ')).toList();
      if (subRamas.isEmpty) return [rutaPadre];
      return subRamas.where((s) => !todas.any((otra) => otra.startsWith('$s > '))).toList();
    }

    // Calcula el estado del Checkbox: false (nada), true (todo seleccionado), null (selección parcial [-])
    bool? estadoCheckUbicacion(String u) {
      bool tieneHijos = todas.any((otra) => otra.startsWith('$u > '));
      if (!tieneHijos) {
        return elegidas.contains(u);
      }
      List<String> hojas = obtenerHojasDeRama(u);
      int seleccionados = hojas.where((h) => elegidas.contains(h)).length;
      if (seleccionados == 0 && !elegidas.contains(u)) return false;
      if (seleccionados == hojas.length) return true;
      return null; // Selección parcial [-]
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          List<String> filtradasPorArea = todas.where((u) {
            if (filtroAreaModal == null) return true;
            String raiz = JerarquiaUbicacionHelper.descomponerRuta(u).first.toUpperCase();
            return raiz == filtroAreaModal;
          }).toList();

          List<String> hojasVistaActual = filtradasPorArea
              .where((u) => !todas.any((otra) => otra.startsWith('$u > ')))
              .toList();

          int hojasSeleccionadasEnVista = hojasVistaActual.where((h) => elegidas.contains(h)).length;
          bool? estadoGeneralVista = hojasVistaActual.isEmpty
              ? false
              : (hojasSeleccionadasEnVista == 0
                  ? false
                  : (hojasSeleccionadasEnVista == hojasVistaActual.length ? true : null));

          List<String> visibles = filtradasPorArea.where((u) {
            for (String c in contraidasModal) {
              if (u.startsWith('$c > ')) return false;
            }
            return true;
          }).toList();

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.amber, width: 1.5)),
            title: const Row(
              children: [
                Icon(Icons.print, color: Colors.amber, size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Seleccionar QRs para Imprimir / Descargar',
                    style: TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              height: 440,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                    child: const Row(
                      children: [
                        Icon(Icons.keyboard, size: 16, color: Colors.cyanAccent),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Tip: Usa Shift + Click entre dos ubicaciones para seleccionar todo el rango de golpe.',
                            style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white24)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              isExpanded: true,
                              dropdownColor: const Color(0xFF2C2C2C),
                              value: filtroAreaModal,
                              items: const [
                                DropdownMenuItem(value: null, child: Text('📍 Área: Todas (PISO / BODEGA / DISPLAY)', style: TextStyle(fontSize: 11, color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                                DropdownMenuItem(value: 'PISO', child: Text('🏪 PISO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                DropdownMenuItem(value: 'BODEGA', child: Text('📦 BODEGA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                DropdownMenuItem(value: 'DISPLAY', child: Text('✨ DISPLAY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                              ],
                              onChanged: (val) => setModalState(() {
                                filtroAreaModal = val;
                                ultimaRutaClick = null;
                              }),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TextButton.icon(
                        icon: Icon(contraidasModal.isEmpty ? Icons.unfold_less : Icons.unfold_more, size: 16, color: Colors.amber),
                        label: Text(contraidasModal.isEmpty ? 'Contraer' : 'Expandir', style: const TextStyle(fontSize: 11, color: Colors.amber)),
                        onPressed: () {
                          setModalState(() {
                            if (contraidasModal.isNotEmpty) {
                              contraidasModal.clear();
                            } else {
                              for (String r in todas) {
                                if (todas.any((otra) => otra.startsWith('$r > '))) {
                                  contraidasModal.add(r);
                                }
                              }
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            tristate: true,
                            activeColor: Colors.amber,
                            checkColor: Colors.black,
                            value: estadoGeneralVista,
                            onChanged: (_) {
                              setModalState(() {
                                if (estadoGeneralVista == true) {
                                  elegidas.removeAll(filtradasPorArea);
                                } else {
                                  elegidas.addAll(hojasVistaActual);
                                }
                              });
                            },
                          ),
                          Text('${elegidas.length} seleccionados', style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => setModalState(() => elegidas.removeAll(filtradasPorArea)),
                            child: const Text('Desmarcar vista', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ),
                          TextButton(
                            onPressed: () => setModalState(() => elegidas.addAll(hojasVistaActual)),
                            child: const Text('Seleccionar todos', style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 6),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visibles.length,
                      itemBuilder: (c, i) {
                        String u = visibles[i];
                        List<String> niveles = JerarquiaUbicacionHelper.descomponerRuta(u);
                        int prof = niveles.length >= 2 ? (niveles.length - 2) : 0;
                        bool tieneHijos = todas.any((otra) => otra.startsWith('$u > '));
                        bool estaContraido = contraidasModal.contains(u);
                        bool? estadoActual = estadoCheckUbicacion(u);

                        void toggleConSoporteShift() {
                          bool isShift = HardwareKeyboard.instance.isShiftPressed;
                          bool activar = (estadoActual != true);

                          setModalState(() {
                            if (isShift && ultimaRutaClick != null && visibles.contains(ultimaRutaClick)) {
                              int idxA = visibles.indexOf(ultimaRutaClick!);
                              int idxB = i;
                              int ini = idxA < idxB ? idxA : idxB;
                              int fin = idxA > idxB ? idxA : idxB;
                              for (int k = ini; k <= fin; k++) {
                                String rutaRango = visibles[k];
                                List<String> objetivos = obtenerHojasDeRama(rutaRango);
                                if (activar) {
                                  elegidas.addAll(objetivos);
                                } else {
                                  elegidas.removeAll(objetivos);
                                  elegidas.remove(rutaRango);
                                }
                              }
                            } else {
                              if (tieneHijos) {
                                List<String> hojasHijas = obtenerHojasDeRama(u);
                                if (estadoActual == true) {
                                  elegidas.removeAll(hojasHijas);
                                  elegidas.remove(u);
                                } else {
                                  elegidas.addAll(hojasHijas);
                                }
                              } else {
                                if (estadoActual == true) {
                                  elegidas.remove(u);
                                } else {
                                  elegidas.add(u);
                                }
                              }
                            }
                            ultimaRutaClick = u;
                          });
                        }

                        return Padding(
                          padding: EdgeInsets.only(left: (prof * 16.0).clamp(0.0, 80.0)),
                          child: ListTile(
                            dense: true,
                            visualDensity: const VisualDensity(vertical: -2),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (tieneHijos)
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                    icon: Icon(estaContraido ? Icons.chevron_right : Icons.expand_more, color: Colors.amber, size: 18),
                                    onPressed: () {
                                      setModalState(() {
                                        if (estaContraido) {
                                          contraidasModal.remove(u);
                                        } else {
                                          contraidasModal.add(u);
                                        }
                                      });
                                    },
                                  )
                                else
                                  const SizedBox(width: 24),
                                Checkbox(
                                  tristate: true,
                                  activeColor: Colors.amber,
                                  checkColor: Colors.black,
                                  value: estadoActual,
                                  onChanged: (_) => toggleConSoporteShift(),
                                ),
                              ],
                            ),
                            title: Text(
                              niveles.last,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: tieneHijos ? FontWeight.bold : FontWeight.normal,
                                color: tieneHijos ? Colors.amberAccent : Colors.white,
                              ),
                            ),
                            subtitle: Text(
                              niveles.join(' ➔ '),
                              style: const TextStyle(fontSize: 10, color: Colors.white54),
                            ),
                            onTap: toggleConSoporteShift,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                icon: const Icon(Icons.print, size: 18),
                label: Text('GENERAR PLANTILLA (${elegidas.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: elegidas.isEmpty
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        List<String> ordenadasPorJerarquia = JerarquiaUbicacionHelper.ordenarRutasPorJerarquia(elegidas);
                        _generarPlantillaImprimibleQRs(ordenadasPorJerarquia);
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  void _generarPlantillaImprimibleQRs(List<String> ubicacionesElegidas) {
    StringBuffer tarjetasHtml = StringBuffer();
    for (String u in ubicacionesElegidas) {
      String dataQr = Uri.encodeComponent('LOC:$u');
      String urlQr = 'https://quickchart.io/qr?text=$dataQr&size=240&margin=1';
      tarjetasHtml.writeln('''
        <div class="card">
          <div class="tienda">${widget.nombreTienda}</div>
          <img src="$urlQr" width="165" height="165" alt="QR" />
          <div class="ruta">${JerarquiaUbicacionHelper.descomponerRuta(u).join(' ➔ ')}</div>
        </div>
      ''');
    }

    String documentoHtml = '''
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>Plantilla QRs - ${widget.nombreTienda}</title>
  <style>
    body { font-family: Arial, sans-serif; background: #f4f4f4; margin: 20px; text-align: center; }
    .no-print { margin-bottom: 20px; padding: 12px; background: #1e1e1e; color: white; border-radius: 10px; }
    .btn { background: #ffc107; color: #000; border: none; padding: 10px 22px; font-weight: bold; border-radius: 6px; cursor: pointer; font-size: 14px; }
    .grid { display: flex; flex-wrap: wrap; justify-content: center; gap: 14px; }
    .card { background: white; border: 2px dashed #333; border-radius: 10px; width: 205px; padding: 10px; page-break-inside: avoid; box-sizing: border-box; }
    .tienda { font-size: 10px; color: #666; font-weight: bold; margin-bottom: 4px; letter-spacing: 1px; }
    .ruta { font-size: 12px; font-weight: bold; color: #000; margin-top: 6px; word-wrap: break-word; }
    @media print {
      body { background: white; margin: 0; }
      .no-print { display: none; }
    }
  </style>
</head>
<body>
  <div class="no-print">
    <span style="margin-right: 15px;">Plantilla lista con ${ubicacionesElegidas.length} códigos QR para recortar y pegar</span>
    <button class="btn" onclick="window.print()">🖨️ IMPRIMIR / GUARDAR PDF</button>
  </div>
  <div class="grid">
    ${tarjetasHtml.toString()}
  </div>
</body>
</html>
''';

    final bytes = utf8.encode(documentoHtml);
    final blob = html.Blob([bytes], 'text/html;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.window.open(url, '_blank');
  }

  void _mostrarYDescargarQR(String nombreMueble) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Mueble: $nombreMueble', style: const TextStyle(color: Colors.black), textAlign: TextAlign.center),
        content: RepaintBoundary(
          key: _qrKey,
          child: Container(color: Colors.white, width: 250, height: 250, alignment: Alignment.center, child: QrImageView(data: 'LOC:$nombreMueble', version: QrVersions.auto, size: 200.0, backgroundColor: Colors.white)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CERRAR', style: TextStyle(color: Colors.grey))),
          ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white), icon: const Icon(Icons.download), label: const Text('DESCARGAR PNG'), onPressed: () => _descargarQRComoImagen(nombreMueble))
        ],
      )
    );
  }

  Future<void> _descargarQRComoImagen(String nombre) async {
    try {
      RenderRepaintBoundary boundary = _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();
      final blob = html.Blob([pngBytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)..setAttribute("download", "QR_$nombre.png")..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) { debugPrint("Error descargando QR: $e"); }
  }

  // Sincroniza inventario_activo y misiones_auditoria con un mapa en memoria recién cargado del CSV
  Future<Map<String, int>> _sincronizarInventarioConMapaCatalogo(Map<String, Map<String, dynamic>> mapaCatalogo) async {
    int lotesReparados = 0;
    int lotesOhActualizado = 0;

    Map<String, dynamic>? buscarEnMapa(String codigo) {
      for (String cand in JerarquiaUbicacionHelper.generarVariantesCodigo(codigo)) {
        if (mapaCatalogo.containsKey(cand)) return mapaCatalogo[cand];
      }
      return null;
    }

    var db = FirebaseFirestore.instance;
    WriteBatch batch = db.batch();
    int ops = 0;

    Future<void> commitSiNecesario() async {
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    }

    // 1. Revisar todos los lotes en inventario_activo de esta tienda
    var invSnap = await _refTienda.collection('inventario_activo').get();
    for (var doc in invSnap.docs) {
      var d = doc.data();
      String skuActual = (d['sku'] ?? '').toString().trim();
      String eanActual = (d['ean'] ?? '').toString().trim();
      String descActual = (d['descripcion'] ?? '').toString().trim();

      Map<String, dynamic>? infoMaestra = buscarEnMapa(skuActual);
      if (infoMaestra == null && eanActual.isNotEmpty) {
        infoMaestra = buscarEnMapa(eanActual);
      }

      if (infoMaestra != null) {
        bool eraMissing = descActual == 'Artículo Nuevo' ||
            descActual == 'ARTÍCULO NUEVO / NO EN CATÁLOGO' ||
            descActual == 'Sin Nombre' ||
            (d['nombreProveedor'] ?? 'ND') == 'ND' ||
            skuActual != infoMaestra['sku'];

        batch.update(doc.reference, {
          'sku': infoMaestra['sku'],
          'ean': infoMaestra['ean'],
          'descripcion': infoMaestra['descripcion'],
          'idProveedor': infoMaestra['idProveedor'],
          'nombreProveedor': infoMaestra['nombreProveedor'],
          'idCategoria': infoMaestra['idCategoria'],
          'nombreGpoArticulos': infoMaestra['nombreGpoArticulos'],
          'precioVenta': infoMaestra['precioVenta'],
          'oh': infoMaestra['oh'],
        });
        await commitSiNecesario();

        if (eraMissing) {
          lotesReparados++;
        } else {
          lotesOhActualizado++;
        }
      }
    }

    // 2. Revisar también misiones_auditoria pendientes para que no se queden con el código viejo o como "Artículo Nuevo"
    var misSnap = await _refTienda.collection('misiones_auditoria').where('estado', isEqualTo: 'pendiente').get();
    for (var mDoc in misSnap.docs) {
      var m = mDoc.data();
      String mSku = (m['sku'] ?? '').toString().trim();
      Map<String, dynamic>? infoMaestra = buscarEnMapa(mSku);
      if (infoMaestra != null) {
        batch.update(mDoc.reference, {
          'sku': infoMaestra['sku'],
          'descripcion': infoMaestra['descripcion'],
          'nombreProveedor': infoMaestra['nombreProveedor'],
          'nombreGpoArticulos': infoMaestra['nombreGpoArticulos'],
        });
        await commitSiNecesario();
      }
    }

    if (ops > 0) await batch.commit();
    return {'reparados': lotesReparados, 'actualizados': lotesOhActualizado};
  }

  // Botón rápido para reparar "Artículo Nuevo" consultando directamente la colección maestro_productos actual
  Future<void> _repararArticulosNuevosConBD() async {
    setState(() {
      _procesando = true;
      _estado = 'Buscando match en la Base de Datos para los "Artículo Nuevo"...';
    });

    try {
      var invSnap = await _refTienda.collection('inventario_activo').get();
      var misSnap = await _refTienda.collection('misiones_auditoria').where('estado', isEqualTo: 'pendiente').get();

      var db = FirebaseFirestore.instance;
      WriteBatch batch = db.batch();
      int ops = 0;
      int reparados = 0;
      int sinMatch = 0;

      Future<void> commitSiNecesario() async {
        ops++;
        if (ops >= 400) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      }

      for (var doc in invSnap.docs) {
        var d = doc.data();
        String skuActual = (d['sku'] ?? '').toString().trim();
        String eanActual = (d['ean'] ?? '').toString().trim();
        String descActual = (d['descripcion'] ?? '').toString().trim();
        String provActual = (d['nombreProveedor'] ?? 'ND').toString().trim();

        bool necesitaMatch = descActual == 'Artículo Nuevo' ||
            descActual == 'ARTÍCULO NUEVO / NO EN CATÁLOGO' ||
            descActual == 'Sin Nombre' ||
            provActual == 'ND' ||
            skuActual.length >= 11; // Códigos UPC/EAN guardados como SKU

        if (!necesitaMatch) continue;

        Map<String, dynamic>? master = await JerarquiaUbicacionHelper.buscarProductoMaestro(skuActual);
        if (master == null && eanActual.isNotEmpty) {
          master = await JerarquiaUbicacionHelper.buscarProductoMaestro(eanActual);
        }

        if (master != null && master['sku'] != null && master['sku'].toString().trim().isNotEmpty) {
          batch.update(doc.reference, {
            'sku': master['sku'].toString().trim(),
            'ean': (master['ean'] ?? eanActual).toString().trim(),
            'descripcion': master['descripcion'] ?? descActual,
            'idProveedor': master['idProveedor'],
            'nombreProveedor': master['nombreProveedor'] ?? 'ND',
            'idCategoria': master['idCategoria'],
            'nombreGpoArticulos': master['nombreGpoArticulos'] ?? 'SIN GRUPO',
            'precioVenta': master['precioVenta'] ?? '0',
            'oh': master['oh'] ?? '0',
          });
          await commitSiNecesario();
          reparados++;
        } else {
          sinMatch++;
          bool yaTieneMision = misSnap.docs.any((m) =>
              (m.data()['sku'] ?? '').toString().trim() == skuActual &&
              (m.data()['esArticuloNuevo'] == true || (m.data()['mensaje'] ?? '').toString().contains('ARTÍCULO NUEVO')));
          if (!yaTieneMision) {
            batch.set(_refTienda.collection('misiones_auditoria').doc(), {
              'sku': skuActual,
              'ean': eanActual.isNotEmpty ? eanActual : skuActual,
              'descripcion': 'Artículo Nuevo (Validar UPC / SKU en físico)',
              'ubicacion': d['ubicacion'] ?? 'ND',
              'cantidad': d['cantidad'] ?? 1,
              'fechaCaducidad': d['fechaCaducidad'],
              'nombreProveedor': 'SIN MATCH EN BD',
              'nombreGpoArticulos': 'SIN GRUPO',
              'estado': 'pendiente',
              'esArticuloNuevo': true,
              'fechaGeneracion': FieldValue.serverTimestamp(),
              'mensaje': '🔎 ARTÍCULO NUEVO SIN MATCH: Ir a la ubicación, revisar físicamente el UPC / SKU del lote y editarlo para vincularlo.',
            });
            await commitSiNecesario();
          }
        }
      }

      for (var mDoc in misSnap.docs) {
        var m = mDoc.data();
        String mSku = (m['sku'] ?? '').toString().trim();
        String mDesc = (m['descripcion'] ?? '').toString().trim();
        if (mDesc == 'Artículo Nuevo' || mDesc == 'ARTÍCULO NUEVO / NO EN CATÁLOGO' || mSku.length >= 11) {
          var master = await JerarquiaUbicacionHelper.buscarProductoMaestro(mSku);
          if (master != null && master['sku'] != null) {
            batch.update(mDoc.reference, {
              'sku': master['sku'].toString().trim(),
              'descripcion': master['descripcion'] ?? mDesc,
              'nombreProveedor': master['nombreProveedor'] ?? 'ND',
              'nombreGpoArticulos': master['nombreGpoArticulos'] ?? 'SIN GRUPO',
            });
            await commitSiNecesario();
          }
        }
      }

      if (ops > 0) await batch.commit();

      setState(() {
        _procesando = false;
        _estado = '✅ Match finalizado:\n$reparados lotes "Artículo Nuevo" actualizados con su SKU y Descripción real.\n($sinMatch lotes aún no existen en el Catálogo Maestro).';
      });
    } catch (e) {
      setState(() {
        _procesando = false;
        _estado = 'Error al reparar artículos: $e';
      });
    }
  }

  Future<void> _cargarCatalogoMaestroZona9() async {
    try {
      var metaDoc = await FirebaseFirestore.instance.collection('sistema').doc('catalogo_metadata').get();
      if (metaDoc.exists) {
        Timestamp? ts = metaDoc.data()?['ultima_carga'];
        if (ts != null) {
          DateTime ultimaFecha = ts.toDate();
          DateTime ahora = DateTime.now();
          if (ultimaFecha.year == ahora.year && ultimaFecha.month == ahora.month && ultimaFecha.day == ahora.day) {
            bool ok = await _verificarPermisoAdminCatalogo();
            if (ok == false) return;
          }
        }
      }
    } catch (_) {}
    try {
      FilePickerResult? resultado = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'CSV']);
      if (resultado != null && resultado.files.single.bytes != null) {
        setState(() { _procesando = true; _estado = "Leyendo Catálogo Maestro Zonal (Reto Zona 9)..."; });
        final bytes = resultado.files.single.bytes!;
        
        final csvString = latin1.decode(bytes); 
        List<String> filas = const LineSplitter().convert(csvString);
        RegExp separador = RegExp(r',(?=(?:[^"]*"[^"]*")*[^"]*$)');
        
        if (filas.length < 8) {
          setState(() { _procesando = false; _estado = "Error: El archivo no parece ser 'Reto Zona 9'. Faltan filas."; });
          return;
        }

        List<String> codigosCentro = filas[5].split(separador).map((e) => e.replaceAll('"', '').trim()).toList();
        String idTiendaLocal = widget.idTiendaGlobal.split('_').last; 
        int columnaTienda = -1;
        
        for (int j = 10; j < codigosCentro.length; j++) {
           if (codigosCentro[j] == idTiendaLocal) {
              columnaTienda = j;
              break;
           }
        }

        if (columnaTienda == -1) {
           setState(() { _procesando = false; _estado = "Error: No se encontró la tienda $idTiendaLocal en el archivo de la Zona."; });
           return;
        }

        var db = FirebaseFirestore.instance;
        WriteBatch lote = db.batch(); 
        int contadorSubidas = 0; int operacionesEnLote = 0;
        Map<String, Map<String, dynamic>> mapaCatalogoLocal = {};

        for (var i = 7; i < filas.length; i++) {
          if (filas[i].trim().isEmpty) continue;
          List<String> columnas = filas[i].split(separador);
          
          if (columnas.length > columnaTienda) { 
            String provId = columnas[1].replaceAll('"', '').trim();
            String provNombre = columnas[2].replaceAll('"', '').trim();
            String gpoId = columnas[3].replaceAll('"', '').trim();
            String gpoNombre = columnas[4].replaceAll('"', '').trim();
            String ean = columnas[6].replaceAll('"', '').trim();
            String sku = columnas[7].replaceAll('"', '').trim();
            String desc = columnas[8].replaceAll('"', '').trim();
            String precio = columnas[9].replaceAll('"', '').trim();
            String oh = columnas[columnaTienda].replaceAll('"', '').trim();

            Map<String, dynamic> dataProducto = {
              'idProveedor': provId,
              'nombreProveedor': provNombre,
              'idCategoria': gpoId,
              'nombreGpoArticulos': gpoNombre,
              'sku': sku, 
              'ean': ean, 
              'descripcion': desc,
              'precioVenta': precio, 
              'oh': oh 
            };
            
            if (ean.isNotEmpty && ean != "0" && ean != "NaN") { 
               lote.set(db.collection('maestro_productos').doc(ean), dataProducto); 
               operacionesEnLote++; contadorSubidas++;
               for (String v in JerarquiaUbicacionHelper.generarVariantesCodigo(ean)) {
                 mapaCatalogoLocal[v] = dataProducto;
               }
            }
            if (sku.isNotEmpty && sku != "NaN") { 
               lote.set(db.collection('maestro_productos').doc(sku), dataProducto); 
               operacionesEnLote++; contadorSubidas++;
               for (String v in JerarquiaUbicacionHelper.generarVariantesCodigo(sku)) {
                 mapaCatalogoLocal[v] = dataProducto;
               }
            }
            
            if (operacionesEnLote >= 450) { await lote.commit(); lote = db.batch(); operacionesEnLote = 0; }
          }
        }
        
        if (operacionesEnLote > 0) { await lote.commit(); }

        setState(() {
          _estado = "Catálogo subido. Haciendo Match automático con 'Artículo Nuevo' y actualizando OH en Sábana...";
        });

        Map<String, int> syncRes = await _sincronizarInventarioConMapaCatalogo(mapaCatalogoLocal);
        
        await FirebaseFirestore.instance.collection('sistema').doc('catalogo_metadata').set({
          'ultima_carga': FieldValue.serverTimestamp(),
          'usuario_carga': widget.nombreTienda
        });
        await _obtenerUltimaActualizacion();

        setState(() {
          _procesando = false;
          _estado = "¡Catálogo Actualizado Exitosamente!\nSe mapearon $contadorSubidas SKUs.\n🔄 Match automático en Sábana: ${syncRes['reparados']} 'Artículo Nuevo' reparados y ${syncRes['actualizados']} lotes con OH actualizado.";
        });
      }
    } catch (e) { setState(() { _procesando = false; _estado = "Error en Catálogo:\n$e"; }); }
  }

  Future<void> _cargarVentasDiariasCSV() async {
    try {
      FilePickerResult? resultado = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'CSV']);
      if (resultado != null && resultado.files.single.bytes != null) {
        setState(() { _procesando = true; _estado = "Calculando FIFO y deduciendo ventas en piso..."; });
        final bytes = resultado.files.single.bytes!;
        
        final csvString = utf8.decode(bytes, allowMalformed: true); 
        List<String> filas = const LineSplitter().convert(csvString);
        RegExp separador = RegExp(r',(?=(?:[^"]*"[^"]*")*[^"]*$)');
        
        Map<String, int> ventasProcesadas = {};

        for (var i = 3; i < filas.length; i++) {
          if (filas[i].trim().isEmpty) continue;
          List<String> columnas = filas[i].split(separador);
          if (columnas.length >= 2) {
            String sku = columnas[0].replaceAll('"', '').trim();
            int cantVendida = int.tryParse(columnas[1].replaceAll('"', '').trim()) ?? 0;
            
            if (sku.isNotEmpty && cantVendida > 0) {
              ventasProcesadas[sku] = (ventasProcesadas[sku] ?? 0) + cantVendida;
            }
          }
        }

        int misionesNuevas = 0;
        int misionesActualizadas = 0;

        for (var sku in ventasProcesadas.keys) {
          int porDescontar = ventasProcesadas[sku]!;
          
          var querySnap = await _refTienda.collection('inventario_activo').where('sku', isEqualTo: sku).get();
          
          var docsOrdenados = querySnap.docs.toList();
          docsOrdenados.sort((a, b) {
            var dataA = a.data() as Map<String, dynamic>;
            var dataB = b.data() as Map<String, dynamic>;
            
            String ubiA = (dataA['ubicacion'] ?? '').toString().toUpperCase();
            String ubiB = (dataB['ubicacion'] ?? '').toString().toUpperCase();
            
            int prioA = ubiA.contains('BODEGA') ? 1 : 0;
            int prioB = ubiB.contains('BODEGA') ? 1 : 0;
            if (prioA != prioB) return prioA.compareTo(prioB); 
            
            Timestamp tA = dataA['fechaCaducidad'] ?? Timestamp.now();
            Timestamp tB = dataB['fechaCaducidad'] ?? Timestamp.now();
            return tA.compareTo(tB);
          });

          for (var doc in docsOrdenados) {
            if (porDescontar <= 0) break;
            var data = doc.data() as Map<String, dynamic>;
            int cantActual = data['cantidad'] ?? 0;
            int descAqui = (cantActual <= porDescontar) ? cantActual : porDescontar;
            porDescontar -= descAqui;

            if (cantActual <= descAqui) await doc.reference.delete(); 
            else await doc.reference.update({'cantidad': cantActual - descAqui});

            if (descAqui > 0) {
              var misionesP = await _refTienda.collection('misiones_auditoria')
                  .where('estado', isEqualTo: 'pendiente')
                  .where('sku', isEqualTo: sku)
                  .get();
                  
              var misionMatchea = misionesP.docs.where((m) {
                  var md = m.data();
                  return md['ubicacion'] == data['ubicacion'] && md['fechaCaducidad'] == data['fechaCaducidad'] && md['descontado'] != null; 
              }).toList();

              if (misionMatchea.isNotEmpty) {
                  var docMision = misionMatchea.first;
                  int descAnterior = docMision['descontado'] ?? 0;
                  await docMision.reference.update({
                      'descontado': descAnterior + descAqui,
                      'fechaGeneracion': FieldValue.serverTimestamp()
                  });
                  misionesActualizadas++;
              } else {
                  List<String> otrasUbis = docsOrdenados
                      .map((d) => ((d.data() as Map<String, dynamic>)['ubicacion'] ?? '').toString())
                      .where((u) => u.isNotEmpty && u != (data['ubicacion'] ?? ''))
                      .toSet()
                      .toList();
                  await _refTienda.collection('misiones_auditoria').add({
                    'sku': sku, 'descripcion': data['descripcion'] ?? 'ND', 'ubicacion': data['ubicacion'] ?? 'ND',
                    'descontado': descAqui, 'fechaCaducidad': data['fechaCaducidad'], 'estado': 'pendiente',
                    'nombreProveedor': data['nombreProveedor'] ?? 'ND', 'nombreGpoArticulos': data['nombreGpoArticulos'] ?? 'SIN GRUPO',
                    'otrasUbicaciones': otrasUbis,
                    if (data['comentarioCorporativo'] != null) 'comentarioCorporativo': data['comentarioCorporativo'],
                    'fechaGeneracion': FieldValue.serverTimestamp(),
                  });
                  misionesNuevas++;
              }
            }
          }
        }
        await _refTienda.set({'ultima_carga_ventas': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        await _obtenerUltimaCargaVentas();
        setState(() { _procesando = false; _estado = "¡Cierre de Ventas Exitoso!\nMisiones Nuevas: $misionesNuevas | Actualizadas: $misionesActualizadas"; });
      }
    } catch (e) { setState(() { _procesando = false; _estado = "Error en ventas:\n$e"; }); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Centro de Mando', style: TextStyle(fontSize: 16)), 
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 10)), 
              icon: const Icon(Icons.cloud_download, size: 16), 
              label: const Text('SAP BD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)), 
              onPressed: () { html.window.open('https://sapbjp00db.liverpool.com.mx/irj/servlet/prt/portal/prtroot/pcd!3aportal_content!2fcom.sap.pct!2fplatform_add_ons!2fcom.sap.ip.bi!2fiViews!2fcom.sap.ip.bi.bex?BOOKMARK=1TUPM9LFHL4Q72F5HJMJUSXNP', '_blank'); } 
            )
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8.0, bottom: 8.0, right: 8.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 10)), 
              icon: const Icon(Icons.point_of_sale, size: 16), 
              label: const Text('SAP VENTAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)), 
              onPressed: () { html.window.open('https://sapbjp00db.liverpool.com.mx/irj/servlet/prt/portal/prtroot/pcd!3aportal_content!2fcom.sap.pct!2fplatform_add_ons!2fcom.sap.ip.bi!2fiViews!2fcom.sap.ip.bi.bex?BOOKMARK=1TUPM9LFHL4Q6ZPPKLHHU0M3N', '_blank'); } 
            )
          )
        ]
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(_estado, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.amber)),
              const SizedBox(height: 20),
              if (_procesando) const CircularProgressIndicator(color: Colors.amber) else Column(children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    children: [
                      SizedBox(height: 50, width: double.infinity, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, foregroundColor: Colors.white), icon: const Icon(Icons.upload_file), label: const Text('1. SUBIR CATÁLOGO ZONAL'), onPressed: _cargarCatalogoMaestroZona9)),
                      const SizedBox(height: 5),
                      Text(_ultimaActualizacion, style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 40,
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.cyanAccent,
                            side: const BorderSide(color: Colors.cyanAccent),
                          ),
                          icon: const Icon(Icons.auto_fix_high, size: 18),
                          label: const Text('REPARAR "ARTÍCULO NUEVO" (HACER MATCH CON BD)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          onPressed: _repararArticulosNuevosConBD,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                Column(
                  children: [
                    SizedBox(height: 50, width: double.infinity, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black), icon: const Icon(Icons.point_of_sale), label: const Text('2. SUBIR VENTAS DEL DÍA'), onPressed: _cargarVentasDiariasCSV)),
                    const SizedBox(height: 5),
                    Text(_ultimaCargaVentas, style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
                  ),
                  child: Column(
                    children: [
                      const Text('Bóveda de Respaldo y Migración', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(_ultimoBackup, style: const TextStyle(color: Colors.white70, fontSize: 11, fontStyle: FontStyle.italic)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 12)),
                              icon: const Icon(Icons.download_for_offline, size: 18),
                              label: const Text('DESCARGAR BACKUP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                              onPressed: () => _solicitarPasswordBackup('Descargar Backup', _exportarBackupJSON),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.amberAccent, side: const BorderSide(color: Colors.amberAccent), padding: const EdgeInsets.symmetric(vertical: 12)),
                              icon: const Icon(Icons.restore_page, size: 18),
                              label: const Text('RESTAURAR / MIGRAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                              onPressed: () => _solicitarPasswordBackup('Restaurar / Migrar', _restaurarBackupJSON),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 40),
              const Divider(color: Colors.white24),
              const SizedBox(height: 20),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text('Arquitectura de Ubicaciones (Árbol de Muebles)', style: TextStyle(fontSize: 16, color: Colors.amber, fontWeight: FontWeight.bold)),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    icon: const Icon(Icons.print, size: 16),
                    label: const Text('Imprimir QRs', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: _abrirSelectorImpresionQRs,
                  ),
                  const SizedBox(width: 6),
                  TextButton.icon(
                    icon: Icon(_ramasContraidas.isEmpty ? Icons.unfold_less : Icons.unfold_more, color: Colors.cyanAccent, size: 16),
                    label: Text(_ramasContraidas.isEmpty ? 'Contraer a 1er Nivel' : 'Expandir Todo', style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      setState(() {
                        if (_ramasContraidas.isNotEmpty) {
                          _ramasContraidas.clear();
                        } else {
                          _ramasContraidas.addAll(_rutasConHijosActuales);
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Crea un mueble base y toca el botón [+] verde de cualquier fila para ramificar (Caras, Niveles, Entrepaños, Divisiones). Puedes separar varios con comas (,).',
                style: TextStyle(color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Row(children: [
                Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.withOpacity(0.4))),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      dropdownColor: const Color(0xFF2C2C2C),
                      value: _prefijoMueble,
                      items: ['PISO', 'BODEGA', 'DISPLAY'].map((String val) => DropdownMenuItem(value: val, child: Text(val, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)))).toList(),
                      onChanged: (val) => setState(() => _prefijoMueble = val!),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _muebleController,
                    decoration: InputDecoration(
                      hintText: 'Ej. MESA TE, GONDOLA 1 (separa con coma)',
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    if (_muebleController.text.trim().isNotEmpty) {
                      List<String> nuevos = _muebleController.text.toUpperCase().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                      var batch = FirebaseFirestore.instance.batch();
                      for (String n in nuevos) {
                        String nombreFinal = '$_prefijoMueble > $n';
                        batch.set(_refTienda.collection('ubicaciones').doc(), {'nombre': nombreFinal});
                      }
                      await batch.commit();
                      _muebleController.clear();
                    }
                  },
                  child: const Icon(Icons.add),
                ),
              ]),
              const SizedBox(height: 15),
              Container(
                height: 360,
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white12)),
                child: StreamBuilder<QuerySnapshot>(
                  stream: _refTienda.collection('ubicaciones').orderBy('nombre').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    var docs = snapshot.data!.docs;
                    List<String> todasRutas = docs.map((d) => d['nombre'].toString()).toList();

                    _rutasConHijosActuales = todasRutas
                        .where((r) => todasRutas.any((otra) => otra.startsWith('$r > ')))
                        .toList();

                    // Mostrar siempre las ubicaciones de 1er nivel; ocultar solo sub-niveles cuyo padre esté contraído
                    var docsVisibles = docs.where((doc) {
                      String ruta = doc['nombre'].toString();
                      for (String contraida in _ramasContraidas) {
                        if (ruta.startsWith('$contraida > ')) return false;
                      }
                      return true;
                    }).toList();

                    if (docs.isEmpty) {
                      return const Center(child: Text('Aún no hay muebles registrados en esta tienda.', style: TextStyle(color: Colors.white54)));
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      itemCount: docsVisibles.length,
                      itemBuilder: (context, index) {
                        var doc = docsVisibles[index];
                        String ruta = doc['nombre'].toString();
                        List<String> niveles = ruta.contains(' > ') ? ruta.split(' > ') : [ruta];
                        int profundidad = niveles.length >= 2 ? (niveles.length - 2) : 0;
                        String nombreCorto = niveles.last;
                        String areaRaiz = niveles.first.toUpperCase();

                        bool tieneHijos = todasRutas.any((r) => r.startsWith('$ruta > '));
                        bool estaContraido = _ramasContraidas.contains(ruta);

                        Color colorRaiz = Colors.amber;
                        IconData iconoRaiz = Icons.storefront;
                        if (areaRaiz.contains('BODEGA')) {
                          colorRaiz = Colors.pinkAccent;
                          iconoRaiz = Icons.inventory_2;
                        } else if (areaRaiz.contains('DISPLAY')) {
                          colorRaiz = Colors.cyanAccent;
                          iconoRaiz = Icons.auto_awesome;
                        }

                        return Container(
                          margin: EdgeInsets.only(left: (profundidad * 18.0).clamp(0.0, 90.0), top: 3, bottom: 3),
                          decoration: BoxDecoration(
                            color: tieneHijos ? Colors.white.withOpacity(0.07) : Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(10),
                            border: Border(left: BorderSide(color: colorRaiz, width: tieneHijos ? 3.5 : 1.5)),
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            onTap: tieneHijos
                                ? () {
                                    setState(() {
                                      if (estaContraido) {
                                        _ramasContraidas.remove(ruta);
                                      } else {
                                        _ramasContraidas.add(ruta);
                                      }
                                    });
                                  }
                                : null,
                            onLongPress: () => _renombrarUbicacionDialog(doc, docs),
                            leading: InkWell(
                              onTap: tieneHijos
                                  ? () {
                                      setState(() {
                                        if (estaContraido) {
                                          _ramasContraidas.remove(ruta);
                                        } else {
                                          _ramasContraidas.add(ruta);
                                        }
                                      });
                                    }
                                  : null,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (tieneHijos)
                                    Icon(estaContraido ? Icons.chevron_right : Icons.expand_more, color: Colors.amber, size: 20)
                                  else
                                    const SizedBox(width: 20),
                                  Icon(profundidad == 0 ? iconoRaiz : Icons.subdirectory_arrow_right, color: colorRaiz, size: 18),
                                ],
                              ),
                            ),
                            title: Text(
                              nombreCorto,
                              style: TextStyle(
                                fontWeight: tieneHijos ? FontWeight.bold : FontWeight.w500,
                                fontSize: 13,
                                color: tieneHijos ? Colors.white : Colors.white70,
                              ),
                            ),
                            subtitle: Text(
                              ruta.replaceAll(' > ', ' ➔ '),
                              style: TextStyle(fontSize: 10, color: colorRaiz.withOpacity(0.8)),
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent, size: 20),
                                  tooltip: 'Agregar Sub-nivel (Cara, Nivel, Entrepaño...)',
                                  onPressed: () => _agregarSubRamaDialog(ruta, todasRutas),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.qr_code, color: Colors.blueAccent, size: 20),
                                  tooltip: 'Descargar QR de esta ubicación',
                                  onPressed: () => _mostrarYDescargarQR(ruta),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                  tooltip: 'Eliminar ubicación',
                                  onPressed: () => _confirmarEliminarRama(doc, docs),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 40),
              const Divider(color: Colors.white24),
              const SizedBox(height: 20),

                            Text('Gestión de Usuarios (${widget.nombreTienda})', style: const TextStyle(fontSize: 18, color: Colors.amber)),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(flex: 1, child: TextField(controller: _numEmpleadoController, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: '# Empleado', filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)))),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: TextField(controller: _nombreUsuarioController, decoration: InputDecoration(hintText: 'Nombre y Apellido', filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)))),
                ]
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _rolSeleccionado,
                      decoration: InputDecoration(filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                      dropdownColor: const Color(0xFF2C2C2C),
                      items: const [
                        DropdownMenuItem(value: 'director', child: Text('Director')),
                        DropdownMenuItem(value: 'gerente', child: Text('Gerente')),
                        DropdownMenuItem(value: 'jefe', child: Text('Jefe / Administrador')),
                        DropdownMenuItem(value: 'piso', child: Text('Colaborador (Piso)')),
                      ],
                      onChanged: (val) => setState(() => _rolSeleccionado = val!),
                    )
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () async {
                      if (_numEmpleadoController.text.isNotEmpty && _nombreUsuarioController.text.isNotEmpty) {
                        await _refTienda.collection('colaboradores').doc(_numEmpleadoController.text.trim()).set({
                          'nombre': _nombreUsuarioController.text.trim(),
                          'rol': _rolSeleccionado,
                        });
                        _numEmpleadoController.clear();
                        _nombreUsuarioController.clear();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Usuario guardado en ${widget.nombreTienda}', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.green));
                      } else {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Llene todos los campos'), backgroundColor: Colors.redAccent));
                      }
                    },
                    child: const Icon(Icons.person_add)
                  )
                ]
              ),
              const SizedBox(height: 15),
              Container(
                 height: 250, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)),
                 child: StreamBuilder<QuerySnapshot>(
                    stream: _refTienda.collection('colaboradores').snapshots(),
                    builder: (context, snapshot) {
                       if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                       if (snapshot.data!.docs.isEmpty) return const Center(child: Text("Sin usuarios registrados en esta tienda", style: TextStyle(color: Colors.white54)));
                       return ListView.builder(
                          itemCount: snapshot.data!.docs.length,
                          itemBuilder: (context, index) {
                             var doc = snapshot.data!.docs[index];
                             var data = doc.data() as Map<String, dynamic>;
                             
                             String rol = data['rol'] ?? 'piso';
                             IconData icono = Icons.person;
                             Color colorIcono = Colors.blueAccent;
                             if (rol == 'director') { icono = Icons.account_balance; colorIcono = Colors.purpleAccent; }
                             else if (rol == 'gerente') { icono = Icons.business_center; colorIcono = Colors.pinkAccent; }
                             else if (rol == 'jefe') { icono = Icons.security; colorIcono = Colors.amber; }
                             
                             return ListTile(
                                leading: Icon(icono, color: colorIcono),
                                title: Text(data['nombre'] ?? 'Sin nombre', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('Emp: ${doc.id} • Rol: $rol'.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => doc.reference.delete()),
                             );
                          }
                       );
                    }
                 )
              )
            ],
          ),
        ),
      ),
    );
  }
}
