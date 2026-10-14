import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../modelos/etiqueta_mes.dart';
import 'ingreso.dart';
import 'login.dart';

class PantallaEscaner extends StatefulWidget {
  final bool estaActiva;
  final String usuarioRegistra;
  final String idTiendaGlobal;

  const PantallaEscaner({
    super.key,
    this.estaActiva = true,
    required this.usuarioRegistra,
    required this.idTiendaGlobal,
  });

  @override
  State<PantallaEscaner> createState() => _PantallaEscanerState();
}

class _PantallaEscanerState extends State<PantallaEscaner> with SingleTickerProviderStateMixin {
  final TextEditingController _skuController = TextEditingController();
  String? _ubicacionDestino;
  bool _modoTrasvase = false;

  late AnimationController _laserController;
  late Animation<double> _laserAnimation;
  bool _bloquearEscaneo = false;

  static const String kUbicacionTransito = 'EN TRÁNSITO';

  CollectionReference<Map<String, dynamic>> get _refInv =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('inventario_activo');

  CollectionReference<Map<String, dynamic>> get _refUbi =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('ubicaciones');

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _laserAnimation = Tween<double>(begin: 10.0, end: 180.0).animate(_laserController);
  }

  @override
  void dispose() {
    _laserController.dispose();
    _skuController.dispose();
    super.dispose();
  }

  Future<String> _obtenerSkuOficial(String codigo) async {
    var doc = await FirebaseFirestore.instance.collection('maestro_productos').doc(codigo).get();
    if (doc.exists) {
      var data = doc.data();
      if (data != null && data['sku'] != null && data['sku'].toString().trim().isNotEmpty) {
        return data['sku'].toString().trim();
      }
    } else {
      var qEan = await FirebaseFirestore.instance.collection('maestro_productos').where('ean', isEqualTo: codigo).limit(1).get();
      if (qEan.docs.isNotEmpty) {
        var data = qEan.docs.first.data();
        if (data['sku'] != null && data['sku'].toString().trim().isNotEmpty) {
          return data['sku'].toString().trim();
        }
      }
    }
    return codigo;
  }

  void _procesarEscaneo(String codigo) async {
    String codigoLimpio = codigo.trim();

    if (codigoLimpio.startsWith('LOC:')) {
      String muebleEscaneado = codigoLimpio.substring(4);
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.amber, width: 2)),
          title: Text('Mueble: $muebleEscaneado', style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
          content: const Text('¿Qué acción deseas realizar con esta ubicación?', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _ubicacionDestino = muebleEscaneado;
                  _skuController.clear();
                });
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('📍 Ubicación anclada: $_ubicacionDestino'), backgroundColor: Colors.green));
              },
              child: const Text('ANCLAR DESTINO', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrangeAccent, foregroundColor: Colors.white),
              icon: const Icon(Icons.local_shipping, size: 18),
              label: const Text('DEJAR CARRITO AQUÍ'),
              onPressed: () {
                Navigator.pop(context);
                setState(() => _ubicacionDestino = muebleEscaneado);
                _abrirCarritoEnTransito(destinoPreseleccionado: muebleEscaneado);
              },
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
              icon: const Icon(Icons.outbox, size: 18),
              label: const Text('EXTRAER LOTES'),
              onPressed: () {
                Navigator.pop(context);
                _abrirTrasvaseMasivo(ubicacionInicial: muebleEscaneado);
              },
            ),
          ],
        ),
      );
    } else if (codigoLimpio.isNotEmpty) {
      if (_modoTrasvase) {
        _seleccionarOrigenYCantidadPorSku(codigoLimpio);
      } else {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PantallaRegistro(
              skuEscaneado: codigoLimpio,
              ubicacionPredefinida: _ubicacionDestino,
              usuarioRegistra: widget.usuarioRegistra,
              idTiendaGlobal: widget.idTiendaGlobal,
            ),
          ),
        );
      }
      _skuController.clear();
    }

    if (mounted) setState(() => _bloquearEscaneo = false);
  }

  // --- ESCANEO DE UN SKU EN MODO TRASVASE (ENVÍA AL CARRITO EN TRÁNSITO) ---
  void _seleccionarOrigenYCantidadPorSku(String codigoBuscado) async {
    String skuOficial = await _obtenerSkuOficial(codigoBuscado);
    var snapshot = await _refInv.where('sku', isEqualTo: skuOficial).get();
    if (snapshot.docs.isEmpty && skuOficial != codigoBuscado) {
      snapshot = await _refInv.where('sku', isEqualTo: codigoBuscado).get();
    }
    if (snapshot.docs.isEmpty) {
      snapshot = await _refInv.where('ean', isEqualTo: codigoBuscado).get();
    }

    var docsDisponibles = snapshot.docs.where((d) => (d.data()['ubicacion'] ?? '') != kUbicacionTransito).toList();

    if (docsDisponibles.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay existencias disponibles fuera del carrito en tránsito.'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    _abrirTrasvaseMasivo(skuFiltroInicial: skuOficial);
  }

  // --- FUNCIÓN PARA PEDIR CANTIDAD MANUAL AL TOCAR EL NÚMERO ---
  Future<int?> _pedirCantidadManual(BuildContext context, int actual, int maximo, String descripcion) async {
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
          decoration: InputDecoration(
            labelText: 'Cantidad a mover (Máx: $maximo)',
            filled: true,
            fillColor: Colors.black45,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
            onPressed: () {
              int val = int.tryParse(ctrl.text.trim()) ?? 0;
              if (val < 0) val = 0;
              if (val > maximo) val = maximo;
              Navigator.pop(ctx, val);
            },
            child: const Text('ACEPTAR'),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 1. VENTANA DE TRASVASE MASIVO (SELECCIONAR UBICACIÓN -> EXTRAER AL CARRITO)
  // =========================================================================
  void _abrirTrasvaseMasivo({String? ubicacionInicial, String? skuFiltroInicial}) async {
    var invSnap = await _refInv.get();
    var ubiSnap = await _refUbi.orderBy('nombre').get();

    // Contar cuántos lotes tiene cada ubicación (excluyendo EN TRÁNSITO)
    Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> lotesPorUbicacion = {};
    for (var doc in invSnap.docs) {
      String ubi = (doc.data()['ubicacion'] ?? 'SIN UBICACIÓN').toString();
      if (ubi == kUbicacionTransito) continue;
      lotesPorUbicacion.putIfAbsent(ubi, () => []);
      lotesPorUbicacion[ubi]!.add(doc);
    }

    // Ordenar lotes por fecha de caducidad (FIFO: primero los que vencen antes)
    for (var lista in lotesPorUbicacion.values) {
      lista.sort((a, b) {
        Timestamp tA = a.data()['fechaCaducidad'] ?? Timestamp.now();
        Timestamp tB = b.data()['fechaCaducidad'] ?? Timestamp.now();
        return tA.compareTo(tB);
      });
    }

    Set<String> todasUbicaciones = {
      ...lotesPorUbicacion.keys,
      ...ubiSnap.docs.map((d) => d['nombre'].toString()),
    };
    todasUbicaciones.remove(kUbicacionTransito);
    List<String> listaUbicaciones = todasUbicaciones.toList()..sort();

    String? ubicacionSeleccionada = ubicacionInicial;
    if (ubicacionSeleccionada == null || !listaUbicaciones.contains(ubicacionSeleccionada)) {
      if (lotesPorUbicacion.containsKey('OPERACION TIENDA')) {
        ubicacionSeleccionada = 'OPERACION TIENDA';
      } else if (lotesPorUbicacion.isNotEmpty) {
        ubicacionSeleccionada = lotesPorUbicacion.keys.first;
      } else if (listaUbicaciones.isNotEmpty) {
        ubicacionSeleccionada = listaUbicaciones.first;
      }
    }

    Map<String, int> cantidadesSeleccionadas = {};
    String busquedaInterna = (skuFiltroInicial ?? '').toLowerCase();
    TextEditingController searchCtrl = TextEditingController(text: skuFiltroInicial ?? '');
    bool procesandoExtraccion = false;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF181818),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            List<QueryDocumentSnapshot<Map<String, dynamic>>> lotesActuales =
                ubicacionSeleccionada != null ? (lotesPorUbicacion[ubicacionSeleccionada] ?? []) : [];

            var lotesFiltrados = lotesActuales.where((doc) {
              if (busquedaInterna.isEmpty) return true;
              var d = doc.data();
              String desc = (d['descripcion'] ?? '').toString().toLowerCase();
              String sku = (d['sku'] ?? '').toString().toLowerCase();
              String ean = (d['ean'] ?? '').toString().toLowerCase();
              return desc.contains(busquedaInterna) || sku.contains(busquedaInterna) || ean.contains(busquedaInterna);
            }).toList();

            int totalLotesMarcados = cantidadesSeleccionadas.values.where((v) => v > 0).length;
            int totalPiezasMarcadas = cantidadesSeleccionadas.values.fold(0, (a, b) => a + b);

            return Container(
              height: MediaQuery.of(context).size.height * 0.86,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.swap_horiz_rounded, color: Colors.blueAccent, size: 26),
                          SizedBox(width: 8),
                          Text('TRASVASE MASIVO (EXTRAER)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amber)),
                        ],
                      ),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 1. Selector de Ubicación de Origen
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blueAccent),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        dropdownColor: const Color(0xFF2C2C2C),
                        value: ubicacionSeleccionada,
                        hint: const Text('Selecciona Ubicación de Origen', style: TextStyle(color: Colors.white70)),
                        items: listaUbicaciones.map((u) {
                          int count = lotesPorUbicacion[u]?.length ?? 0;
                          return DropdownMenuItem<String>(
                            value: u,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text('📍 $u', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: count > 0 ? Colors.greenAccent.withOpacity(0.2) : Colors.white10,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text('$count lotes', style: TextStyle(fontSize: 11, color: count > 0 ? Colors.greenAccent : Colors.white38, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setModalState(() {
                            ubicacionSeleccionada = val;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 2. Buscador interno y botón de "Seleccionar Todo el Mueble"
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: TextField(
                            controller: searchCtrl,
                            decoration: InputDecoration(
                              hintText: 'Filtrar SKU o descripción...',
                              hintStyle: const TextStyle(fontSize: 12),
                              prefixIcon: const Icon(Icons.search, size: 18, color: Colors.amber),
                              suffixIcon: busquedaInterna.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 16),
                                      onPressed: () {
                                        searchCtrl.clear();
                                        setModalState(() => busquedaInterna = '');
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: Colors.white10,
                              contentPadding: EdgeInsets.zero,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            ),
                            onChanged: (v) => setModalState(() => busquedaInterna = v.toLowerCase()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.withOpacity(0.2),
                          foregroundColor: Colors.amber,
                          side: const BorderSide(color: Colors.amber),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        icon: const Icon(Icons.done_all, size: 16),
                        label: const Text('TODO EL MUEBLE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        onPressed: lotesFiltrados.isEmpty
                            ? null
                            : () {
                                setModalState(() {
                                  bool todosSeleccionados = lotesFiltrados.every((doc) => (cantidadesSeleccionadas[doc.id] ?? 0) == (doc.data()['cantidad'] ?? 0));
                                  for (var doc in lotesFiltrados) {
                                    int maxPzas = doc.data()['cantidad'] ?? 0;
                                    cantidadesSeleccionadas[doc.id] = todosSeleccionados ? 0 : maxPzas;
                                  }
                                });
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 3. Lista de lotes anclados a esa ubicación
                  Expanded(
                    child: lotesFiltrados.isEmpty
                        ? const Center(
                            child: Text('No hay lotes registrados en esta ubicación.', style: TextStyle(color: Colors.white54, fontSize: 14)),
                          )
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
                              int cantActual = cantidadesSeleccionadas[docId] ?? 0;
                              bool seleccionado = cantActual > 0;

                              return Card(
                                color: seleccionado ? Colors.blueAccent.withOpacity(0.18) : Colors.white10,
                                margin: const EdgeInsets.symmetric(vertical: 5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: seleccionado ? Colors.blueAccent : Colors.white12, width: seleccionado ? 2 : 1),
                                ),
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
                                            onChanged: (val) {
                                              setModalState(() {
                                                cantidadesSeleccionadas[docId] = (val == true) ? maximoPermitido : 0;
                                              });
                                            },
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
                                      const SizedBox(height: 6),
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
                                                onTap: () => setModalState(() => cantidadesSeleccionadas[docId] = maximoPermitido),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                                  decoration: BoxDecoration(
                                                    color: cantActual == maximoPermitido ? Colors.amber : Colors.amber.withOpacity(0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: Colors.amber),
                                                  ),
                                                  child: Text('TODO', style: TextStyle(color: cantActual == maximoPermitido ? Colors.black : Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              IconButton(
                                                icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 26),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                onPressed: cantActual > 0 ? () => setModalState(() => cantidadesSeleccionadas[docId] = cantActual - 1) : null,
                                              ),
                                              const SizedBox(width: 6),
                                              InkWell(
                                                onTap: () async {
                                                  int? nuevaCant = await _pedirCantidadManual(context, cantActual, maximoPermitido, d['descripcion'] ?? d['sku']);
                                                  if (nuevaCant != null) {
                                                    setModalState(() => cantidadesSeleccionadas[docId] = nuevaCant);
                                                  }
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white24)),
                                                  child: Text(cantActual.toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              IconButton(
                                                icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent, size: 26),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                onPressed: cantActual < maximoPermitido ? () => setModalState(() => cantidadesSeleccionadas[docId] = cantActual + 1) : null,
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: procesandoExtraccion
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.shopping_cart_checkout, size: 24),
                      label: Text(
                        procesandoExtraccion
                            ? 'MOVIENDO AL CARRITO...'
                            : 'ENVIAR AL CARRITO TEMPORAL ($totalLotesMarcados lotes • $totalPiezasMarcadas pzas)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: (totalLotesMarcados == 0 || procesandoExtraccion)
                          ? null
                          : () async {
                              setModalState(() => procesandoExtraccion = true);
                              await _ejecutarExtraccionACarritoTransito(invSnap.docs, cantidadesSeleccionadas);
                              if (mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('🛒 $totalLotesMarcados lotes ($totalPiezasMarcadas pzas) cargados en CARRITO EN TRÁNSITO'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _ejecutarExtraccionACarritoTransito(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> todosDocs,
    Map<String, int> cantidadesSeleccionadas,
  ) async {
    var mapaDocs = {for (var d in todosDocs) d.id: d};

    for (var entry in cantidadesSeleccionadas.entries) {
      int cantMover = entry.value;
      if (cantMover <= 0) continue;

      var docOrigen = mapaDocs[entry.key];
      if (docOrigen == null) continue;

      var data = docOrigen.data();
      int cantActual = data['cantidad'] ?? 0;
      if (cantMover > cantActual) cantMover = cantActual;

      String skuOficial = await _obtenerSkuOficial((data['sku'] ?? '').toString());
      DateTime fCad = (data['fechaCaducidad'] as Timestamp).toDate();
      String ubiOrigen = (data['ubicacion'] ?? 'SIN UBICACIÓN').toString();

      // 1. Descontar del mueble de origen
      if (cantActual <= cantMover) {
        await docOrigen.reference.delete();
      } else {
        await docOrigen.reference.update({'cantidad': cantActual - cantMover});
      }

      // 2. Buscar si ya existe el mismo SKU + Fecha + Origen en el CARRITO EN TRÁNSITO para unificar
      var qTransito = await _refInv
          .where('ubicacion', isEqualTo: kUbicacionTransito)
          .where('sku', isEqualTo: skuOficial)
          .get();

      QueryDocumentSnapshot<Map<String, dynamic>>? loteEnTransito;
      for (var d in qTransito.docs) {
        DateTime fDoc = (d.data()['fechaCaducidad'] as Timestamp).toDate();
        String origDoc = (d.data()['ubicacionOrigen'] ?? '').toString();
        if (fDoc.year == fCad.year && fDoc.month == fCad.month && fDoc.day == fCad.day && origDoc == ubiOrigen) {
          loteEnTransito = d;
          break;
        }
      }

      if (loteEnTransito != null) {
        int cantEnCarrito = loteEnTransito.data()['cantidad'] ?? 0;
        await loteEnTransito.reference.update({
          'cantidad': cantEnCarrito + cantMover,
          'fechaTransito': FieldValue.serverTimestamp(),
          'usuarioTransito': widget.usuarioRegistra,
        });
      } else {
        var nuevoLote = Map<String, dynamic>.from(data);
        nuevoLote['sku'] = skuOficial;
        nuevoLote['cantidad'] = cantMover;
        nuevoLote['ubicacion'] = kUbicacionTransito;
        nuevoLote['ubicacionOrigen'] = ubiOrigen;
        nuevoLote['fechaTransito'] = FieldValue.serverTimestamp();
        nuevoLote['usuarioTransito'] = widget.usuarioRegistra;
        await _refInv.add(nuevoLote);
      }
    }
  }

  // =========================================================================
  // 2. VENTANA DE UBICACIÓN TEMPORAL FANTASMA (CARRITO EN TRÁNSITO -> REPARTIR)
  // =========================================================================
  void _abrirCarritoEnTransito({String? destinoPreseleccionado}) async {
    var transitoSnap = await _refInv.where('ubicacion', isEqualTo: kUbicacionTransito).get();
    var ubiSnap = await _refUbi.orderBy('nombre').get();

    List<String> listaMuebles = ubiSnap.docs
        .map((d) => d['nombre'].toString())
        .where((n) => n != kUbicacionTransito)
        .toList();

    String? muebleDestino = destinoPreseleccionado ?? _ubicacionDestino;
    if (muebleDestino != null && !listaMuebles.contains(muebleDestino)) {
      listaMuebles.add(muebleDestino);
    }

    var docsTransito = transitoSnap.docs.toList();
    docsTransito.sort((a, b) {
      Timestamp tA = a.data()['fechaCaducidad'] ?? Timestamp.now();
      Timestamp tB = b.data()['fechaCaducidad'] ?? Timestamp.now();
      return tA.compareTo(tB);
    });

    // Por defecto marcamos todos los lotes con su cantidad completa para dejar rápido
    Map<String, int> cantidadesADejar = {
      for (var d in docsTransito) d.id: (d.data()['cantidad'] ?? 0) as int
    };

    bool procesandoEntrega = false;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF181818),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            int lotesElegidos = cantidadesADejar.values.where((v) => v > 0).length;
            int piezasElegidas = cantidadesADejar.values.fold(0, (a, b) => a + b);

            return Container(
              height: MediaQuery.of(context).size.height * 0.86,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.shopping_cart_checkout, color: Colors.deepOrangeAccent, size: 26),
                          SizedBox(width: 8),
                          Text('CARRITO EN TRÁNSITO (TEMPORAL)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.amber)),
                        ],
                      ),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const Text('Selecciona qué artículos y cuántas piezas vas a dejar en el mueble destino:', style: TextStyle(color: Colors.white60, fontSize: 11)),
                  const SizedBox(height: 10),

                  // 1. Selector de Mueble Destino donde se va a acomodar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: muebleDestino != null ? Colors.green.withOpacity(0.15) : Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: muebleDestino != null ? Colors.greenAccent : Colors.deepOrangeAccent, width: 1.5),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        dropdownColor: const Color(0xFF2C2C2C),
                        value: muebleDestino,
                        hint: const Text('🎯 1. Selecciona el MUEBLE DESTINO aquí...', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                        items: listaMuebles
                            .map((u) => DropdownMenuItem<String>(
                                  value: u,
                                  child: Text('🎯 Destino: $u', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                                ))
                            .toList(),
                        onChanged: (val) {
                          setModalState(() => muebleDestino = val);
                          setState(() => _ubicacionDestino = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Botones rápidos de Marcar Todos / Desmarcar Todos
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.check_box_outline_blank, size: 16, color: Colors.white54),
                        label: const Text('Desmarcar todo', style: TextStyle(fontSize: 11, color: Colors.white54)),
                        onPressed: () {
                          setModalState(() {
                            for (var d in docsTransito) {
                              cantidadesADejar[d.id] = 0;
                            }
                          });
                        },
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.select_all, size: 16, color: Colors.amber),
                        label: const Text('Seleccionar todo', style: TextStyle(fontSize: 11, color: Colors.amber)),
                        onPressed: () {
                          setModalState(() {
                            for (var d in docsTransito) {
                              cantidadesADejar[d.id] = (d.data()['cantidad'] ?? 0) as int;
                            }
                          });
                        },
                      ),
                    ],
                  ),

                  Expanded(
                    child: docsTransito.isEmpty
                        ? const Center(
                            child: Text('¡El carrito temporal está limpio!\nNo hay mercancía pendiente en tránsito.', textAlign: TextAlign.center, style: TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                          )
                        : ListView.builder(
                            itemCount: docsTransito.length,
                            itemBuilder: (context, i) {
                              var doc = docsTransito[i];
                              var d = doc.data();
                              String docId = doc.id;
                              DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
                              String fechaFormateada = "${cad.day.toString().padLeft(2, '0')}/${cad.month.toString().padLeft(2, '0')}/${cad.year}";
                              String origen = (d['ubicacionOrigen'] ?? 'ND').toString();

                              int maxEnCarrito = d['cantidad'] ?? 0;
                              int cantElegida = cantidadesADejar[docId] ?? 0;
                              bool activo = cantElegida > 0;

                              return Card(
                                color: activo ? Colors.green.withOpacity(0.15) : Colors.white10,
                                margin: const EdgeInsets.symmetric(vertical: 5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: activo ? Colors.greenAccent : Colors.white12, width: activo ? 2 : 1),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(10.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Checkbox(
                                            value: activo,
                                            activeColor: Colors.greenAccent,
                                            checkColor: Colors.black,
                                            onChanged: (v) {
                                              setModalState(() {
                                                cantidadesADejar[docId] = (v == true) ? maxEnCarrito : 0;
                                              });
                                            },
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
                                          // Botón para devolver este lote a su mueble de origen si no cupo
                                          IconButton(
                                            icon: const Icon(Icons.settings_backup_restore, color: Colors.orangeAccent),
                                            tooltip: 'Devolver a $origen',
                                            onPressed: () async {
                                              await _repartirDesdeCarritoTransito([doc], {docId: maxEnCarrito}, origen);
                                              setModalState(() {
                                                docsTransito.removeAt(i);
                                                cantidadesADejar.remove(docId);
                                              });
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Devuelto a $origen'), backgroundColor: Colors.orange));
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
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
                                                onTap: () => setModalState(() => cantidadesADejar[docId] = maxEnCarrito),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                                  decoration: BoxDecoration(
                                                    color: cantElegida == maxEnCarrito ? Colors.amber : Colors.amber.withOpacity(0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: Colors.amber),
                                                  ),
                                                  child: Text('TODO', style: TextStyle(color: cantElegida == maxEnCarrito ? Colors.black : Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              IconButton(
                                                icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 26),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                onPressed: cantElegida > 0 ? () => setModalState(() => cantidadesADejar[docId] = cantElegida - 1) : null,
                                              ),
                                              const SizedBox(width: 6),
                                              InkWell(
                                                onTap: () async {
                                                  int? nuevaCant = await _pedirCantidadManual(context, cantElegida, maxEnCarrito, d['descripcion'] ?? d['sku']);
                                                  if (nuevaCant != null) {
                                                    setModalState(() => cantidadesADejar[docId] = nuevaCant);
                                                  }
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white24)),
                                                  child: Text(cantElegida.toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              IconButton(
                                                icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent, size: 26),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                onPressed: cantElegida < maxEnCarrito ? () => setModalState(() => cantidadesADejar[docId] = cantElegida + 1) : null,
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: procesandoEntrega
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                          : const Icon(Icons.archive, size: 24),
                      label: Text(
                        procesandoEntrega
                            ? 'ACOMODANDO EN MUEBLE...'
                            : (muebleDestino == null
                                ? 'SELECCIONA UN MUEBLE DESTINO ARRIBA'
                                : 'DEJAR EN $muebleDestino ($lotesElegidos lotes • $piezasElegidas pzas)'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      onPressed: (muebleDestino == null || lotesElegidos == 0 || procesandoEntrega)
                          ? null
                          : () async {
                              setModalState(() => procesandoEntrega = true);
                              await _repartirDesdeCarritoTransito(docsTransito, cantidadesADejar, muebleDestino!);
                              if (mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('✅ $piezasElegidas piezas acomodadas exitosamente en $muebleDestino'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _repartirDesdeCarritoTransito(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docsTransito,
    Map<String, int> cantidadesADejar,
    String muebleDestino,
  ) async {
    var mapaDocs = {for (var d in docsTransito) d.id: d};

    for (var entry in cantidadesADejar.entries) {
      int cantDejar = entry.value;
      if (cantDejar <= 0) continue;

      var docCarrito = mapaDocs[entry.key];
      if (docCarrito == null) continue;

      var data = docCarrito.data();
      int cantActualEnCarrito = data['cantidad'] ?? 0;
      if (cantDejar > cantActualEnCarrito) cantDejar = cantActualEnCarrito;

      String skuOficial = await _obtenerSkuOficial((data['sku'] ?? '').toString());
      DateTime fCad = (data['fechaCaducidad'] as Timestamp).toDate();

      // 1. Restar o eliminar del Carrito en Tránsito
      if (cantActualEnCarrito <= cantDejar) {
        await docCarrito.reference.delete();
      } else {
        await docCarrito.reference.update({'cantidad': cantActualEnCarrito - cantDejar});
      }

      // 2. Sumar o crear en el Mueble Destino
      var qDestino = await _refInv
          .where('ubicacion', isEqualTo: muebleDestino)
          .where('sku', isEqualTo: skuOficial)
          .get();

      QueryDocumentSnapshot<Map<String, dynamic>>? loteEnDestino;
      for (var d in qDestino.docs) {
        DateTime fDoc = (d.data()['fechaCaducidad'] as Timestamp).toDate();
        if (fDoc.year == fCad.year && fDoc.month == fCad.month && fDoc.day == fCad.day) {
          loteEnDestino = d;
          break;
        }
      }

      if (loteEnDestino != null) {
        int cantDestino = loteEnDestino.data()['cantidad'] ?? 0;
        await loteEnDestino.reference.update({'cantidad': cantDestino + cantDejar});
      } else {
        var nuevoData = Map<String, dynamic>.from(data);
        nuevoData['sku'] = skuOficial;
        nuevoData['cantidad'] = cantDejar;
        nuevoData['ubicacion'] = muebleDestino;
        nuevoData['fechaCaptura'] = FieldValue.serverTimestamp();
        nuevoData.remove('ubicacionOrigen');
        nuevoData.remove('fechaTransito');
        nuevoData.remove('usuarioTransito');
        nuevoData.remove('misionTransitoGenerada');
        await _refInv.add(nuevoData);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.logout, color: Colors.redAccent),
          onPressed: () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const PantallaLogin()));
          },
        ),
        title: const Text('Operaciones de Piso', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 16)),
        actions: [
          const Center(child: Text("TRASVASE ", style: TextStyle(fontSize: 10))),
          Switch(value: _modoTrasvase, onChanged: (v) => setState(() => _modoTrasvase = v), activeColor: Colors.blueAccent),
        ],
      ),
      body: Column(
        children: [
          // 1. BOTÓN INGRESO DE MERCANCÍA (MANIFIESTO)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pinkAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.inventory_2, size: 20),
                label: const Text('INGRESO DE MERCANCÍA (MANIFIESTO)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.8)),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PantallaIngreso(usuario: widget.usuarioRegistra, idTiendaGlobal: widget.idTiendaGlobal),
                  ),
                ),
              ),
            ),
          ),

          // 2. NUEVOS BOTONES: TRASVASE MASIVO + UBICACIÓN TEMPORAL (CARRITO EN TRÁNSITO)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                      label: const Text('TRASVASE MASIVO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      onPressed: () => _abrirTrasvaseMasivo(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _refInv.where('ubicacion', isEqualTo: kUbicacionTransito).snapshots(),
                    builder: (context, snap) {
                      int lotesEnCarrito = snap.hasData ? snap.data!.docs.length : 0;
                      int pzasEnCarrito = 0;
                      if (snap.hasData) {
                        for (var doc in snap.data!.docs) {
                          pzasEnCarrito += ((doc.data() as Map<String, dynamic>)['cantidad'] ?? 0) as int;
                        }
                      }
                      bool tieneCarga = lotesEnCarrito > 0;

                      return SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: tieneCarga ? Colors.deepOrangeAccent : Colors.white12,
                            foregroundColor: tieneCarga ? Colors.white : Colors.white70,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            side: BorderSide(color: tieneCarga ? Colors.amberAccent : Colors.white24, width: tieneCarga ? 1.5 : 1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: Icon(tieneCarga ? Icons.shopping_cart_checkout : Icons.shopping_cart_outlined, size: 18),
                          label: Text(
                            tieneCarga ? 'EN TRÁNSITO ($lotesEnCarrito • ${pzasEnCarrito}pz)' : 'CARRITO TEMPORAL (0)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () => _abrirCarritoEnTransito(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // 3. SELECTOR DE UBICACIÓN DESTINO / ANCLAJE
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: Row(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _refUbi.orderBy('nombre').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const LinearProgressIndicator(color: Colors.amber);
                      List<String> listaMuebles = snapshot.data!.docs
                          .map((d) => d['nombre'] as String)
                          .where((n) => n != kUbicacionTransito)
                          .toList();
                      if (_ubicacionDestino != null && !listaMuebles.contains(_ubicacionDestino)) {
                        listaMuebles.add(_ubicacionDestino!);
                      }
                      return Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: (_ubicacionDestino != null && _ubicacionDestino != "Sin anclar") ? Colors.green.withOpacity(0.1) : Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: (_ubicacionDestino != null && _ubicacionDestino != "Sin anclar") ? Colors.greenAccent : Colors.white24),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.location_on, size: 20, color: (_ubicacionDestino != null && _ubicacionDestino != "Sin anclar") ? Colors.greenAccent : Colors.white54),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  dropdownColor: const Color(0xFF2C2C2C),
                                  hint: Text(
                                    _modoTrasvase ? 'Selecciona Mueble Destino' : 'Selecciona Mueble para Anclar',
                                    style: TextStyle(color: _modoTrasvase ? Colors.blueAccent : Colors.white54, fontSize: 12),
                                  ),
                                  value: _ubicacionDestino,
                                  items: [
                                    const DropdownMenuItem<String>(value: null, child: Text('Sin anclar', style: TextStyle(color: Colors.white54, fontSize: 12))),
                                    ...listaMuebles.map((u) => DropdownMenuItem<String>(value: u, child: Text(u, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))))
                                  ],
                                  onChanged: (val) => setState(() => _ubicacionDestino = val),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (_ubicacionDestino != null && _ubicacionDestino != "Sin anclar")
                  IconButton(
                    icon: const Icon(Icons.outbox, color: Colors.blueAccent),
                    tooltip: "Extraer mercancía de $_ubicacionDestino",
                    onPressed: () => _abrirTrasvaseMasivo(ubicacionInicial: _ubicacionDestino),
                  ),
              ],
            ),
          ),

          // 4. ESCÁNER DE CÁMARA COMPACTO
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _modoTrasvase ? Colors.blueAccent : Colors.amber, width: 2.5),
              ),
              clipBehavior: Clip.hardEdge,
              child: widget.estaActiva
                  ? Stack(
                      children: [
                        MobileScanner(
                          onDetect: (capture) {
                            if (_bloquearEscaneo) return;
                            final barcode = capture.barcodes.first;
                            if (barcode.rawValue != null) {
                              setState(() => _bloquearEscaneo = true);
                              _procesarEscaneo(barcode.rawValue!);
                            }
                          },
                        ),
                        Center(
                          child: SizedBox(
                            width: 200,
                            height: 200,
                            child: Stack(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.white30, width: 2),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                AnimatedBuilder(
                                  animation: _laserAnimation,
                                  builder: (context, child) => Positioned(
                                    top: _laserAnimation.value,
                                    left: 10,
                                    right: 10,
                                    child: Container(
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent,
                                        boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.8), blurRadius: 10, spreadRadius: 2)],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.videocam_off, size: 50, color: Colors.white24),
                          SizedBox(height: 8),
                          Text('Cámara en reposo\n(Ahorro de batería)', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
            ),
          ),

          // 5. ENTRADA MANUAL DE SKU / UPC
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              height: 48,
              child: TextField(
                controller: _skuController,
                decoration: InputDecoration(
                  hintText: _modoTrasvase ? 'Busca SKU o UPC para extraer...' : 'SKU / UPC Manual...',
                  filled: true,
                  fillColor: Colors.white10,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search, color: Colors.amber),
                    onPressed: () {
                      if (_skuController.text.isNotEmpty) {
                        setState(() => _bloquearEscaneo = true);
                        _procesarEscaneo(_skuController.text);
                      }
                    },
                  ),
                ),
                onSubmitted: (val) {
                  if (val.isNotEmpty) {
                    setState(() => _bloquearEscaneo = true);
                    _procesarEscaneo(val);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PantallaRegistro extends StatefulWidget {
  final String skuEscaneado;
  final String? ubicacionPredefinida;
  final String usuarioRegistra;
  final String idTiendaGlobal;
  const PantallaRegistro({
    super.key,
    required this.skuEscaneado,
    this.ubicacionPredefinida,
    required this.usuarioRegistra,
    required this.idTiendaGlobal,
  });
  @override
  State<PantallaRegistro> createState() => _PantallaRegistroState();
}

class _PantallaRegistroState extends State<PantallaRegistro> {
  DateTime? _fechaSeleccionada;
  String? _ubicacionSeleccionada;
  bool _guardando = false;
  final TextEditingController _cantidadController = TextEditingController(text: "1");
  String _descripcion = "Buscando...";
  late String _skuOficial;
  Map<String, dynamic>? _datosMaestros;

  @override
  void initState() {
    super.initState();
    _skuOficial = widget.skuEscaneado.trim();
    if (widget.ubicacionPredefinida != null && widget.ubicacionPredefinida != "Sin anclar") {
      _ubicacionSeleccionada = widget.ubicacionPredefinida;
    }
    _buscarDatosOriginales();
  }

  Future<void> _buscarDatosOriginales() async {
    try {
      String codigo = widget.skuEscaneado.trim();
      var doc = await FirebaseFirestore.instance.collection('maestro_productos').doc(codigo).get();
      if (!doc.exists) {
        var qEan = await FirebaseFirestore.instance.collection('maestro_productos').where('ean', isEqualTo: codigo).limit(1).get();
        if (qEan.docs.isNotEmpty) {
          _datosMaestros = qEan.docs.first.data();
        }
      } else {
        _datosMaestros = doc.data();
      }

      if (mounted) {
        setState(() {
          if (_datosMaestros != null) {
            if (_datosMaestros!['sku'] != null && _datosMaestros!['sku'].toString().trim().isNotEmpty) {
              _skuOficial = _datosMaestros!['sku'].toString().trim();
            }
            _descripcion = _datosMaestros?['descripcion'] ?? "Sin Nombre";
          } else {
            _descripcion = "Artículo Nuevo";
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _descripcion = "Error");
    }
  }

  Future<void> _guardarEnNube() async {
    if (_ubicacionSeleccionada == null || _fechaSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Revisa Fecha y Mueble'), backgroundColor: Colors.redAccent));
      return;
    }
    setState(() => _guardando = true);
    try {
      int cantNueva = int.tryParse(_cantidadController.text) ?? 1;
      var refInv = FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('inventario_activo');

      var existentes = await refInv.where('sku', isEqualTo: _skuOficial).where('ubicacion', isEqualTo: _ubicacionSeleccionada).get();

      QueryDocumentSnapshot? loteIgual;
      for (var d in existentes.docs) {
        DateTime fDoc = (d['fechaCaducidad'] as Timestamp).toDate();
        if (fDoc.year == _fechaSeleccionada!.year && fDoc.month == _fechaSeleccionada!.month && fDoc.day == _fechaSeleccionada!.day) {
          loteIgual = d;
          break;
        }
      }

      if (loteIgual != null) {
        int cantActual = loteIgual['cantidad'] ?? 0;
        await loteIgual.reference.update({'cantidad': cantActual + cantNueva});
      } else {
        var map = <String, dynamic>{
          'sku': _skuOficial,
          'descripcion': _descripcion,
          'ubicacion': _ubicacionSeleccionada,
          'cantidad': cantNueva,
          'fechaCaducidad': Timestamp.fromDate(_fechaSeleccionada!),
          'fechaCaptura': FieldValue.serverTimestamp(),
          'capturista': widget.usuarioRegistra,
        };
        if (_datosMaestros != null) {
          map.addAll(_datosMaestros!);
          map['sku'] = _skuOficial;
        }
        await refInv.add(map);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _guardando = false);
    }
  }

  void _mostrarSelectorFechaFluido() {
    DateTime tempDate = _fechaSeleccionada ?? DateTime.now();
    DateTime hoy = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          height: 350,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text('Fecha de Caducidad', style: TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Expanded(
                child: CalendarDatePicker(
                  initialDate: tempDate,
                  firstDate: DateTime(hoy.year, hoy.month, hoy.day),
                  lastDate: DateTime(hoy.year + 10, hoy.month, hoy.day),
                  onDateChanged: (DateTime newDate) => tempDate = newDate,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                    onPressed: () {
                      setState(() => _fechaSeleccionada = tempDate);
                      Navigator.pop(context);
                    },
                    child: const Text('Confirmar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar Entrada')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text(_descripcion, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.amber), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('SKU Oficial: $_skuOficial', style: const TextStyle(fontSize: 14, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 25),
            TextField(controller: _cantidadController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad de Piezas', filled: true)),
            const SizedBox(height: 20),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('ubicaciones').orderBy('nombre').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                List<String> listaMuebles = snapshot.data!.docs.map((d) => d['nombre'] as String).where((n) => n != 'EN TRÁNSITO').toList();
                if (_ubicacionSeleccionada != null && !listaMuebles.contains(_ubicacionSeleccionada)) listaMuebles.add(_ubicacionSeleccionada!);
                return Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(5), border: const Border(bottom: BorderSide(color: Colors.white54))),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.white54),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            dropdownColor: const Color(0xFF2C2C2C),
                            hint: const Text('Selecciona Mueble', style: TextStyle(color: Colors.white54)),
                            value: _ubicacionSeleccionada,
                            items: listaMuebles.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                            onChanged: (val) => setState(() => _ubicacionSeleccionada = val),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.calendar_month),
              label: Text(
                _fechaSeleccionada == null
                    ? 'Seleccionar Fecha'
                    : "${_fechaSeleccionada!.day.toString().padLeft(2, '0')} / ${_fechaSeleccionada!.month.toString().padLeft(2, '0')} / ${_fechaSeleccionada!.year}",
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.white10, foregroundColor: Colors.white),
              onPressed: _mostrarSelectorFechaFluido,
            ),
            const SizedBox(height: 50),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: (_fechaSeleccionada == null || _guardando) ? null : _guardarEnNube,
                child: _guardando ? const CircularProgressIndicator() : const Text('CONFIRMAR Y GUARDAR'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
