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

  final List<Map<String, dynamic>> _manifiesto = [];
  bool _guardando = false;
  bool _alertaSinMatchActiva = false;

  @override
  void dispose() {
    _fechaCtrl.dispose();
    _skuCtrl.dispose();
    _cantCtrl.dispose();
    _skuFocus.dispose();
    super.dispose();
  }

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
    } catch (_) {}
    return null;
  }

  Future<bool> _mostrarAdvertenciaSinMatch(String codigoCapturado) async {
    setState(() => _alertaSinMatchActiva = true);
    _skuFocus.unfocus();
    FocusScope.of(context).unfocus();

    bool? resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1A24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Colors.purpleAccent, width: 2.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.add_a_photo_rounded, color: Colors.amber, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '⚠️ CÓDIGO SIN MATCH EN CATÁLOGO',
                  style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.purpleAccent),
                ),
                child: Text(
                  'Código escaneado: $codigoCapturado',
                  style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '📸 Por favor toma una fotografía del SKU, UPC y/o producto para su posterior validación.',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5, height: 1.35),
              ),
              const SizedBox(height: 10),
              const Text(
                '🔒 El escáner se encuentra pausado. Hasta que no presiones ACEPTAR no podrás continuar escaneando.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'DESCARTAR LECTURA',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
            // Usamos InkWell sin foco de teclado para que el Enter del láser Zebra no cierre la alerta por accidente
            InkWell(
              onTap: () => Navigator.pop(ctx, true),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: Colors.black, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'ACEPTAR (CONTINUAR)',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (mounted) {
      setState(() => _alertaSinMatchActiva = false);
    }
    return resultado == true;
  }

  void _agregarItem(String codigoIngresado) async {
    if (_alertaSinMatchActiva) return;
    String codigo = codigoIngresado.trim();
    if (codigo.isEmpty) return;
    DateTime? cad = _parsearFecha(_fechaCtrl.text);

    if (cad == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Formato de fecha inválido. Usa DD/MM/AA'), backgroundColor: Colors.redAccent),
      );
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
      if (masterData['sku'] != null && masterData['sku'].toString().trim().isNotEmpty) {
        skuOficial = masterData['sku'].toString().trim();
      }
      eanOficial = (masterData['ean'] ?? '').toString().trim();
      desc = masterData['descripcion'] ?? 'Sin Nombre';
      prov = masterData['nombreProveedor'] ?? 'ND';
      gpo = masterData['nombreGpoArticulos'] ?? 'SIN GRUPO';
    } else {
      bool confirmarAltaSinMatch = await _mostrarAdvertenciaSinMatch(codigo);
      if (!confirmarAltaSinMatch) {
        _skuCtrl.clear();
        _skuFocus.requestFocus();
        return;
      }
      desc = 'ARTÍCULO NUEVO / NO EN CATÁLOGO';
    }

    String fechaEstandar = "${cad.day.toString().padLeft(2, '0')}/${cad.month.toString().padLeft(2, '0')}/${cad.year}";

    setState(() {
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
          'datosMaestros': masterData,
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

      var existenteSnap = await refTienda
          .collection('inventario_activo')
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
          'capturista': widget.usuario,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manifiesto recibido y unificado en OPERACION TIENDA'), backgroundColor: Colors.green),
      );
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
                      decoration: const InputDecoration(
                        labelText: 'Fecha de Caducidad',
                        hintText: 'Ej. 01.09.26 o 01/09/2026',
                        filled: true,
                        fillColor: Colors.black45,
                        border: OutlineInputBorder(),
                      ),
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
              readOnly: _alertaSinMatchActiva,
              decoration: InputDecoration(
                labelText: _alertaSinMatchActiva ? '🔒 Confirma la advertencia en pantalla...' : 'Escanear SKU / UPC...',
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
                      leading: CircleAvatar(
                        backgroundColor: Colors.amber,
                        child: Text(item['cantidad'].toString(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(item['descripcion'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        'SKU: ${item['sku']} • Vence: ${item['fechaRaw']}\nUPC: ${JerarquiaUbicacionHelper.obtenerUpcVisual(item)} • Prov: ${item['nombreProveedor']}',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () => setState(() => _manifiesto.removeAt(i)),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_manifiesto.isNotEmpty)
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
                  icon: _guardando ? const CircularProgressIndicator() : const Icon(Icons.save_alt, size: 28),
                  label: Text(
                    _guardando ? 'GUARDANDO...' : 'GUARDAR MANIFIESTO (${_manifiesto.length} lotes)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  onPressed: _guardando ? null : _guardarManifiesto,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
