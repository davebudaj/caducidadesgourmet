import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../modelos/selector_jerarquico_ubicacion.dart';

class PantallaIngreso extends StatefulWidget {
  final String usuario;
  final String idTiendaGlobal;
  const PantallaIngreso({super.key, required this.usuario, required this.idTiendaGlobal});
  @override
  State<PantallaIngreso> createState() => _PantallaIngresoState();
}

class _PantallaIngresoState extends State<PantallaIngreso> {
  final TextEditingController _fechaCtrl = TextEditingController();
  final TextEditingController _skuCtrl = TextEditingController();
  final TextEditingController _cantCtrl = TextEditingController(text: '1');
  final FocusNode _skuFocus = FocusNode();

  List<Map<String, dynamic>> _manifiesto = [];
  bool _guardando = false;

  DateTime? _parsearFecha(String input) {
    String clean = input.replaceAll(RegExp(r'[^0-9]'), ''); 
    try {
      if (clean.length == 6) {
        int d = int.parse(clean.substring(0, 2));
        int m = int.parse(clean.substring(2, 4));
        int y = int.parse(clean.substring(4, 6)) + 2000;
        return DateTime(y, m, d);
      } else if (clean.length == 8) {
        int d = int.parse(clean.substring(0, 2));
        int m = int.parse(clean.substring(2, 4));
        int y = int.parse(clean.substring(4, 8));
        return DateTime(y, m, d);
      }
    } catch (e) {}
    return null;
  }

  void _agregarItem(String codigoIngresado) async {
    String codigo = codigoIngresado.trim();
    if (codigo.isEmpty) return;
    DateTime? cad = _parsearFecha(_fechaCtrl.text);
    
    if (cad == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Formato de fecha inválido. Usa DD/MM/AA'), backgroundColor: Colors.redAccent));
      _skuCtrl.clear();
      _skuFocus.requestFocus();
      return;
    }
    
    int cant = int.tryParse(_cantCtrl.text) ?? 1;

    String skuOficial = codigo;
    String eanOficial = '';
    String desc = 'Buscando...';
    String prov = 'ND';
    String gpo = 'SIN GRUPO';
    Map<String, dynamic>? masterData;

    masterData = await JerarquiaUbicacionHelper.buscarProductoMaestro(codigo);

    if (masterData != null) {
      // Conversión automática de UPC a SKU Oficial
      if (masterData['sku'] != null && masterData['sku'].toString().trim().isNotEmpty) {
        skuOficial = masterData['sku'].toString().trim();
      }
      eanOficial = (masterData['ean'] ?? '').toString().trim();
      desc = masterData['descripcion'] ?? 'Sin Nombre';
      prov = masterData['nombreProveedor'] ?? 'ND';
      gpo = masterData['nombreGpoArticulos'] ?? 'SIN GRUPO';
    } else {
      desc = 'ARTÍCULO NUEVO / NO EN CATÁLOGO';
    }

    String fechaEstandar = "${cad.day.toString().padLeft(2, '0')}/${cad.month.toString().padLeft(2, '0')}/${cad.year}";

    setState(() {
      // Unificar lote si tiene el mismo SKU Oficial y la misma Fecha de Caducidad
      int idx = _manifiesto.indexWhere((e) {
        DateTime fExistente = e['fechaCaducidad'] as DateTime;
        return e['sku'] == skuOficial &&
               fExistente.year == cad.year &&
               fExistente.month == cad.month &&
               fExistente.day == cad.day;
      });

      if (idx != -1) {
        _manifiesto[idx]['cantidad'] += cant;
      } else {
        _manifiesto.insert(0, {
          'sku': skuOficial,
          'ean': eanOficial,
          'descripcion': desc,
          'cantidad': cant,
          'fechaCaducidad': cad,
          'fechaRaw': fechaEstandar,
          'nombreProveedor': prov,
          'nombreGpoArticulos': gpo,
          'datosMaestros': masterData
        });
      }
    });

    _skuCtrl.clear();
    _cantCtrl.text = '1';
    _skuFocus.requestFocus();
  }

  Future<void> _guardarManifiesto() async {
    if (_manifiesto.isEmpty) return;
    setState(() => _guardando = true);
    
    var refTienda = FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal);
    var batch = FirebaseFirestore.instance.batch();
    
    for (var item in _manifiesto) {
      DateTime cad = item['fechaCaducidad'] as DateTime;
      Timestamp tsCad = Timestamp.fromDate(cad);

      // Verificar si ya existe el mismo lote (SKU + Fecha) en OPERACION TIENDA para unificarlo
      var existenteSnap = await refTienda.collection('inventario_activo')
          .where('sku', isEqualTo: item['sku'])
          .where('ubicacion', isEqualTo: 'OPERACION TIENDA')
          .get();

      QueryDocumentSnapshot? docExistente;
      for (var d in existenteSnap.docs) {
        DateTime fDoc = (d['fechaCaducidad'] as Timestamp).toDate();
        if (fDoc.year == cad.year && fDoc.month == cad.month && fDoc.day == cad.day) {
          docExistente = d;
          break;
        }
      }

      if (docExistente != null) {
        int cantActual = docExistente['cantidad'] ?? 0;
        batch.update(docExistente.reference, {'cantidad': cantActual + (item['cantidad'] as int)});
      } else {
        var ref = refTienda.collection('inventario_activo').doc();
        bool esTemp = item['datosMaestros'] == null || item['datosMaestros']['esTemporal'] == true;
        Map<String, dynamic> data = {
          'sku': item['sku'],
          'codigoOriginalCapturado': item['ean'] != null && item['ean'].toString().isNotEmpty ? item['ean'] : item['sku'],
          if (esTemp && item['descripcion'] != 'ARTÍCULO NUEVO / NO EN CATÁLOGO') 'edicionTemporal': true,
          'ean': item['ean'] ?? '',
          'descripcion': item['descripcion'],
          'cantidad': item['cantidad'],
          'fechaCaducidad': tsCad,
          'ubicacion': 'OPERACION TIENDA',
          'nombreProveedor': item['nombreProveedor'],
          'nombreGpoArticulos': item['nombreGpoArticulos'],
          'fechaCaptura': FieldValue.serverTimestamp(),
          'capturista': widget.usuario
        };
        if (item['datosMaestros'] != null) {
          data.addAll({
            'idProveedor': item['datosMaestros']['idProveedor'],
            'idCategoria': item['datosMaestros']['idCategoria'],
            'precioVenta': item['datosMaestros']['precioVenta'],
            'oh': item['datosMaestros']['oh'],
          });
        }
        batch.set(ref, data);
      }
    }

    var ubiSnap = await refTienda.collection('ubicaciones').where('nombre', isEqualTo: 'OPERACION TIENDA').get();
    if (ubiSnap.docs.isEmpty) {
      batch.set(refTienda.collection('ubicaciones').doc(), {'nombre': 'OPERACION TIENDA'});
    }

    await batch.commit();
    
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Manifiesto recibido y unificado en OPERACION TIENDA'), backgroundColor: Colors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recepción de Manifiesto', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _fechaCtrl,
                      decoration: const InputDecoration(labelText: 'Fecha de Caducidad', hintText: 'Ej. 01.09.26 o 01/09/2026', filled: true, fillColor: Colors.black45, border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _cantCtrl,
                      decoration: const InputDecoration(labelText: 'Cant.', filled: true, fillColor: Colors.black45, border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _skuCtrl,
              focusNode: _skuFocus,
              decoration: InputDecoration(
                labelText: 'Escanear SKU / UPC...',
                prefixIcon: const Icon(Icons.qr_code_scanner, color: Colors.blueAccent),
                filled: true,
                fillColor: Colors.blueAccent.withOpacity(0.1),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.blueAccent, width: 2)),
              ),
              autofocus: true,
              onSubmitted: _agregarItem,
            ),
            const SizedBox(height: 15),
            const Align(alignment: Alignment.centerLeft, child: Text('Carrito de Recepción:', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))),
            Expanded(
              child: ListView.builder(
                itemCount: _manifiesto.length,
                itemBuilder: (context, i) {
                  var item = _manifiesto[i];
                  return Card(
                    color: Colors.white10,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: Colors.amber, child: Text(item['cantidad'].toString(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
                      title: Text(item['descripcion'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: Text('SKU: ${item['sku']} • Vence: ${item['fechaRaw']}\nUPC: ${JerarquiaUbicacionHelper.obtenerUpcVisual(item)} • Prov: ${item['nombreProveedor']}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => setState(() => _manifiesto.removeAt(i))),
                    ),
                  );
                },
              ),
            ),
            if (_manifiesto.isNotEmpty)
              SizedBox(
                width: double.infinity, height: 60,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
                  icon: _guardando ? const CircularProgressIndicator() : const Icon(Icons.save_alt, size: 28),
                  label: Text(_guardando ? 'GUARDANDO...' : 'GUARDAR MANIFIESTO (${_manifiesto.length} lotes)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  onPressed: _guardando ? null : _guardarManifiesto,
                ),
              )
          ],
        ),
      ),
    );
  }
}
