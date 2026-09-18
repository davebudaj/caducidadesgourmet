import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PantallaIngreso extends StatefulWidget {
  final String usuario;
  const PantallaIngreso({super.key, required this.usuario});
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

  // Algoritmo inteligente para leer formatos como 01.09.2026, 01/09/26, 010926
  DateTime? _parsearFecha(String input) {
    String clean = input.replaceAll(RegExp(r'[^0-9]'), ''); 
    try {
      if (clean.length == 6) { // ddmmyy
        int d = int.parse(clean.substring(0, 2));
        int m = int.parse(clean.substring(2, 4));
        int y = int.parse(clean.substring(4, 6)) + 2000;
        return DateTime(y, m, d);
      } else if (clean.length == 8) { // ddmmyyyy
        int d = int.parse(clean.substring(0, 2));
        int m = int.parse(clean.substring(2, 4));
        int y = int.parse(clean.substring(4, 8));
        return DateTime(y, m, d);
      }
    } catch (e) {}
    return null;
  }

  void _agregarItem(String sku) async {
    if (sku.isEmpty) return;
    DateTime? cad = _parsearFecha(_fechaCtrl.text);
    
    if (cad == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Formato de fecha inválido. Usa DD/MM/AA'), backgroundColor: Colors.redAccent));
      _skuCtrl.clear();
      _skuFocus.requestFocus();
      return;
    }
    
    int cant = int.tryParse(_cantCtrl.text) ?? 1;

    // Buscar datos maestros rápidamente
    String desc = 'Buscando...';
    String prov = 'ND';
    String gpo = 'SIN GRUPO';
    Map<String, dynamic>? masterData;

    var doc = await FirebaseFirestore.instance.collection('maestro_productos').doc(sku).get();
    if (doc.exists) {
      masterData = doc.data();
      desc = masterData?['descripcion'] ?? 'Sin Nombre';
      prov = masterData?['nombreProveedor'] ?? 'ND';
      gpo = masterData?['nombreGpoArticulos'] ?? 'SIN GRUPO';
    } else {
      desc = 'ARTÍCULO NUEVO / NO EN CATÁLOGO';
    }

    setState(() {
      int idx = _manifiesto.indexWhere((e) => e['sku'] == sku && e['fechaRaw'] == _fechaCtrl.text);
      if (idx != -1) {
        _manifiesto[idx]['cantidad'] += cant; // Si escanea el mismo, suma la cantidad
      } else {
        _manifiesto.insert(0, {
          'sku': sku,
          'descripcion': desc,
          'cantidad': cant,
          'fechaCaducidad': cad,
          'fechaRaw': _fechaCtrl.text,
          'nombreProveedor': prov,
          'nombreGpoArticulos': gpo,
          'datosMaestros': masterData
        });
      }
    });

    _skuCtrl.clear();
    _cantCtrl.text = '1'; // Resetea cantidad a 1 por si la cambiaron
    _skuFocus.requestFocus(); // Vuelve a poner el cursor para el siguiente bip
  }

  Future<void> _guardarManifiesto() async {
    if (_manifiesto.isEmpty) return;
    setState(() => _guardando = true);
    
    var batch = FirebaseFirestore.instance.batch();
    
    for (var item in _manifiesto) {
      var ref = FirebaseFirestore.instance.collection('inventario_activo').doc();
      Map<String, dynamic> data = {
        'sku': item['sku'],
        'descripcion': item['descripcion'],
        'cantidad': item['cantidad'],
        'fechaCaducidad': Timestamp.fromDate(item['fechaCaducidad']),
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

    // Si la bodega no existe, la creamos
    var ubiSnap = await FirebaseFirestore.instance.collection('ubicaciones').where('nombre', isEqualTo: 'OPERACION TIENDA').get();
    if (ubiSnap.docs.isEmpty) {
      batch.set(FirebaseFirestore.instance.collection('ubicaciones').doc(), {'nombre': 'OPERACION TIENDA'});
    }

    await batch.commit();
    
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Manifiesto recibido en OPERACION TIENDA'), backgroundColor: Colors.green));
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
                      keyboardType: TextInputType.datetime,
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
              onSubmitted: _agregarItem, // Esta línea atrapa el "Enter" del escáner físico
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
                      subtitle: Text('SKU: ${item['sku']} • Vence: ${item['fechaRaw']}\nProv: ${item['nombreProveedor']}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
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
