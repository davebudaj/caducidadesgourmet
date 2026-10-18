import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:universal_html/html.dart' as html;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../modelos/etiqueta_mes.dart';
import 'finanzas.dart';

class PantallaDashboard extends StatefulWidget {
  final String usuarioActual;
  final String idTiendaGlobal;
  const PantallaDashboard({super.key, required this.usuarioActual, required this.idTiendaGlobal});
  @override
  State<PantallaDashboard> createState() => PantallaDashboardState();
}

class PantallaDashboardState extends State<PantallaDashboard> {
  final TextEditingController _busquedaController = TextEditingController();
  String _busqueda = "";
  String? _filtroProveedor;
  String? _filtroGrupo;
  String? _filtroRiesgoEspecial;
  String? _filtroTipoUbicacion;
  String? _filtroMueble;
  int? _filtroMes = DateTime.now().month;

  static const Map<int, String> _nombresMeses = {
    1: 'Enero', 2: 'Febrero', 3: 'Marzo', 4: 'Abril',
    5: 'Mayo', 6: 'Junio', 7: 'Julio', 8: 'Agosto',
    9: 'Septiembre', 10: 'Octubre', 11: 'Noviembre', 12: 'Diciembre'
  }; 
  
  bool _modoSeleccion = false;
  bool _filtroDescuadreSAP = false;
  Set<String> _seleccionados = {};
  
  late Stream<QuerySnapshot> _inventarioStream; 

  @override
  void initState() {
    super.initState();
    _inventarioStream = FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('inventario_activo').orderBy('fechaCaducidad').snapshots();
  }

  Future<String> _traducirCodigoASku(String codigo) async {
    String limpio = codigo.trim();
    if (limpio.isEmpty) return limpio;
    var doc = await FirebaseFirestore.instance.collection('maestro_productos').doc(limpio).get();
    if (doc.exists) {
      var d = doc.data();
      if (d != null && d['sku'] != null && d['sku'].toString().trim().isNotEmpty) {
        return d['sku'].toString().trim();
      }
    }
    return limpio;
  }

  void aplicarFiltroEspecial(String riesgo) {
    setState(() {
      _filtroRiesgoEspecial = riesgo;
      _filtroProveedor = null;
      _filtroMes = null;
      _filtroDescuadreSAP = false; 
      _filtroGrupo = null;
    });
  }

  void _borrarSeleccionados() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Borrar Múltiples Lotes', style: TextStyle(color: Colors.redAccent)),
        content: Text('¿Seguro que deseas eliminar ${_seleccionados.length} lote(s) de la Sábana de Riesgos?\n\nEsta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              var batch = FirebaseFirestore.instance.batch();
              for (String id in _seleccionados) {
                batch.delete(FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('inventario_activo').doc(id));
              }
              await batch.commit();
              setState(() {
                _modoSeleccion = false;
                _seleccionados.clear();
              });
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lotes eliminados exitosamente'), backgroundColor: Colors.green));
            },
            child: const Text('SÍ, BORRAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          )
        ]
      )
    );
  }

  void _tratamientoMasivo() {
    String motivoSeleccionado = 'Merma / Destrucción';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text('Tratamiento Masivo', style: TextStyle(color: Colors.amber)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Se aplicará a ${_seleccionados.length} lote(s) en su totalidad.', style: const TextStyle(color: Colors.white70)),
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
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                onPressed: () async {
                  Navigator.pop(ctx);
                  var batch = FirebaseFirestore.instance.batch();
                  var refTienda = FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal);
                  
                  for (String id in _seleccionados) {
                    var docRef = refTienda.collection('inventario_activo').doc(id);
                    var docSnap = await docRef.get();
                    if (docSnap.exists) {
                      var d = docSnap.data() as Map<String, dynamic>;
                      int cant = d['cantidad'] ?? 0;
                      double precio = double.tryParse((d['precioVenta'] ?? 0).toString()) ?? 0.0;
                      
                      var histRef = refTienda.collection('historial_tratamientos').doc();
                      batch.set(histRef, {
                        'sku': d['sku'],
                        'descripcion': d['descripcion'],
                        'nombreProveedor': d['nombreProveedor'] ?? 'ND',
                        'nombreGpoArticulos': d['nombreGpoArticulos'] ?? 'SIN GRUPO',
                        'ubicacion': d['ubicacion'],
                        'cantidadTratada': cant,
                        'motivo': motivoSeleccionado,
                        'costoTotal': cant * precio,
                        'fechaTratamiento': FieldValue.serverTimestamp(),
                        'usuario': widget.usuarioActual
                      });
                      FinanzasService.actualizarResumenEnBatch(
                        batch: batch,
                        idTiendaGlobal: widget.idTiendaGlobal,
                        motivo: motivoSeleccionado,
                        cantidad: cant,
                        monto: cant * precio,
                      );
                      
                      if (motivoSeleccionado == 'Saldado / Promoción') {
                        batch.update(docRef, {
                          'enPromocion': true,
                          if (d['comentarioCorporativo'] != null) 'instruccionCorpEjecutada': true,
                          if (d['comentarioCorporativo'] != null) 'ejecutadaPorCorp': widget.usuarioActual,
                          if (d['comentarioCorporativo'] != null) 'motivoEjecucionCorp': motivoSeleccionado,
                          'piezasEnPromocion': cant,
                          'fechaPromocion': FieldValue.serverTimestamp(),
                        });
                      } else {
                        batch.delete(docRef);
                      }
                    }
                  }
                  await batch.commit();
                  setState(() {
                    _modoSeleccion = false;
                    _seleccionados.clear();
                  });
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tratamiento masivo aplicado exitosamente'), backgroundColor: Colors.green));
                },
                child: const Text('APLICAR', style: TextStyle(fontWeight: FontWeight.bold))
              )
            ]
          );
        }
      )
    );
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
              _infoRow("CANTIDAD FÍSICA", d['cantidad'].toString() + " pzas"),
              _infoRow("PRECIO VENTA", "MXN " + (d['precioVenta'] ?? 0).toString()),
              _infoRow("OH TEÓRICO (SAP)", (d['oh'] ?? 'No disponible').toString() + " pzas"),
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
     DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
     int dias = cad.difference(DateTime.now()).inDays;
     bool bloquearPromocion = (d['enPromocion'] == true) || (dias <= 15);
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
                     items: [
                       const DropdownMenuItem(value: 'Merma / Destrucción', child: Text('📉 Merma / Destrucción')),
                       if (!bloquearPromocion)
                         const DropdownMenuItem(value: 'Saldado / Promoción', child: Text('🏷️ Saldado / Promoción')),
                       const DropdownMenuItem(value: 'Devolución a Proveedor', child: Text('📦 Devolución a Proveedor')),
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
                       double precio = double.tryParse((d['precioVenta'] ?? 0).toString()) ?? 0.0;
                       
                       var batchTrat = FirebaseFirestore.instance.batch();
                       var histDoc = FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('historial_tratamientos').doc();
                       batchTrat.set(histDoc, {
                         'sku': d['sku'],
                         'descripcion': d['descripcion'],
                         'nombreProveedor': d['nombreProveedor'] ?? 'ND',
                         'nombreGpoArticulos': d['nombreGpoArticulos'] ?? 'SIN GRUPO',
                         'ubicacion': d['ubicacion'],
                         'cantidadTratada': cantATratar,
                         'motivo': motivoSeleccionado,
                         'costoTotal': cantATratar * precio,
                         'fechaTratamiento': FieldValue.serverTimestamp(),
                         'usuario': widget.usuarioActual
                       });
                       FinanzasService.actualizarResumenEnBatch(
                         batch: batchTrat,
                         idTiendaGlobal: widget.idTiendaGlobal,
                         motivo: motivoSeleccionado,
                         cantidad: cantATratar,
                         monto: cantATratar * precio,
                       );
                       await batchTrat.commit();

                       if (motivoSeleccionado == 'Saldado / Promoción') {
                         await docSnap.reference.update({
                           'enPromocion': true,
                          if (d['comentarioCorporativo'] != null) 'instruccionCorpEjecutada': true,
                          if (d['comentarioCorporativo'] != null) 'ejecutadaPorCorp': widget.usuarioActual,
                          if (d['comentarioCorporativo'] != null) 'motivoEjecucionCorp': motivoSeleccionado,
                           'piezasEnPromocion': cantATratar,
                           'fechaPromocion': FieldValue.serverTimestamp(),
                         });
                       } else if (cantATratar == cantOriginal) {
                         await docSnap.reference.delete();
                       } else {
                         await docSnap.reference.update({
                           'cantidad': cantOriginal - cantATratar,
                           if (d['comentarioCorporativo'] != null) 'instruccionCorpEjecutada': true,
                           if (d['comentarioCorporativo'] != null) 'ejecutadaPorCorp': widget.usuarioActual,
                           if (d['comentarioCorporativo'] != null) 'motivoEjecucionCorp': motivoSeleccionado,
                         });
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
    DateTime fechaOriginal = (d['fechaCaducidad'] as Timestamp).toDate();
    DateTime fechaEditada = fechaOriginal;

    String currentDesc = d['descripcion'] ?? 'Artículo Nuevo';
    Map<String, dynamic>? updatedMasterData;
    String? localUbi;
    FocusNode skuFocus = FocusNode();
    bool listenerAdded = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (!listenerAdded) {
              listenerAdded = true;
              skuFocus.addListener(() async {
                if (!skuFocus.hasFocus && skuCtrl.text.isNotEmpty) {
                  setDialogState(() => currentDesc = "Buscando...");
                  try {
                    String codigoEscrito = skuCtrl.text.trim();
                    var masterDoc = await FirebaseFirestore.instance.collection('maestro_productos').doc(codigoEscrito).get();
                    if (masterDoc.exists) {
                      updatedMasterData = masterDoc.data();
                      if (updatedMasterData?['sku'] != null && updatedMasterData!['sku'].toString().trim().isNotEmpty) {
                        skuCtrl.text = updatedMasterData!['sku'].toString().trim();
                      }
                      setDialogState(() => currentDesc = updatedMasterData?['descripcion'] ?? 'Sin Nombre');
                    } else {
                      updatedMasterData = null;
                      setDialogState(() => currentDesc = 'Artículo Nuevo (No en catálogo)');
                    }
                  } catch (e) {
                    setDialogState(() => currentDesc = 'Error al buscar');
                  }
                }
              });
            }

            String fechaTexto = "${fechaEditada.day.toString().padLeft(2, '0')}/${fechaEditada.month.toString().padLeft(2, '0')}/${fechaEditada.year}";

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text('Editar Registro', style: TextStyle(color: Colors.amber)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: skuCtrl,
                      focusNode: skuFocus,
                      decoration: const InputDecoration(labelText: 'SKU / UPC', labelStyle: TextStyle(color: Colors.amber), filled: true, fillColor: Colors.white10),
                    ),
                    const SizedBox(height: 5),
                    Align(alignment: Alignment.centerLeft, child: Text(currentDesc, style: const TextStyle(fontSize: 10, color: Colors.greenAccent))),
                    const Divider(color: Colors.white12),
                    TextField(
                      controller: cantCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cantidad Fija (Piezas)', labelStyle: TextStyle(color: Colors.white54)),
                    ),
                    const SizedBox(height: 15),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('ubicaciones').orderBy('nombre').snapshots(),
                      builder: (context, ubiSnapshot) {
                        if (!ubiSnapshot.hasData) return const LinearProgressIndicator();
                        List<String> validUbis = ubiSnapshot.data!.docs.map((u) => u['nombre'].toString()).toList();
                        if (localUbi == null) {
                          String currentUbi = d['ubicacion'].toString();
                          if (validUbis.contains(currentUbi)) localUbi = currentUbi;
                        }

                        return DropdownButtonFormField<String?>(
                          decoration: const InputDecoration(labelText: "Seleccionar Mueble / Ubicación", labelStyle: TextStyle(color: Colors.amber)),
                          dropdownColor: const Color(0xFF2C2C2C),
                          value: localUbi,
                          hint: const Text("Elige...", style: TextStyle(color: Colors.white24)),
                          items: validUbis.map((ubi) => DropdownMenuItem(value: ubi, child: Text(ubi, style: const TextStyle(fontSize: 12)))).toList(),
                          onChanged: (val) => setDialogState(() => localUbi = val),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    const Text('Fecha de Caducidad', style: TextStyle(color: Colors.amber, fontSize: 12)),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white10,
                          side: const BorderSide(color: Colors.amber, width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.calendar_month, color: Colors.amber),
                        label: Text(
                          fechaTexto,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                        ),
                        onPressed: () async {
                          DateTime? nuevaFecha = await showDatePicker(
                            context: context,
                            initialDate: fechaEditada,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2036),
                          );
                          if (nuevaFecha != null) {
                            setDialogState(() => fechaEditada = nuevaFecha);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  onPressed: () async {
                    int? nCant = int.tryParse(cantCtrl.text);
                    String nSku = await _traducirCodigoASku(skuCtrl.text);

                    if (nCant != null && nSku.isNotEmpty) {
                      var masterDoc = await FirebaseFirestore.instance.collection('maestro_productos').doc(nSku).get();
                      if (masterDoc.exists) {
                        updatedMasterData = masterDoc.data();
                        currentDesc = updatedMasterData?['descripcion'] ?? currentDesc;
                      }

                      Map<String, dynamic> updateData = {
                        'cantidad': nCant,
                        'sku': nSku,
                        'ubicacion': localUbi,
                        'descripcion': currentDesc,
                        'fechaCaducidad': Timestamp.fromDate(fechaEditada),
                      };

                      if (fechaEditada.year != fechaOriginal.year ||
                          fechaEditada.month != fechaOriginal.month ||
                          fechaEditada.day != fechaOriginal.day) {
                        updateData['misionGenerada45d'] = FieldValue.delete();
                        updateData['misionBodega90d'] = FieldValue.delete();
                      }

                      if (updatedMasterData != null) {
                        updateData.addAll({
                          'ean': updatedMasterData!['ean'] ?? '',
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

                      await docSnap.reference.update(updateData);
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Registro actualizado con éxito'), backgroundColor: Colors.green),
                        );
                      }
                    }
                  },
                  child: const Text('GUARDAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
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
      appBar: _modoSeleccion
          ? AppBar(
              backgroundColor: Colors.redAccent.shade700,
              leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _modoSeleccion = false; _seleccionados.clear(); })),
              title: Text('${_seleccionados.length} seleccionados', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              actions: [
                IconButton(icon: const Icon(Icons.handyman), tooltip: 'Tratamiento Masivo', onPressed: _tratamientoMasivo),
                IconButton(icon: const Icon(Icons.delete_forever), tooltip: 'Borrar Lotes', onPressed: _borrarSeleccionados),
              ],
            )
          : AppBar(title: const Text('Sábana de Riesgo', style: TextStyle(fontWeight: FontWeight.bold))),
      body: StreamBuilder<QuerySnapshot>(
        stream: _inventarioStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.amber));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Inventario sano.'));
          
          var provs = snapshot.data!.docs.map((doc) => (doc.data() as Map)['nombreProveedor']?.toString() ?? 'ND').toSet().toList()..sort();
          var grupos = snapshot.data!.docs.map((doc) => (doc.data() as Map)['nombreGpoArticulos']?.toString() ?? 'ND').toSet().toList()..sort();
          Set<String> conjuntoMueblesYRamas = {};
          for (var doc in snapshot.data!.docs) {
            String u = ((doc.data() as Map)['ubicacion']?.toString() ?? 'ND');
            if (_filtroTipoUbicacion == null || u.toUpperCase().contains(_filtroTipoUbicacion!)) {
              conjuntoMueblesYRamas.add(u);
              if (u.contains(' > ')) {
                List<String> p = u.split(' > ');
                String acum = p[0];
                for (int k = 1; k < p.length - 1; k++) {
                  acum = '$acum > ${p[k]}';
                  conjuntoMueblesYRamas.add(acum);
                }
              }
            }
          }
          var mueblesDisponibles = conjuntoMueblesYRamas.toList()..sort();

          Map<String, int> sumaFisicaPorSku = {};
          for (var doc in snapshot.data!.docs) {
            var dMap = doc.data() as Map<String, dynamic>;
            String s = (dMap['sku'] ?? '').toString();
            int c = (dMap['cantidad'] ?? 0) as int;
            if (s.isNotEmpty) {
              sumaFisicaPorSku[s] = (sumaFisicaPorSku[s] ?? 0) + c;
            }
          }

          var docsFiltrados = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            String desc = (data['descripcion'] ?? '').toString().toLowerCase();
            String sku = (data['sku'] ?? '').toString().toLowerCase();
            String ean = (data['ean'] ?? '').toString().toLowerCase();
            String prov = (data['nombreProveedor'] ?? 'ND').toString();
            String gpo = (data['nombreGpoArticulos'] ?? 'ND').toString();
            String ubi = (data['ubicacion'] ?? 'ND').toString();

            DateTime cad = (data['fechaCaducidad'] as Timestamp).toDate();
            int dias = cad.difference(DateTime.now()).inDays;

            bool coincideBusqueda = _busqueda.isEmpty || desc.contains(_busqueda) || sku.contains(_busqueda) || ean.contains(_busqueda);
            bool coincideProv = _filtroProveedor == null || prov == _filtroProveedor;
            bool coincideGpo = _filtroGrupo == null || gpo == _filtroGrupo;
            
            bool coincideRiesgo = true;
            if (_filtroRiesgoEspecial != null) {
              if (_filtroRiesgoEspecial == 'caducado') coincideRiesgo = dias < 0;
              else if (_filtroRiesgoEspecial == 'critico') coincideRiesgo = dias >= 0 && dias <= 14;
              else if (_filtroRiesgoEspecial == 'proximo') coincideRiesgo = dias > 14 && dias <= 30;
              else if (_filtroRiesgoEspecial == 'sano') coincideRiesgo = dias > 30;
            }
            
            bool coincideTipoUbi = _filtroTipoUbicacion == null || ubi.toUpperCase().contains(_filtroTipoUbicacion!);
            bool coincideMueble = _filtroMueble == null || ubi == _filtroMueble || ubi.startsWith('${_filtroMueble!} > ');
            bool coincideMes = _filtroMes == null || cad.month == _filtroMes;
            bool coincideDescuadre = true;
            if (_filtroDescuadreSAP) {
              String skuRaw = (data['sku'] ?? '').toString();
              int totalFisico = sumaFisicaPorSku[skuRaw] ?? 0;
              int ohSap = int.tryParse((data['oh'] ?? '').toString().split('.')[0].trim()) ?? -1;
              coincideDescuadre = (ohSap >= 0 && totalFisico != ohSap);
            }
            return coincideBusqueda && coincideProv && coincideGpo && coincideRiesgo && coincideTipoUbi && coincideMueble && coincideMes && coincideDescuadre;
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
      _filtroTipoUbicacion = null;
      _filtroMueble = null;
      _filtroMes = null;
      _filtroDescuadreSAP = false;
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
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _filtroDescuadreSAP ? Colors.redAccent : Colors.white10,
                            foregroundColor: Colors.white,
                            side: BorderSide(color: _filtroDescuadreSAP ? Colors.amberAccent : Colors.redAccent),
                          ),
                          icon: const Icon(Icons.compare_arrows, size: 16),
                          label: Text(_filtroDescuadreSAP ? 'Viendo Descuadre SAP' : 'Descuadre vs SAP', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: () => setState(() {
                            _filtroDescuadreSAP = !_filtroDescuadreSAP;
                            if (_filtroDescuadreSAP) _filtroMes = null;
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _busquedaController,
                      decoration: InputDecoration(
                        hintText: 'Buscar SKU, UPC o Artículo...',
                        prefixIcon: const Icon(Icons.search, color: Colors.amber),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.qr_code_scanner, color: Colors.blueAccent),
                          tooltip: 'Escanear Código',
                          onPressed: () async {
                             String? codigoEscaneado = await Navigator.push(
                               context, 
                               MaterialPageRoute(builder: (context) => const PantallaEscanerRapido())
                             );
                             if (codigoEscaneado != null && codigoEscaneado.isNotEmpty) {
                                String skuTraducido = await _traducirCodigoASku(codigoEscaneado);
                                _busquedaController.text = skuTraducido;
                                setState(() => _busqueda = skuTraducido.toLowerCase());
                             }
                          }
                        ),
                        filled: true, fillColor: Colors.white10,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0)
                      ),
                      onChanged: (v) => setState(() => _busqueda = v.toLowerCase()),
                      onSubmitted: (v) async {
                        String traducido = await _traducirCodigoASku(v);
                        if (traducido != v.trim()) {
                          _busquedaController.text = traducido;
                          setState(() => _busqueda = traducido.toLowerCase());
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(left: 4, bottom: 4),
                                child: Text('Filtro proveedor', style: TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold)),
                              ),
                              Container(
                                height: 40,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String?>(
                                    isExpanded: true,
                                    dropdownColor: const Color(0xFF2C2C2C),
                                    value: _filtroProveedor,
                                    hint: const Text('Filtro proveedor', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                    items: [
                                      const DropdownMenuItem(value: null, child: Text('Filtro proveedor: Todos', style: TextStyle(fontSize: 12, color: Colors.greenAccent))),
                                      ...provs.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))
                                    ],
                                    onChanged: (v) => setState(() => _filtroProveedor = v),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(left: 4, bottom: 4),
                                child: Text('Filtro Grupo de Art.', style: TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold)),
                              ),
                              Container(
                                height: 40,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String?>(
                                    isExpanded: true,
                                    dropdownColor: const Color(0xFF2C2C2C),
                                    value: _filtroGrupo,
                                    hint: const Text('Filtro Grupo de Art.', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                    items: [
                                      const DropdownMenuItem(value: null, child: Text('Filtro Grupo de Art.: Todos', style: TextStyle(fontSize: 12, color: Colors.greenAccent))),
                                      ...grupos.map((g) => DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))
                                    ],
                                    onChanged: (v) => setState(() => _filtroGrupo = v),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(left: 4, bottom: 4),
                                child: Text('Filtro Ubicación', style: TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold)),
                              ),
                              Container(
                                height: 40,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String?>(
                                    isExpanded: true,
                                    dropdownColor: const Color(0xFF2C2C2C),
                                    value: _filtroTipoUbicacion,
                                    hint: const Text('Filtro Ubicación', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                    items: const [
                                      DropdownMenuItem(value: null, child: Text('Ubicación: Todas', style: TextStyle(fontSize: 12, color: Colors.greenAccent))),
                                      DropdownMenuItem(value: 'BODEGA', child: Text('📦 BODEGA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                                      DropdownMenuItem(value: 'PISO', child: Text('🏪 PISO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                                      DropdownMenuItem(value: 'DISPLAY', child: Text('✨ DISPLAY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                                    ],
                                    onChanged: (v) => setState(() {
                                      _filtroTipoUbicacion = v;
                                      _filtroMueble = null;
                                    }),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(left: 4, bottom: 4),
                                child: Text('Filtro Mes', style: TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold)),
                              ),
                              Container(
                                height: 40,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int?>(
                                    isExpanded: true,
                                    dropdownColor: const Color(0xFF2C2C2C),
                                    value: _filtroMes,
                                    hint: const Text('Filtro Mes', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                    items: [
                                      const DropdownMenuItem<int?>(
                                        value: null,
                                        child: Text('Mes: Todos (Top 100)', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                                      ),
                                      ..._nombresMeses.entries.map((e) => DropdownMenuItem<int?>(
                                            value: e.key,
                                            child: Text('📅 ${e.value}', style: const TextStyle(fontSize: 12)),
                                          )),
                                    ],
                                    onChanged: (v) => setState(() => _filtroMes = v),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_filtroTipoUbicacion != null) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                                  child: Text('Muebles en $_filtroTipoUbicacion', style: const TextStyle(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                                ),
                                Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(color: Colors.cyanAccent.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.cyanAccent.withOpacity(0.4))),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String?>(
                                      isExpanded: true,
                                      dropdownColor: const Color(0xFF2C2C2C),
                                      value: (mueblesDisponibles.contains(_filtroMueble)) ? _filtroMueble : null,
                                      hint: const Text('Nombre del mueble', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                      items: [
                                        DropdownMenuItem(value: null, child: Text('Todos (${mueblesDisponibles.length})', style: const TextStyle(fontSize: 12, color: Colors.greenAccent))),
                                        ...mueblesDisponibles.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))
                                      ],
                                      onChanged: (v) => setState(() => _filtroMueble = v),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                          String docId = docsFinales[i].id;
                          DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
                          int dias = cad.difference(DateTime.now()).inDays;
                          Map<String, dynamic> etiqueta = EtiquetaMes.obtener(cad);
                          bool isSelected = _seleccionados.contains(docId);
                          
                          return Card(
                            color: isSelected ? Colors.redAccent.withOpacity(0.2) : Colors.white10,
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: isSelected ? Colors.redAccent : Colors.white24, width: isSelected ? 2 : 1)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              onLongPress: () {
                                if (!_modoSeleccion) {
                                  setState(() {
                                    _modoSeleccion = true;
                                    _seleccionados.add(docId);
                                  });
                                }
                              },
                              onTap: () {
                                if (_modoSeleccion) {
                                  setState(() {
                                    if (isSelected) {
                                      _seleccionados.remove(docId);
                                      if (_seleccionados.isEmpty) _modoSeleccion = false;
                                    } else {
                                      _seleccionados.add(docId);
                                    }
                                  });
                                } else {
                                  _verDetalleCompleto(docsFinales[i]);
                                }
                              }, 
                              leading: Container(
                                width: 45, height: 45,
                                decoration: BoxDecoration(color: etiqueta['color'].withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: etiqueta['color'])),
                                child: Center(child: Text(dias.toString(), style: TextStyle(color: etiqueta['color'], fontWeight: FontWeight.bold, fontSize: 14))),
                              ),
                              title: Text(d['descripcion'] ?? d['sku'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d['cantidad'].toString() + ' pzas • Ubicación: ' + d['ubicacion'].toString(), style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
                                    if (d['enPromocion'] == true)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text('🏷️ EN PROMOCIÓN / SALDADO (${d['piezasEnPromocion'] ?? d['cantidad']} pzas) - Pendiente venta o baja', style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                    if (_filtroDescuadreSAP)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          '📊 Físico Tienda: ${sumaFisicaPorSku[(d['sku'] ?? '').toString()] ?? d['cantidad']} pzas  vs  SAP (OH): ${d['oh'] ?? 0} pzas',
                                          style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    if (d['comentarioCorporativo'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          d['instruccionCorpEjecutada'] == true
                                              ? '✅ CORP EJECUTADO (${d['motivoEjecucionCorp'] ?? 'Atendido'}): ${d['comentarioCorporativo']}'
                                              : 'INSTRUCCIÓN: ${d['comentarioCorporativo']}',
                                          style: TextStyle(
                                            color: d['instruccionCorpEjecutada'] == true ? Colors.greenAccent : Colors.pinkAccent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                  ],
                                ),
                              ),
                              trailing: _modoSeleccion
                                  ? Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked, color: isSelected ? Colors.redAccent : Colors.white54)
                                  : const Icon(Icons.info_outline, color: Colors.white54),
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
      appBar: AppBar(title: const Text('Escanear SKU / UPC para buscar', style: TextStyle(color: Colors.amber))),
      body: MobileScanner(
        onDetect: (capture) {
          if (_yaEscaneado) return; 
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
