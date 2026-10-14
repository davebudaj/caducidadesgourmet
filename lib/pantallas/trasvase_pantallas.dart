import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PantallaTrasvaseMasivo extends StatefulWidget {
  final String idTiendaGlobal;
  final String usuarioRegistra;
  final String? ubicacionInicial;
  final String? skuFiltroInicial;

  const PantallaTrasvaseMasivo({
    super.key,
    required this.idTiendaGlobal,
    required this.usuarioRegistra,
    this.ubicacionInicial,
    this.skuFiltroInicial,
  });

  @override
  State<PantallaTrasvaseMasivo> createState() => _PantallaTrasvaseMasivoState();
}

class _PantallaTrasvaseMasivoState extends State<PantallaTrasvaseMasivo> {
  static const String kUbicacionTransito = 'EN TRÁNSITO';
  bool _cargandoDatos = true;
  bool _procesandoExtraccion = false;

  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _lotesPorUbicacion = {};
  List<String> _listaUbicaciones = [];
  String? _ubicacionSeleccionada;
  final Map<String, int> _cantidadesSeleccionadas = {};
  late TextEditingController _searchCtrl;
  String _busquedaInterna = '';

  CollectionReference<Map<String, dynamic>> get _refInv =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('inventario_activo');

  CollectionReference<Map<String, dynamic>> get _refUbi =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('ubicaciones');

  @override
  void initState() {
    super.initState();
    _busquedaInterna = (widget.skuFiltroInicial ?? '').toLowerCase();
    _searchCtrl = TextEditingController(text: widget.skuFiltroInicial ?? '');
    _cargarInventarioYUbicaciones();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarInventarioYUbicaciones() async {
    setState(() => _cargandoDatos = true);
    try {
      var results = await Future.wait([_refInv.get(), _refUbi.orderBy('nombre').get()]);
      var invSnap = results[0];
      var ubiSnap = results[1];

      Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> agrupado = {};
      for (var doc in invSnap.docs) {
        String ubi = (doc.data()['ubicacion'] ?? 'SIN UBICACIÓN').toString();
        if (ubi == kUbicacionTransito) continue;
        agrupado.putIfAbsent(ubi, () => []);
        agrupado[ubi]!.add(doc);
      }

      for (var lista in agrupado.values) {
        lista.sort((a, b) {
          Timestamp tA = a.data()['fechaCaducidad'] ?? Timestamp.now();
          Timestamp tB = b.data()['fechaCaducidad'] ?? Timestamp.now();
          return tA.compareTo(tB);
        });
      }

      Set<String> todasUbis = {...agrupado.keys, ...ubiSnap.docs.map((d) => d['nombre'].toString())};
      todasUbis.remove(kUbicacionTransito);
      List<String> ordenadas = todasUbis.toList()..sort();

      String? ubiInicial = widget.ubicacionInicial;
      if (ubiInicial == null || !ordenadas.contains(ubiInicial)) {
        if (agrupado.containsKey('OPERACION TIENDA')) {
          ubiInicial = 'OPERACION TIENDA';
        } else if (agrupado.isNotEmpty) {
          ubiInicial = agrupado.keys.first;
        } else if (ordenadas.isNotEmpty) {
          ubiInicial = ordenadas.first;
        }
      }

      if (mounted) {
        setState(() {
          _lotesPorUbicacion = agrupado;
          _listaUbicaciones = ordenadas;
          _ubicacionSeleccionada = ubiInicial;
          _cargandoDatos = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargandoDatos = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  Future<int?> _pedirCantidadManual(int actual, int maximo, String descripcion) async {
    TextEditingController ctrl = TextEditingController(text: actual > 0 ? actual.toString() : '');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: Text(descripcion, style: const TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold), maxLines: 2),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Cantidad a mover (Máx: $maximo)', filled: true, fillColor: Colors.black45, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
            onPressed: () {
              int val = int.tryParse(ctrl.text.trim()) ?? 0;
              Navigator.pop(ctx, val.clamp(0, maximo));
            },
            child: const Text('ACEPTAR'),
          ),
        ],
      ),
    );
  }

  Future<void> _ejecutarExtraccionMasiva() async {
    setState(() => _procesandoExtraccion = true);
    try {
      var todosDocs = _lotesPorUbicacion.values.expand((x) => x).toList();
      var mapaDocs = {for (var d in todosDocs) d.id: d};
      var transitoSnap = await _refInv.where('ubicacion', isEqualTo: kUbicacionTransito).get();
      var docsEnTransito = transitoSnap.docs.toList();

      var batch = FirebaseFirestore.instance.batch();
      int lotesMovidos = 0;
      int piezasMovidas = 0;

      for (var entry in _cantidadesSeleccionadas.entries) {
        int cantMover = entry.value;
        if (cantMover <= 0) continue;
        var docOrigen = mapaDocs[entry.key];
        if (docOrigen == null) continue;

        var data = docOrigen.data();
        int cantActual = data['cantidad'] ?? 0;
        if (cantMover > cantActual) cantMover = cantActual;

        String sku = (data['sku'] ?? '').toString();
        DateTime fCad = (data['fechaCaducidad'] as Timestamp).toDate();
        String ubiOrigen = (data['ubicacion'] ?? 'SIN UBICACIÓN').toString();

        if (cantActual <= cantMover) {
          batch.delete(docOrigen.reference);
        } else {
          batch.update(docOrigen.reference, {'cantidad': cantActual - cantMover});
        }

        QueryDocumentSnapshot<Map<String, dynamic>>? loteExistente;
        for (var d in docsEnTransito) {
          var td = d.data();
          if (td['sku'] == sku && (td['ubicacionOrigen'] ?? '') == ubiOrigen) {
            DateTime fDoc = (td['fechaCaducidad'] as Timestamp).toDate();
            if (fDoc.year == fCad.year && fDoc.month == fCad.month && fDoc.day == fCad.day) {
              loteExistente = d;
              break;
            }
          }
        }

        if (loteExistente != null) {
          int cantEnCarrito = loteExistente.data()['cantidad'] ?? 0;
          batch.update(loteExistente.reference, {
            'cantidad': cantEnCarrito + cantMover,
            'fechaTransito': FieldValue.serverTimestamp(),
            'usuarioTransito': widget.usuarioRegistra,
          });
        } else {
          var nuevoLote = Map<String, dynamic>.from(data);
          nuevoLote['cantidad'] = cantMover;
          nuevoLote['ubicacion'] = kUbicacionTransito;
          nuevoLote['ubicacionOrigen'] = ubiOrigen;
          nuevoLote['fechaTransito'] = FieldValue.serverTimestamp();
          nuevoLote['usuarioTransito'] = widget.usuarioRegistra;
          batch.set(_refInv.doc(), nuevoLote);
        }
        lotesMovidos++;
        piezasMovidas += cantMover;
      }

      await batch.commit();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🛒 $lotesMovidos lotes ($piezasMovidas pzas) enviados al Carrito Temporal'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _procesandoExtraccion = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    var lotesActuales = _ubicacionSeleccionada != null ? (_lotesPorUbicacion[_ubicacionSeleccionada] ?? []) : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    var lotesFiltrados = lotesActuales.where((doc) {
      if (_busquedaInterna.isEmpty) return true;
      var d = doc.data();
      return (d['descripcion'] ?? '').toString().toLowerCase().contains(_busquedaInterna) ||
          (d['sku'] ?? '').toString().toLowerCase().contains(_busquedaInterna) ||
          (d['ean'] ?? '').toString().toLowerCase().contains(_busquedaInterna);
    }).toList();

    int totalLotesMarcados = _cantidadesSeleccionadas.values.where((v) => v > 0).length;
    int totalPiezasMarcadas = _cantidadesSeleccionadas.values.fold(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trasvase Masivo (Extraer)', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.amber), onPressed: _cargandoDatos ? null : _cargarInventarioYUbicaciones),
        ],
      ),
      body: _cargandoDatos
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blueAccent, width: 1.5)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        dropdownColor: const Color(0xFF2C2C2C),
                        value: _ubicacionSeleccionada,
                        hint: const Text('Selecciona Ubicación de Origen', style: TextStyle(color: Colors.white70)),
                        items: _listaUbicaciones.map((u) {
                          int count = _lotesPorUbicacion[u]?.length ?? 0;
                          return DropdownMenuItem<String>(
                            value: u,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text('📍 $u', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
                                Text('$count lotes', style: TextStyle(fontSize: 11, color: count > 0 ? Colors.greenAccent : Colors.white38, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _ubicacionSeleccionada = val),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText: 'Filtrar SKU o descripción...',
                              hintStyle: const TextStyle(fontSize: 12),
                              prefixIcon: const Icon(Icons.search, size: 18, color: Colors.amber),
                              filled: true,
                              fillColor: Colors.white10,
                              contentPadding: EdgeInsets.zero,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            ),
                            onChanged: (v) => setState(() => _busquedaInterna = v.toLowerCase()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.withOpacity(0.2), foregroundColor: Colors.amber, side: const BorderSide(color: Colors.amber)),
                        icon: const Icon(Icons.done_all, size: 16),
                        label: const Text('TODO EL MUEBLE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        onPressed: lotesFiltrados.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  bool todosMarcados = lotesFiltrados.every((doc) => (_cantidadesSeleccionadas[doc.id] ?? 0) == (doc.data()['cantidad'] ?? 0));
                                  for (var doc in lotesFiltrados) {
                                    _cantidadesSeleccionadas[doc.id] = todosMarcados ? 0 : (doc.data()['cantidad'] ?? 0);
                                  }
                                });
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: lotesFiltrados.isEmpty
                        ? const Center(child: Text('No hay lotes en esta ubicación.', style: TextStyle(color: Colors.white54)))
                        : ListView.builder(
                            itemCount: lotesFiltrados.length,
                            itemBuilder: (context, i) {
                              var doc = lotesFiltrados[i];
                              var d = doc.data();
                              String docId = doc.id;
                              DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
                              int dias = cad.difference(DateTime.now()).inDays;
                              String fechaFormateada = "${cad.day.toString().padLeft(2, '0')}/${cad.month.toString().padLeft(2, '0')}/${cad.year}";
                              int maximoPermitido = d['cantidad'] ?? 0;
                              int cantActual = _cantidadesSeleccionadas[docId] ?? 0;
                              bool seleccionado = cantActual > 0;

                              return Card(
                                color: seleccionado ? Colors.blueAccent.withOpacity(0.18) : Colors.white10,
                                margin: const EdgeInsets.symmetric(vertical: 5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: seleccionado ? Colors.blueAccent : Colors.white12, width: seleccionado ? 2 : 1)),
                                child: Padding(
                                  padding: const EdgeInsets.all(10.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Checkbox(
                                            value: seleccionado,
                                            activeColor: Colors.blueAccent,
                                            onChanged: (val) => setState(() => _cantidadesSeleccionadas[docId] = (val == true) ? maximoPermitido : 0),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(d['descripcion'] ?? d['sku'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                Text('SKU: ${d['sku']} • Prov: ${d['nombreProveedor'] ?? 'ND'}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('📅 Cad: $fechaFormateada ($dias d)', style: TextStyle(color: dias <= 15 ? Colors.redAccent : Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                              Text('📦 Existencia: $maximoPermitido pzas', style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              InkWell(
                                                onTap: () => setState(() => _cantidadesSeleccionadas[docId] = maximoPermitido),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                                  decoration: BoxDecoration(color: cantActual == maximoPermitido ? Colors.amber : Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber)),
                                                  child: Text('TODO', style: TextStyle(color: cantActual == maximoPermitido ? Colors.black : Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              IconButton(
                                                icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 26),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                onPressed: cantActual > 0 ? () => setState(() => _cantidadesSeleccionadas[docId] = cantActual - 1) : null,
                                              ),
                                              const SizedBox(width: 6),
                                              InkWell(
                                                onTap: () async {
                                                  int? nuevaCant = await _pedirCantidadManual(cantActual, maximoPermitido, d['descripcion'] ?? d['sku']);
                                                  if (nuevaCant != null) setState(() => _cantidadesSeleccionadas[docId] = nuevaCant);
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white24)),
                                                  child: Text(cantActual.toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              IconButton(
                                                icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent, size: 26),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                onPressed: cantActual < maximoPermitido ? () => setState(() => _cantidadesSeleccionadas[docId] = cantActual + 1) : null,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      icon: _procesandoExtraccion ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.shopping_cart_checkout, size: 24),
                      label: Text(_procesandoExtraccion ? 'ENVIANDO...' : 'ENVIAR AL CARRITO TEMPORAL ($totalLotesMarcados lotes • $totalPiezasMarcadas pzas)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: (totalLotesMarcados == 0 || _procesandoExtraccion) ? null : _ejecutarExtraccionMasiva,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class PantallaCarritoTemporal extends StatefulWidget {
  final String idTiendaGlobal;
  final String usuarioRegistra;
  final String? destinoPreseleccionado;

  const PantallaCarritoTemporal({
    super.key,
    required this.idTiendaGlobal,
    required this.usuarioRegistra,
    this.destinoPreseleccionado,
  });

  @override
  State<PantallaCarritoTemporal> createState() => _PantallaCarritoTemporalState();
}

class _PantallaCarritoTemporalState extends State<PantallaCarritoTemporal> {
  static const String kUbicacionTransito = 'EN TRÁNSITO';
  bool _cargando = true;
  bool _procesandoEntrega = false;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docsTransito = [];
  List<String> _listaMuebles = [];
  String? _muebleDestino;
  final Map<String, int> _cantidadesADejar = {};

  CollectionReference<Map<String, dynamic>> get _refInv =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('inventario_activo');

  CollectionReference<Map<String, dynamic>> get _refUbi =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('ubicaciones');

  @override
  void initState() {
    super.initState();
    _muebleDestino = (widget.destinoPreseleccionado != null && widget.destinoPreseleccionado != 'Sin anclar') ? widget.destinoPreseleccionado : null;
    _cargarCarritoYMuebles();
  }

  Future<void> _cargarCarritoYMuebles() async {
    setState(() => _cargando = true);
    try {
      var results = await Future.wait([
        _refInv.where('ubicacion', isEqualTo: kUbicacionTransito).get(),
        _refUbi.orderBy('nombre').get(),
      ]);
      var transitoSnap = results[0];
      var ubiSnap = results[1];

      List<String> muebles = ubiSnap.docs.map((d) => d['nombre'].toString()).where((n) => n != kUbicacionTransito).toList();
      if (_muebleDestino != null && !muebles.contains(_muebleDestino)) muebles.add(_muebleDestino!);

      var docs = transitoSnap.docs.toList();
      docs.sort((a, b) {
        Timestamp tA = a.data()['fechaCaducidad'] ?? Timestamp.now();
        Timestamp tB = b.data()['fechaCaducidad'] ?? Timestamp.now();
        return tA.compareTo(tB);
      });

      _cantidadesADejar.clear();
      for (var d in docs) {
        _cantidadesADejar[d.id] = (d.data()['cantidad'] ?? 0) as int;
      }

      if (mounted) {
        setState(() {
          _docsTransito = docs;
          _listaMuebles = muebles;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<int?> _pedirCantidadManual(int actual, int maximo, String descripcion) async {
    TextEditingController ctrl = TextEditingController(text: actual > 0 ? actual.toString() : '');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: Text(descripcion, style: const TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold), maxLines: 2),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Piezas a dejar aquí (Máx: $maximo)', filled: true, fillColor: Colors.black45, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
            onPressed: () {
              int val = int.tryParse(ctrl.text.trim()) ?? 0;
              Navigator.pop(ctx, val.clamp(0, maximo));
            },
            child: const Text('ACEPTAR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _ejecutarEntregaEnDestino(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> lotesAProcesar,
    Map<String, int> mapaCantidades,
    String destinoFinal, {
    bool cerrarAlTerminar = true,
  }) async {
    setState(() => _procesandoEntrega = true);
    try {
      var destinoSnap = await _refInv.where('ubicacion', isEqualTo: destinoFinal).get();
      var docsEnDestino = destinoSnap.docs.toList();
      var mapaDocs = {for (var d in lotesAProcesar) d.id: d};
      var batch = FirebaseFirestore.instance.batch();
      int piezasEntregadas = 0;

      for (var entry in mapaCantidades.entries) {
        int cantDejar = entry.value;
        if (cantDejar <= 0) continue;
        var docCarrito = mapaDocs[entry.key];
        if (docCarrito == null) continue;

        var data = docCarrito.data();
        int cantActualEnCarrito = data['cantidad'] ?? 0;
        if (cantDejar > cantActualEnCarrito) cantDejar = cantActualEnCarrito;

        String sku = (data['sku'] ?? '').toString();
        DateTime fCad = (data['fechaCaducidad'] as Timestamp).toDate();

        if (cantActualEnCarrito <= cantDejar) {
          batch.delete(docCarrito.reference);
        } else {
          batch.update(docCarrito.reference, {'cantidad': cantActualEnCarrito - cantDejar});
        }

        QueryDocumentSnapshot<Map<String, dynamic>>? loteIgual;
        for (var d in docsEnDestino) {
          var dd = d.data();
          if (dd['sku'] == sku) {
            DateTime fDoc = (dd['fechaCaducidad'] as Timestamp).toDate();
            if (fDoc.year == fCad.year && fDoc.month == fCad.month && fDoc.day == fCad.day) {
              loteIgual = d;
              break;
            }
          }
        }

        if (loteIgual != null) {
          int cantDestino = loteIgual.data()['cantidad'] ?? 0;
          batch.update(loteIgual.reference, {'cantidad': cantDestino + cantDejar});
        } else {
          var nuevoData = Map<String, dynamic>.from(data);
          nuevoData['cantidad'] = cantDejar;
          nuevoData['ubicacion'] = destinoFinal;
          nuevoData['fechaCaptura'] = FieldValue.serverTimestamp();
          nuevoData.remove('ubicacionOrigen');
          nuevoData.remove('fechaTransito');
          nuevoData.remove('usuarioTransito');
          nuevoData.remove('misionTransitoGenerada');
          batch.set(_refInv.doc(), nuevoData);
        }
        piezasEntregadas += cantDejar;
      }

      await batch.commit();
      if (mounted) {
        if (cerrarAlTerminar) {
          Navigator.pop(context, destinoFinal);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ $piezasEntregadas piezas acomodadas en $destinoFinal'), backgroundColor: Colors.green),
          );
        } else {
          await _cargarCarritoYMuebles();
          setState(() => _procesandoEntrega = false);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _procesandoEntrega = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    int lotesElegidos = _cantidadesADejar.values.where((v) => v > 0).length;
    int piezasElegidas = _cantidadesADejar.values.fold(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carrito Temporal (En Tránsito)', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.amber), onPressed: _cargando ? null : _cargarCarritoYMuebles),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: _muebleDestino != null ? Colors.green.withOpacity(0.15) : Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _muebleDestino != null ? Colors.greenAccent : Colors.deepOrangeAccent, width: 1.5),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        dropdownColor: const Color(0xFF2C2C2C),
                        value: _muebleDestino,
                        hint: const Text('🎯 1. Selecciona el MUEBLE DESTINO aquí...', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                        items: _listaMuebles.map((u) => DropdownMenuItem<String>(value: u, child: Text('🎯 Destino: $u', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)))).toList(),
                        onChanged: (val) => setState(() => _muebleDestino = val),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => setState(() {
                          for (var d in _docsTransito) {
                            _cantidadesADejar[d.id] = 0;
                          }
                        }),
                        child: const Text('Desmarcar todo', style: TextStyle(fontSize: 11, color: Colors.white54)),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          for (var d in _docsTransito) {
                            _cantidadesADejar[d.id] = (d.data()['cantidad'] ?? 0) as int;
                          }
                        }),
                        child: const Text('Seleccionar todo', style: TextStyle(fontSize: 11, color: Colors.amber)),
                      ),
                    ],
                  ),
                  Expanded(
                    child: _docsTransito.isEmpty
                        ? const Center(child: Text('¡El Carrito Temporal está limpio!', style: TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.bold)))
                        : ListView.builder(
                            itemCount: _docsTransito.length,
                            itemBuilder: (context, i) {
                              var doc = _docsTransito[i];
                              var d = doc.data();
                              String docId = doc.id;
                              DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
                              String fechaFormateada = "${cad.day.toString().padLeft(2, '0')}/${cad.month.toString().padLeft(2, '0')}/${cad.year}";
                              String origen = (d['ubicacionOrigen'] ?? 'OPERACION TIENDA').toString();
                              int maxEnCarrito = d['cantidad'] ?? 0;
                              int cantElegida = _cantidadesADejar[docId] ?? 0;
                              bool activo = cantElegida > 0;

                              return Card(
                                color: activo ? Colors.green.withOpacity(0.15) : Colors.white10,
                                margin: const EdgeInsets.symmetric(vertical: 5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: activo ? Colors.greenAccent : Colors.white12, width: activo ? 2 : 1)),
                                child: Padding(
                                  padding: const EdgeInsets.all(10.0),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Checkbox(
                                            value: activo,
                                            activeColor: Colors.greenAccent,
                                            checkColor: Colors.black,
                                            onChanged: (v) => setState(() => _cantidadesADejar[docId] = (v == true) ? maxEnCarrito : 0),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(d['descripcion'] ?? d['sku'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                Text('SKU: ${d['sku']} • Salió de: $origen', style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.settings_backup_restore, color: Colors.orangeAccent),
                                            tooltip: 'Devolver a $origen',
                                            onPressed: _procesandoEntrega ? null : () => _ejecutarEntregaEnDestino([doc], {docId: maxEnCarrito}, origen, cerrarAlTerminar: false),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('📅 Cad: $fechaFormateada', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                              Text('🛒 En carrito: $maxEnCarrito pzas', style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              InkWell(
                                                onTap: () => setState(() => _cantidadesADejar[docId] = maxEnCarrito),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                                  decoration: BoxDecoration(color: cantElegida == maxEnCarrito ? Colors.amber : Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber)),
                                                  child: Text('TODO', style: TextStyle(color: cantElegida == maxEnCarrito ? Colors.black : Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              IconButton(
                                                icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 26),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                onPressed: cantElegida > 0 ? () => setState(() => _cantidadesADejar[docId] = cantElegida - 1) : null,
                                              ),
                                              const SizedBox(width: 6),
                                              InkWell(
                                                onTap: () async {
                                                  int? nuevaCant = await _pedirCantidadManual(cantElegida, maxEnCarrito, d['descripcion'] ?? d['sku']);
                                                  if (nuevaCant != null) setState(() => _cantidadesADejar[docId] = nuevaCant);
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white24)),
                                                  child: Text(cantElegida.toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              IconButton(
                                                icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent, size: 26),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                onPressed: cantElegida < maxEnCarrito ? () => setState(() => _cantidadesADejar[docId] = cantElegida + 1) : null,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      icon: _procesandoEntrega ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) : const Icon(Icons.archive, size: 24),
                      label: Text(
                        _procesandoEntrega ? 'ACOMODANDO...' : (_muebleDestino == null ? 'SELECCIONA UN MUEBLE DESTINO ARRIBA' : 'DEJAR EN $_muebleDestino ($lotesElegidos lotes • $piezasElegidas pzas)'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      onPressed: (_muebleDestino == null || lotesElegidos == 0 || _procesandoEntrega) ? null : () => _ejecutarEntregaEnDestino(_docsTransito, _cantidadesADejar, _muebleDestino!),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
