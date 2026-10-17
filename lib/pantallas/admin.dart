import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:universal_html/html.dart' as html;
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

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
  String _ultimoBackup = "Sin respaldo reciente";

  @override
  void initState() {
    super.initState();
    _refTienda = FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal);
    _obtenerUltimaActualizacion();
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
          children: const [
            Text('El Catálogo Maestro Zonal ya fue cargado el día de hoy en esta tienda.', style: TextStyle(color: Colors.white70, fontSize: 13)),
            SizedBox(height: 12),
            Text('Para realizar una recarga el mismo día, ingresa la clave maestra ADMIN777:', style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
            SizedBox(height: 8),
            TextField(
              controller: passCtrl,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
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
            }
            if (sku.isNotEmpty && sku != "NaN") { 
               lote.set(db.collection('maestro_productos').doc(sku), dataProducto); 
               operacionesEnLote++; contadorSubidas++; 
            }
            
            if (operacionesEnLote >= 450) { await lote.commit(); lote = db.batch(); operacionesEnLote = 0; }
          }
        }
        
        if (operacionesEnLote > 0) { await lote.commit(); }
        
        await FirebaseFirestore.instance.collection('sistema').doc('catalogo_metadata').set({
          'ultima_carga': FieldValue.serverTimestamp(),
          'usuario_carga': widget.nombreTienda
        });
        await _obtenerUltimaActualizacion();

        setState(() { _procesando = false; _estado = "Catálogo Actualizado Exitosamente!\nSe mapearon $contadorSubidas SKUs con el OH de ${widget.nombreTienda}."; });
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
                  await _refTienda.collection('misiones_auditoria').add({
                    'sku': sku, 'descripcion': data['descripcion'] ?? 'ND', 'ubicacion': data['ubicacion'] ?? 'ND',
                    'descontado': descAqui, 'fechaCaducidad': data['fechaCaducidad'], 'estado': 'pendiente',
                    'nombreProveedor': data['nombreProveedor'] ?? 'ND', 'nombreGpoArticulos': data['nombreGpoArticulos'] ?? 'SIN GRUPO',
                    'fechaGeneracion': FieldValue.serverTimestamp(),
                  });
                  misionesNuevas++;
              }
            }
          }
        }
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
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(height: 50, width: double.infinity, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black), icon: const Icon(Icons.point_of_sale), label: const Text('2. SUBIR VENTAS DEL DÍA'), onPressed: _cargarVentasDiariasCSV)),
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
              
              const Text('Gestión de Ubicaciones (Muebles de esta tienda)', style: TextStyle(fontSize: 18, color: Colors.amber)),
              const SizedBox(height: 15),
              Row(children: [
                Container(
                  height: 55, padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      dropdownColor: const Color(0xFF2C2C2C),
                      value: _prefijoMueble,
                      items: ['PISO', 'BODEGA', 'DISPLAY'].map((String val) => DropdownMenuItem(value: val, child: Text(val, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                      onChanged: (val) => setState(() => _prefijoMueble = val!),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _muebleController, decoration: InputDecoration(hintText: 'Ej. MESA DE TE', filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)))),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), 
                  onPressed: () async { 
                    if (_muebleController.text.isNotEmpty) { 
                      String nombreFinal = '$_prefijoMueble ${_muebleController.text.trim().toUpperCase()}';
                      await _refTienda.collection('ubicaciones').add({'nombre': nombreFinal}); 
                      _muebleController.clear(); 
                    } 
                  }, 
                  child: const Icon(Icons.add)
                )
              ]),
              const SizedBox(height: 15),
              Container(
                height: 200, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)),
                child: StreamBuilder<QuerySnapshot>(
                  stream: _refTienda.collection('ubicaciones').orderBy('nombre').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    return ListView.builder(
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        var doc = snapshot.data!.docs[index];
                        return ListTile(
                          title: Text(doc['nombre'], style: const TextStyle(fontWeight: FontWeight.w500)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.qr_code, color: Colors.blueAccent), onPressed: () => _mostrarYDescargarQR(doc['nombre'])),
                              IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => doc.reference.delete()),
                            ],
                          ),
                        );
                      },
                    );
                  }
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
