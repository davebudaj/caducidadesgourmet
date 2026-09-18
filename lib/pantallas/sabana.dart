import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:universal_html/html.dart' as html;
import 'package:mobile_scanner/mobile_scanner.dart'; // Agregado para el escáner

import '../modelos/etiqueta_mes.dart';

class PantallaDashboard extends StatefulWidget {
  final String usuarioActual;
  const PantallaDashboard({super.key, required this.usuarioActual});
  @override
  State<PantallaDashboard> createState() => PantallaDashboardState();
}

class PantallaDashboardState extends State<PantallaDashboard> {
  final TextEditingController _busquedaController = TextEditingController();
  String _busqueda = "";
  String? _filtroProveedor;
  String? _filtroGrupo;
  String? _filtroRiesgoEspecial; 
  
  late Stream<QuerySnapshot> _inventarioStream; 

  @override
  void initState() {
    super.initState();
    _inventarioStream = FirebaseFirestore.instance.collection('inventario_activo').orderBy('fechaCaducidad').snapshots();
  }

  void aplicarFiltroEspecial(String riesgo) {
    setState(() {
      _filtroRiesgoEspecial = riesgo;
      _filtroProveedor = null; 
      _filtroGrupo = null;
    });
  }

  void _verDetalleCompleto(QueryDocumentSnapshot docSnap) {
    var d = docSnap.data() as Map<String, dynamic>;
    DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(d['descripcion'] ?? 'Sin Nombre', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow("SKU", d['sku']),
              _infoRow("PROVEEDOR", d['nombreProveedor']),
              _infoRow("GRUPO", d['nombreGpoArticulos']),
              _infoRow("UBICACIÓN PISO", d['ubicacion']),
              _infoRow("CANTIDAD", d['cantidad'].toString() + " pzas"),
              _infoRow("PRECIO VENTA", "MXN " + d['precioVenta'].toString()),
              _infoRow("CADUCIDAD", "${cad.day}/${cad.month}/${cad.year}"),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                  icon: const Icon(Icons.handyman),
                  label: const Text('DAR TRATAMIENTO', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () {
                     Navigator.pop(context);
                     _dialogoTratamiento(docSnap);
                  }
                ),
              )
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () {
             Navigator.pop(context);
             _confirmarBorrado(docSnap);
          }, child: const Text('BORRAR', style: TextStyle(color: Colors.redAccent))),
          TextButton(onPressed: () {
             Navigator.pop(context);
             _editarRegistro(docSnap);
          }, child: const Text('EDITAR', style: TextStyle(color: Colors.blueAccent))),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CERRAR', style: TextStyle(color: Colors.white54))),
        ],
      )
    );
  }

  void _dialogoTratamiento(QueryDocumentSnapshot docSnap) {
     var d = docSnap.data() as Map<String, dynamic>;
     int cantOriginal = d['cantidad'] ?? 0;
     TextEditingController cantCtrl = TextEditingController(text: cantOriginal.toString());
     String motivoSeleccionado = 'Merma / Destrucción';

     showDialog(
       context: context,
       builder: (context) {
         return StatefulBuilder(
           builder: (context, setDialogState) {
             return AlertDialog(
               backgroundColor: const Color(0xFF1E1E1E),
               title: const Text('Tratamiento de Mercancía', style: TextStyle(color: Colors.amber)),
               content: Column(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   Text('Lote: ${d['descripcion']}', style: const TextStyle(color: Colors.white70)),
                   const SizedBox(height: 15),
                   TextField(controller: cantCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Piezas a retirar', filled: true, fillColor: Colors.white10)),
                   const SizedBox(height: 15),
                   DropdownButtonFormField<String>(
                     decoration: const InputDecoration(labelText: 'Motivo de Salida', filled: true, fillColor: Colors.white10),
                     dropdownColor: const Color(0xFF2C2C2C),
                     value: motivoSeleccionado,
                     items: const [
                       DropdownMenuItem(value: 'Merma / Destrucción', child: Text('📉 Merma / Destrucción')),
                       DropdownMenuItem(value: 'Saldado / Promoción', child: Text('🏷️ Saldado / Promoción')),
                       DropdownMenuItem(value: 'Devolución a Proveedor', child: Text('📦 Devolución a Proveedor')),
                     ],
                     onChanged: (val) => setDialogState(() => motivoSeleccionado = val!),
                   )
                 ],
               ),
               actions: [
                 TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
                 ElevatedButton(
                   style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
                   onPressed: () async {
                     int cantATratar = int.tryParse(cantCtrl.text) ?? 0;
                     if (cantATratar > 0 && cantATratar <= cantOriginal) {
                       double precio = double.tryParse(d['precioVenta'].toString()) ?? 0.0;
                       
                       await FirebaseFirestore.instance.collection('historial_tratamientos').add({
                         'sku': d['sku'],
                         'descripcion': d['descripcion'],
                         'nombreProveedor': d['nombreProveedor'] ?? 'ND',
                         'nombreGpoArticulos': d['nombreGpoArticulos'] ?? 'SIN GRUPO',
                         'nombreGpoArticulos': d['nombreGpoArticulos'] ?? 'SIN GRUPO',
                         'nombreGpoArticulos': d['nombreGpoArticulos'] ?? 'SIN GRUPO',
                         'ubicacion': d['ubicacion'],
                         'cantidadTratada': cantATratar,
                         'motivo': motivoSeleccionado,
                         'costoTotal': cantATratar * precio,
                         'fechaTratamiento': FieldValue.serverTimestamp(),
                         'usuario': widget.usuarioActual
                       });

                       if (cantATratar == cantOriginal) {
                         await docSnap.reference.delete();
                       } else {
                         await docSnap.reference.update({'cantidad': cantOriginal - cantATratar});
                       }

                       if (mounted) {
                         Navigator.pop(context);
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tratamiento registrado en el historial.'), backgroundColor: Colors.green));
                       }
                     }
                   }, 
                   child: const Text('APLICAR TRATAMIENTO')
                 )
               ],
             );
           }
         );
       }
     );
  }

  void _confirmarBorrado(QueryDocumentSnapshot docSnap) {
    showDialog(
       context: context,
       builder: (context) => AlertDialog(
          title: const Text('¿Borrar Registro?', style: TextStyle(color: Colors.white)),
          content: const Text('Esta acción eliminará el producto del inventario en piso. ¿Estás seguro?', style: TextStyle(color: Colors.white70)),
          backgroundColor: const Color(0xFF1E1E1E),
          actions: [
             TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
             ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () {
                   docSnap.reference.delete();
                   Navigator.pop(context);
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro eliminado')));
                },
                child: const Text('SÍ, BORRAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
             )
          ]
       )
    );
  }

  void _editarRegistro(QueryDocumentSnapshot docSnap) {
    var d = docSnap.data() as Map<String, dynamic>;
    TextEditingController cantCtrl = TextEditingController(text: d['cantidad'].toString());
    TextEditingController skuCtrl = TextEditingController(text: d['sku'].toString()); 
    
    String currentDesc = d['descripcion'] ?? 'Artículo Nuevo';
    Map<String, dynamic>? updatedMasterData;
    String? localUbi;
    
    showDialog(
       context: context,
       builder: (context) {
          return StatefulBuilder(
             builder: (context, setDialogState) {
                FocusNode skuFocus = FocusNode();
                skuFocus.addListener(() async {
                   if (!skuFocus.hasFocus && skuCtrl.text.isNotEmpty) {
                      setDialogState(() { currentDesc = "Buscando..."; });
                      try {
                         var masterDoc = await FirebaseFirestore.instance.collection('maestro_productos').doc(skuCtrl.text).get();
                         if (masterDoc.exists) {
                            updatedMasterData = masterDoc.data();
                            setDialogState(() { currentDesc = updatedMasterData?['descripcion'] ?? 'Sin Nombre'; });
                         } else {
                            updatedMasterData = null;
                            setDialogState(() { currentDesc = 'Artículo Nuevo (No en catálogo)'; });
                         }
                      } catch (e) {
                         setDialogState(() { currentDesc = 'Error al buscar'; });
                      }
                   }
                });

                return AlertDialog(
                   backgroundColor: const Color(0xFF1E1E1E),
                   title: const Text('Editar Registro', style: TextStyle(color: Colors.amber)),
                   content: SingleChildScrollView(
                      child: Column(
                         mainAxisSize: MainAxisSize.min,
                         children: [
                            TextField(
                               controller: skuCtrl,
                               focusNode: skuFocus,
                               decoration: const InputDecoration(labelText: 'SKU / EAN', labelStyle: TextStyle(color: Colors.amber), filled: true, fillColor: Colors.white10),
                            ),
                            const SizedBox(height: 5),
                            Align(alignment: Alignment.centerLeft, child: Text(currentDesc, style: const TextStyle(fontSize: 10, color: Colors.greenAccent))),
                            const Divider(color: Colors.white12),
                            TextField(controller: cantCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad Fija (Piezas)', labelStyle: TextStyle(color: Colors.white54))),
                            const SizedBox(height: 15),
                            
                            StreamBuilder<QuerySnapshot>(
                               stream: FirebaseFirestore.instance.collection('ubicaciones').orderBy('nombre').snapshots(),
                               builder: (context, ubiSnapshot) {
                                  if (!ubiSnapshot.hasData) return const LinearProgressIndicator();
                                  List<String> validUbis = ubiSnapshot.data!.docs.map((u) => u['nombre'].toString()).toList();
                                  if(localUbi == null) {
                                      String currentUbi = d['ubicacion'].toString();
                                      if(validUbis.contains(currentUbi)) localUbi = currentUbi;
                                  }

                                  return DropdownButtonFormField<String?>(
                                     decoration: const InputDecoration(labelText: "Seleccionar Mueble / Ubicación", labelStyle: TextStyle(color: Colors.amber)),
                                     dropdownColor: const Color(0xFF2C2C2C),
                                     value: localUbi,
                                     hint: const Text("Elige...", style: TextStyle(color: Colors.white24)),
                                     items: validUbis.map((ubi) => DropdownMenuItem(value: ubi, child: Text(ubi, style: const TextStyle(fontSize: 12)))).toList(),
                                     onChanged: (val) { setDialogState(() { localUbi = val; }); },
                                  );
                               }
                            ),
                         ]
                      ),
                   ),
                   actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
                      ElevatedButton(
                         style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                         onPressed: () {
                            int? nCant = int.tryParse(cantCtrl.text);
                            String nSku = skuCtrl.text;
                            
                            if(nCant != null && nSku.isNotEmpty) {
                               Map<String, dynamic> updateData = {
                                  'cantidad': nCant,
                                  'sku': nSku, 
                                  'ubicacion': localUbi, 
                                  'descripcion': currentDesc 
                               };
                               
                               if(updatedMasterData != null) {
                                   updateData.addAll({
                                      'idProveedor': updatedMasterData!['idProveedor'],
                                      'nombreProveedor': updatedMasterData!['nombreProveedor'],
                                      'idCategoria': updatedMasterData!['idCategoria'],
                                      'nombreGpoArticulos': updatedMasterData!['nombreGpoArticulos'],
                                      'precioVenta': updatedMasterData!['precioVenta'],
                                      'oh': updatedMasterData!['oh'],
                                   });
                               } else if (nSku != d['sku']) {
                                   updateData.addAll({
                                      'nombreProveedor': FieldValue.delete(),
                                      'nombreGpoArticulos': FieldValue.delete(),
                                      'precioVenta': FieldValue.delete(),
                                      'oh': FieldValue.delete(),
                                   });
                               }

                               docSnap.reference.update(updateData);
                               Navigator.pop(context);
                               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro actualizado con éxito'), backgroundColor: Colors.green));
                            }
                         },
                         child: const Text('GUARDAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                      )
                   ]
                );
             }
          );
       }
    );
  }

  Widget _infoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: RichText(text: TextSpan(children: [
        TextSpan(text: label + ": ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70, fontSize: 12)),
        TextSpan(text: value.toString(), style: const TextStyle(color: Colors.amberAccent, fontSize: 14)),
      ])),
    );
  }

  void _descargarExcel(List<QueryDocumentSnapshot> docs, {String nombreArchivo = "Sabana_Filtros.csv"}) {
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay datos para descargar')));
      return;
    }
    
    StringBuffer csv = StringBuffer();
    csv.writeln("SKU,EAN,DESCRIPCION,PROVEEDOR,GRUPO_ARTICULOS,UBICACION,CANTIDAD,PRECIO_VENTA,OH_SAP,FECHA_CADUCIDAD,DIAS_PARA_VENCER");

    DateTime hoy = DateTime.now();

    for (var doc in docs) {
      var d = doc.data() as Map<String, dynamic>;
      DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
      int dias = cad.difference(hoy).inDays;
      
      String sku = (d['sku'] ?? '').toString();
      String ean = (d['ean'] ?? '').toString();
      String desc = '"' + (d['descripcion'] ?? '').toString().replaceAll('"', '""') + '"';
      String prov = '"' + (d['nombreProveedor'] ?? '').toString().replaceAll('"', '""') + '"';
      String gpo = '"' + (d['nombreGpoArticulos'] ?? '').toString().replaceAll('"', '""') + '"';
      String ubi = '"' + (d['ubicacion'] ?? '').toString().replaceAll('"', '""') + '"';
      String cant = (d['cantidad'] ?? 0).toString();
      String precio = (d['precioVenta'] ?? 0).toString();
      String oh = (d['oh'] ?? 0).toString();
      String fCad = "${cad.day}/${cad.month}/${cad.year}";

      csv.writeln("$sku,$ean,$desc,$prov,$gpo,$ubi,$cant,$precio,$oh,$fCad,$dias");
    }

    final bytes = utf8.encode('\uFEFF' + csv.toString()); 
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", nombreArchivo)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  void _descargarProximoMes(List<QueryDocumentSnapshot> todosLosDocs) {
    DateTime hoy = DateTime.now();
    int mesSig = hoy.month == 12 ? 1 : hoy.month + 1;
    int anioSig = hoy.month == 12 ? hoy.year + 1 : hoy.year;

    var docsProximoMes = todosLosDocs.where((doc) {
      var data = doc.data() as Map<String, dynamic>;
      Timestamp? ts = data['fechaCaducidad'];
      if (ts == null) return false;
      DateTime cad = ts.toDate();
      return cad.month == mesSig && cad.year == anioSig;
    }).toList();

    if (docsProximoMes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay caducidades registradas para el próximo mes.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent));
      return;
    }

    _descargarExcel(docsProximoMes, nombreArchivo: "Caducidades_${mesSig}_${anioSig}.csv");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sábana de Riesgo', style: TextStyle(fontWeight: FontWeight.bold))),
      body: StreamBuilder<QuerySnapshot>(
        stream: _inventarioStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.amber));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Inventario sano.'));
          
          var provs = snapshot.data!.docs.map((doc) => (doc.data() as Map)['nombreProveedor']?.toString() ?? 'ND').toSet().toList()..sort();
          var grupos = snapshot.data!.docs.map((doc) => (doc.data() as Map)['nombreGpoArticulos']?.toString() ?? 'ND').toSet().toList()..sort();

          var docsFiltrados = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            String desc = (data['descripcion'] ?? '').toString().toLowerCase();
            String sku = (data['sku'] ?? '').toString().toLowerCase();
            String prov = (data['nombreProveedor'] ?? 'ND').toString();
            String gpo = (data['nombreGpoArticulos'] ?? 'ND').toString();

            DateTime cad = (data['fechaCaducidad'] as Timestamp).toDate();
            int dias = cad.difference(DateTime.now()).inDays;

            bool coincideBusqueda = _busqueda.isEmpty || desc.contains(_busqueda) || sku.contains(_busqueda);
            bool coincideProv = _filtroProveedor == null || prov == _filtroProveedor;
            bool coincideGpo = _filtroGrupo == null || gpo == _filtroGrupo;
            
            bool coincideRiesgo = true;
            if (_filtroRiesgoEspecial != null) {
              if (_filtroRiesgoEspecial == 'caducado') coincideRiesgo = dias < 0;
              else if (_filtroRiesgoEspecial == 'critico') coincideRiesgo = dias >= 0 && dias <= 14;
              else if (_filtroRiesgoEspecial == 'proximo') coincideRiesgo = dias > 14 && dias <= 30;
              else if (_filtroRiesgoEspecial == 'sano') coincideRiesgo = dias > 30;
            }
            
            return coincideBusqueda && coincideProv && coincideGpo && coincideRiesgo;
          }).toList();

          var docsFinales = docsFiltrados.take(100).toList();

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(color: Colors.black, border: Border(bottom: BorderSide(color: Colors.white24, width: 1))),
                child: Column(
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, foregroundColor: Colors.white),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Limpiar', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                             _busquedaController.clear();
                             setState(() {
                               _busqueda = "";
                               _filtroProveedor = null;
                               _filtroGrupo = null;
                               _filtroRiesgoEspecial = null;
                             });
                          }
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('CSV Filtros', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: () => _descargarExcel(docsFiltrados),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black),
                          icon: const Icon(Icons.date_range, size: 16),
                          label: const Text('CSV Próx. Mes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: () => _descargarProximoMes(snapshot.data!.docs),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _busquedaController,
                      decoration: InputDecoration(
                        hintText: 'Buscar SKU o Artículo...',
                        prefixIcon: const Icon(Icons.search, color: Colors.amber),
                        
                        // EL BOTÓN DEL ESCÁNER HA SIDO AÑADIDO AQUÍ COMO SUFFIX ICON
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.qr_code_scanner, color: Colors.blueAccent),
                          tooltip: 'Escanear Código',
                          onPressed: () async {
                             String? codigoEscaneado = await Navigator.push(
                               context, 
                               MaterialPageRoute(builder: (context) => const PantallaEscanerRapido())
                             );
                             if (codigoEscaneado != null && codigoEscaneado.isNotEmpty) {
                                _busquedaController.text = codigoEscaneado;
                                setState(() => _busqueda = codigoEscaneado.toLowerCase());
                             }
                          }
                        ),
                        
                        filled: true, fillColor: Colors.white10,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0)
                      ),
                      onChanged: (v) => setState(() => _busqueda = v.toLowerCase()),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 40, padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                isExpanded: true, dropdownColor: const Color(0xFF2C2C2C),
                                value: _filtroProveedor, hint: const Text('Proveedor', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('Todos', style: TextStyle(fontSize: 12, color: Colors.greenAccent))), 
                                  ...provs.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))
                                ],
                                onChanged: (v) => setState(() => _filtroProveedor = v),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            height: 40, padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                isExpanded: true, dropdownColor: const Color(0xFF2C2C2C),
                                value: _filtroGrupo, hint: const Text('Gpo Artículos', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('Todos', style: TextStyle(fontSize: 12, color: Colors.greenAccent))), 
                                  ...grupos.map((g) => DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))
                                ],
                                onChanged: (v) => setState(() => _filtroGrupo = v),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
              Expanded(
                child: docsFinales.isEmpty
                    ? const Center(child: Text('No hay productos que coincidan.', style: TextStyle(color: Colors.white54)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: docsFinales.length,
                        itemBuilder: (context, i) {
                          var d = docsFinales[i].data() as Map<String, dynamic>;
                          DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
                          int dias = cad.difference(DateTime.now()).inDays;
                          Map<String, dynamic> etiqueta = EtiquetaMes.obtener(cad);
                          
                          return Card(
                            color: Colors.white10,
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.white24)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              onTap: () => _verDetalleCompleto(docsFinales[i]), 
                              leading: Container(
                                width: 45, height: 45,
                                decoration: BoxDecoration(color: etiqueta['color'].withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: etiqueta['color'])),
                                child: Center(child: Text(dias.toString(), style: TextStyle(color: etiqueta['color'], fontWeight: FontWeight.bold, fontSize: 14))),
                              ),
                              title: Text(d['descripcion'] ?? d['sku'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(d['cantidad'].toString() + ' pzas • Ubicación: ' + d['ubicacion'].toString(), style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
                              ),
                              trailing: const Icon(Icons.info_outline, color: Colors.white54),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Nueva pantalla anidada para manejar el escaneo rápido sin salir de la Sábana
class PantallaEscanerRapido extends StatefulWidget {
  const PantallaEscanerRapido({super.key});

  @override
  State<PantallaEscanerRapido> createState() => _PantallaEscanerRapidoState();
}

class _PantallaEscanerRapidoState extends State<PantallaEscanerRapido> {
  bool _yaEscaneado = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear SKU para buscar', style: TextStyle(color: Colors.amber))),
      body: MobileScanner(
        onDetect: (capture) {
          if (_yaEscaneado) return; // Evita que lea 10 veces en un segundo
          final barcode = capture.barcodes.first;
          if (barcode.rawValue != null) {
            setState(() => _yaEscaneado = true);
            Navigator.pop(context, barcode.rawValue);
          }
        },
      ),
    );
  }
}
