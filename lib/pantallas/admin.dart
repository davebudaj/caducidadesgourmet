import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:universal_html/html.dart' as html;
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

class PantallaAdmin extends StatefulWidget {
  const PantallaAdmin({super.key});
  @override
  State<PantallaAdmin> createState() => _PantallaAdminState();
}

class _PantallaAdminState extends State<PantallaAdmin> {
  final TextEditingController _muebleController = TextEditingController();
  final TextEditingController _correoEmpleadoController = TextEditingController();
  
  // Controladores para usuarios
  final TextEditingController _numEmpleadoController = TextEditingController();
  final TextEditingController _nombreUsuarioController = TextEditingController();
  String _rolSeleccionado = 'piso';
  
  bool _procesando = false;
  String _estado = "Listo para cargar archivos CSV";
  final GlobalKey _qrKey = GlobalKey(); 

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

  Future<void> _cargarCSV() async {
    try {
      FilePickerResult? resultado = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'CSV']);
      if (resultado != null && resultado.files.single.bytes != null) {
        setState(() { _procesando = true; _estado = "Leyendo Catálogo Maestro..."; });
        final bytes = resultado.files.single.bytes!;
        final csvString = latin1.decode(bytes); 
        List<String> filas = const LineSplitter().convert(csvString);
        RegExp separador = RegExp(r',(?=(?:[^"]*"[^"]*")*[^"]*$)');
        var db = FirebaseFirestore.instance;
        WriteBatch lote = db.batch(); 
        int contadorSubidas = 0; int operacionesEnLote = 0;

        for (var i = 1; i < filas.length; i++) {
          if (filas[i].trim().isEmpty) continue;
          List<String> columnas = filas[i].split(separador);
          if (columnas.length >= 13) { 
            String ean = columnas[8].replaceAll('"', '').split('.')[0].trim(); 
            String sku = columnas[9].replaceAll('"', '').split('.')[0].trim(); 
            Map<String, dynamic> dataProducto = {
              'zonaVentas': columnas[0].replaceAll('"', '').trim(), 'centro': columnas[1].replaceAll('"', '').trim(),
              'almacen': columnas[2].replaceAll('"', '').trim(), 'idProveedor': columnas[3].replaceAll('"', '').trim(),
              'nombreProveedor': columnas[4].replaceAll('"', '').trim(), 'idCategoria': columnas[5].replaceAll('"', '').trim(),
              'nombreGpoArticulos': columnas[6].replaceAll('"', '').trim(), 'estado': columnas[7].replaceAll('"', '').trim(),
              'sku': sku, 'ean': ean, 'descripcion': columnas[10].replaceAll('"', '').trim(),
              'precioVenta': columnas[11].replaceAll('"', '').trim(), 'oh': columnas[12].replaceAll('"', '').trim()
            };
            if (ean.isNotEmpty && ean != "0") { lote.set(db.collection('maestro_productos').doc(ean), dataProducto); operacionesEnLote++; contadorSubidas++; }
            if (sku.isNotEmpty) { lote.set(db.collection('maestro_productos').doc(sku), dataProducto); operacionesEnLote++; contadorSubidas++; }
            if (operacionesEnLote >= 450) { await lote.commit(); lote = db.batch(); operacionesEnLote = 0; }
          }
        }
        if (operacionesEnLote > 0) { await lote.commit(); }
        setState(() { _procesando = false; _estado = "¡Éxito!\nSe mapearon $contadorSubidas registros al Catálogo."; });
      }
    } catch (e) { setState(() { _procesando = false; _estado = "Error:\n$e"; }); }
  }

  Future<void> _cargarVentasCSV() async {
    try {
      FilePickerResult? resultado = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'CSV']);
      if (resultado != null && resultado.files.single.bytes != null) {
        setState(() { _procesando = true; _estado = "Calculando FIFO y deduciendo ventas..."; });
        final bytes = resultado.files.single.bytes!;
        final csvString = latin1.decode(bytes); 
        List<String> filas = const LineSplitter().convert(csvString);
        RegExp separador = RegExp(r',(?=(?:[^"]*"[^"]*")*[^"]*$)');
        Map<String, int> ventasProcesadas = {};

        for (var i = 1; i < filas.length; i++) {
          if (filas[i].trim().isEmpty) continue;
          List<String> columnas = filas[i].split(separador);
          if (columnas.length >= 2) {
            String sku = columnas[0].replaceAll('"', '').trim();
            int cantVendida = int.tryParse(columnas[1].replaceAll('"', '').trim()) ?? 0;
            if (sku.isNotEmpty && cantVendida > 0) ventasProcesadas[sku] = (ventasProcesadas[sku] ?? 0) + cantVendida;
          }
        }

        int misiones = 0;
        for (var sku in ventasProcesadas.keys) {
          int porDescontar = ventasProcesadas[sku]!;
          var query = await FirebaseFirestore.instance.collection('inventario_activo').where('sku', isEqualTo: sku).orderBy('fechaCaducidad').get();

          for (var doc in query.docs) {
            if (porDescontar <= 0) break;
            int cantActual = doc['cantidad'] ?? 0;
            int descAqui = (cantActual <= porDescontar) ? cantActual : porDescontar;
            porDescontar -= descAqui;

            if (cantActual <= descAqui) await doc.reference.delete(); 
            else await doc.reference.update({'cantidad': cantActual - descAqui});

            if (descAqui > 0) {
              var data = doc.data();
              await FirebaseFirestore.instance.collection('misiones_auditoria').add({
                'sku': sku, 'descripcion': data['descripcion'] ?? 'ND', 'ubicacion': data['ubicacion'] ?? 'ND',
                'descontado': descAqui, 'fechaCaducidad': data['fechaCaducidad'], 'estado': 'pendiente',
                'nombreProveedor': data['nombreProveedor'] ?? 'ND',
                'nombreGpoArticulos': data['nombreGpoArticulos'] ?? 'SIN GRUPO',
                'fechaGeneracion': FieldValue.serverTimestamp(),
              });
              misiones++;
            }
          }
        }
        setState(() { _procesando = false; _estado = "¡Cierre Exitoso!\nSe generaron $misiones misiones para piso."; });
      }
    } catch (e) { setState(() { _procesando = false; _estado = "Error en ventas:\n$e"; }); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Centro de Mando', style: TextStyle(fontSize: 16)), actions: [Padding(padding: const EdgeInsets.all(8.0), child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black), icon: const Icon(Icons.cloud_download, size: 18), label: const Text('SAP BD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), onPressed: () { html.window.open('https://sapbjp00db.liverpool.com.mx/irj/servlet/prt/portal/prtroot/pcd!3aportal_content!2fcom.sap.pct!2fplatform_add_ons!2fcom.sap.ip.bi!2fiViews!2fcom.sap.ip.bi.bex?BOOKMARK=1TUPM9LFHL4Q6JPS3QRZFIZMX', '_blank'); } ))]),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(_estado, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.amber)),
              const SizedBox(height: 20),
              if (_procesando) const CircularProgressIndicator(color: Colors.amber) else Column(children: [
                SizedBox(height: 50, width: double.infinity, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, foregroundColor: Colors.white), icon: const Icon(Icons.upload_file), label: const Text('CATÁLOGO MAESTRO (CSV)'), onPressed: _cargarCSV)),
                const SizedBox(height: 15),
                SizedBox(height: 50, width: double.infinity, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black), icon: const Icon(Icons.point_of_sale), label: const Text('VENTAS DEL DÍA (CSV)'), onPressed: _cargarVentasCSV)),
              ]),
              const SizedBox(height: 40),
              const Divider(color: Colors.white24),
              const SizedBox(height: 20),
              
              // SECCIÓN: MUEBLES
              const Text('Gestión de Ubicaciones (Muebles)', style: TextStyle(fontSize: 18, color: Colors.amber)),
              const SizedBox(height: 15),
              Row(children: [
                Expanded(child: TextField(controller: _muebleController, decoration: InputDecoration(hintText: 'Ej. Góndola 1', filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)))),
                const SizedBox(width: 10),
                ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: () async { if (_muebleController.text.isNotEmpty) { await FirebaseFirestore.instance.collection('ubicaciones').add({'nombre': _muebleController.text.trim().toUpperCase()}); _muebleController.clear(); } }, child: const Icon(Icons.add))
              ]),
              const SizedBox(height: 15),
              Container(
                height: 200, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)),
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('ubicaciones').orderBy('nombre').snapshots(),
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

              // SECCIÓN: USUARIOS
              const Text('Gestión de Usuarios', style: TextStyle(fontSize: 18, color: Colors.amber)),
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
                        DropdownMenuItem(value: 'piso', child: Text('Colaborador (Piso)')),
                        DropdownMenuItem(value: 'jefe', child: Text('Jefe / Administrador')),
                      ],
                      onChanged: (val) => setState(() => _rolSeleccionado = val!),
                    )
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () async {
                      if (_numEmpleadoController.text.isNotEmpty && _nombreUsuarioController.text.isNotEmpty) {
                        await FirebaseFirestore.instance.collection('colaboradores').doc(_numEmpleadoController.text.trim()).set({
                          'nombre': _nombreUsuarioController.text.trim(),
                          'rol': _rolSeleccionado,
                        });
                        _numEmpleadoController.clear();
                        _nombreUsuarioController.clear();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Usuario guardado exitosamente', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
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
                    stream: FirebaseFirestore.instance.collection('colaboradores').snapshots(),
                    builder: (context, snapshot) {
                       if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                       if (snapshot.data!.docs.isEmpty) return const Center(child: Text("Sin usuarios registrados", style: TextStyle(color: Colors.white54)));
                       return ListView.builder(
                          itemCount: snapshot.data!.docs.length,
                          itemBuilder: (context, index) {
                             var doc = snapshot.data!.docs[index];
                             var data = doc.data() as Map<String, dynamic>;
                             bool esJefe = data['rol'] == 'jefe';
                             return ListTile(
                                leading: Icon(esJefe ? Icons.security : Icons.person, color: esJefe ? Colors.amber : Colors.blueAccent),
                                title: Text(data['nombre'] ?? 'Sin nombre', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('Emp: ${doc.id} • Rol: ${data['rol']}'.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
