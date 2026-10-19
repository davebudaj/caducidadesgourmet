import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:universal_html/html.dart' as html;

import 'ingreso.dart';
import 'login.dart';
import 'trasvase_pantallas.dart';
import '../modelos/selector_jerarquico_ubicacion.dart';

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
  bool _camaraActiva = true;
  final FocusNode _skuManualFocus = FocusNode();

  late AnimationController _laserController;
  late Animation<double> _laserAnimation;
  bool _bloquearEscaneo = false;
  bool _enSubPantalla = false;

  static const String kUbicacionTransito = 'EN TRÁNSITO';

  CollectionReference<Map<String, dynamic>> get _refInv =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('inventario_activo');

  CollectionReference<Map<String, dynamic>> get _refUbi =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('ubicaciones');

  @override
  void initState() {
    super.initState();
    try {
      String? camPref = html.window.localStorage['gg_camara_activa'];
      if (camPref != null) _camaraActiva = camPref == 'true';
    } catch (_) {}
    _laserController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    if (_camaraActiva) _laserController.repeat(reverse: true);
    _laserAnimation = Tween<double>(begin: 10.0, end: 180.0).animate(_laserController);
  }

  @override
  void dispose() {
    _laserController.dispose();
    _skuController.dispose();
    _skuManualFocus.dispose();
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

  Future<void> _irATrasvaseMasivo({String? ubicacionInicial, String? skuFiltroInicial}) async {
    setState(() => _enSubPantalla = true);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PantallaTrasvaseMasivo(
          idTiendaGlobal: widget.idTiendaGlobal,
          usuarioRegistra: widget.usuarioRegistra,
          ubicacionInicial: ubicacionInicial,
          skuFiltroInicial: skuFiltroInicial,
        ),
      ),
    );
    if (mounted) setState(() => _enSubPantalla = false);
  }

  Future<void> _irACarritoTemporal({String? destinoPreseleccionado}) async {
    setState(() => _enSubPantalla = true);
    String? nuevoDestino = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => PantallaCarritoTemporal(
          idTiendaGlobal: widget.idTiendaGlobal,
          usuarioRegistra: widget.usuarioRegistra,
          destinoPreseleccionado: destinoPreseleccionado ?? _ubicacionDestino,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _enSubPantalla = false;
        if (nuevoDestino != null) _ubicacionDestino = nuevoDestino;
      });
    }
  }

  void _procesarEscaneo(String codigo) async {
    String codigoLimpio = codigo.trim();

    if (codigoLimpio.startsWith('LOC:')) {
      String muebleEscaneado = codigoLimpio.substring(4);
      var ubiSnap = await _refUbi.orderBy('nombre').get();
      List<String> todasUbis = ubiSnap.docs.map((d) => d['nombre'].toString()).toList();
      // Buscar si este QR tiene sub-niveles hijos (hojas finales)
      List<String> subRamas = todasUbis.where((u) => u.startsWith('$muebleEscaneado > ')).toList();
      List<String> hojas = subRamas.where((u) => !todasUbis.any((otra) => otra.startsWith('$u > '))).toList();

      if (hojas.isNotEmpty) {
        String? subElegida = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.amber, width: 2)),
            title: Text('📍 ${muebleEscaneado.replaceAll(' > ', ' ➔ ')}', style: const TextStyle(color: Colors.amber, fontSize: 15, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Selecciona el nivel / entrepaño exacto donde estás trabajando:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: hojas.length,
                      itemBuilder: (c, idx) {
                        String h = hojas[idx];
                        String etiquetaHija = h.substring(muebleEscaneado.length + 3).replaceAll(' > ', ' ➔ ');
                        return Card(
                          color: Colors.white10,
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.subdirectory_arrow_right, color: Colors.greenAccent, size: 18),
                            title: Text(etiquetaHija, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 13, color: Colors.amber),
                            onTap: () => Navigator.pop(ctx, h),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                icon: const Icon(Icons.outbox, size: 16),
                label: const Text('EXTRAER DE TODO EL MUEBLE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: () => Navigator.pop(ctx, '__EXTRAER_PADRE__'),
              ),
            ],
          ),
        );

        if (subElegida == null) {
          if (mounted) setState(() => _bloquearEscaneo = false);
          return;
        } else if (subElegida == '__EXTRAER_PADRE__') {
          await _irATrasvaseMasivo(ubicacionInicial: muebleEscaneado);
          if (mounted) setState(() => _bloquearEscaneo = false);
          return;
        } else {
          muebleEscaneado = subElegida;
        }
      }

      await showDialog(
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
                _irACarritoTemporal(destinoPreseleccionado: muebleEscaneado);
              },
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
              icon: const Icon(Icons.outbox, size: 18),
              label: const Text('EXTRAER LOTES'),
              onPressed: () {
                Navigator.pop(context);
                _irATrasvaseMasivo(ubicacionInicial: muebleEscaneado);
              },
            ),
          ],
        ),
      );
    } else if (codigoLimpio.isNotEmpty) {
      if (_modoTrasvase) {
        String skuOficial = await _obtenerSkuOficial(codigoLimpio);
        await _irATrasvaseMasivo(skuFiltroInicial: skuOficial);
      } else {
        setState(() => _enSubPantalla = true);
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
        if (mounted) setState(() => _enSubPantalla = false);
      }
      _skuController.clear();
    }

    if (mounted) setState(() => _bloquearEscaneo = false);
  }

  @override
  Widget build(BuildContext context) {
    bool mostrarCamara = widget.estaActiva && !_enSubPantalla && _camaraActiva;

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 118,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              padding: const EdgeInsets.only(left: 6),
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
              tooltip: 'Cerrar sesión',
              onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const PantallaLogin())),
            ),
            const SizedBox(width: 4),
            const Text("CÁM", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white70)),
            Transform.scale(
              scale: 0.78,
              child: Switch(
                value: _camaraActiva,
                activeColor: Colors.greenAccent,
                onChanged: (v) {
                  setState(() => _camaraActiva = v);
                  try {
                    html.window.localStorage['gg_camara_activa'] = v.toString();
                  } catch (_) {}
                  if (v) {
                    _laserController.repeat(reverse: true);
                  } else {
                    _laserController.stop();
                    _skuManualFocus.requestFocus();
                  }
                },
              ),
            ),
          ],
        ),
        titleSpacing: 0,
        centerTitle: true,
        title: const Text('Operaciones de Piso', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 14)),
        actions: [
          const Center(child: Text("TRASVASE", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white70))),
          Transform.scale(
            scale: 0.78,
            child: Switch(value: _modoTrasvase, onChanged: (v) => setState(() => _modoTrasvase = v), activeColor: Colors.blueAccent),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                icon: const Icon(Icons.inventory_2, size: 20),
                label: const Text('INGRESO DE MERCANCÍA (MANIFIESTO)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.8)),
                onPressed: () async {
                  setState(() => _enSubPantalla = true);
                  await Navigator.push(context, MaterialPageRoute(builder: (context) => PantallaIngreso(usuario: widget.usuarioRegistra, idTiendaGlobal: widget.idTiendaGlobal)));
                  if (mounted) setState(() => _enSubPantalla = false);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                      label: const Text('TRASVASE MASIVO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      onPressed: () => _irATrasvaseMasivo(),
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
                          onPressed: () => _irACarritoTemporal(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: Row(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _refUbi.orderBy('nombre').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const LinearProgressIndicator(color: Colors.amber);
                      List<String> listaMuebles = snapshot.data!.docs.map((d) => d['nombre'] as String).where((n) => n != kUbicacionTransito).toList();
                      if (_ubicacionDestino != null && !listaMuebles.contains(_ubicacionDestino)) listaMuebles.add(_ubicacionDestino!);
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
                                  hint: Text(_modoTrasvase ? 'Selecciona Mueble Destino' : 'Selecciona Mueble para Anclar', style: TextStyle(color: _modoTrasvase ? Colors.blueAccent : Colors.white54, fontSize: 12)),
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
                    onPressed: () => _irATrasvaseMasivo(ubicacionInicial: _ubicacionDestino),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: _modoTrasvase ? Colors.blueAccent : Colors.amber, width: 2.5)),
              clipBehavior: Clip.hardEdge,
              child: mostrarCamara
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
                                Container(decoration: BoxDecoration(border: Border.all(color: Colors.white30, width: 2), borderRadius: BorderRadius.circular(16))),
                                AnimatedBuilder(
                                  animation: _laserAnimation,
                                  builder: (context, child) => Positioned(
                                    top: _laserAnimation.value,
                                    left: 10,
                                    right: 10,
                                    child: Container(height: 3, decoration: BoxDecoration(color: Colors.redAccent, boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.8), blurRadius: 10, spreadRadius: 2)])),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.videocam_off, size: 50, color: Colors.white24),
                          const SizedBox(height: 8),
                          Text(
                          _camaraActiva
                              ? 'Cámara en pausa\n(Modo alto rendimiento)'
                              : 'Cámara desactivada (Ahorro de RAM y Batería)\nListo para usar con escáner físico abajo',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        ],
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              height: 48,
              child: TextField(
                controller: _skuController,
                focusNode: _skuManualFocus,
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
  const PantallaRegistro({super.key, required this.skuEscaneado, this.ubicacionPredefinida, required this.usuarioRegistra, required this.idTiendaGlobal});
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
    if (widget.ubicacionPredefinida != null && widget.ubicacionPredefinida != "Sin anclar") _ubicacionSeleccionada = widget.ubicacionPredefinida;
    _buscarDatosOriginales();
  }

  Future<void> _buscarDatosOriginales() async {
    try {
      String codigo = widget.skuEscaneado.trim();
      var doc = await FirebaseFirestore.instance.collection('maestro_productos').doc(codigo).get();
      if (!doc.exists) {
        var qEan = await FirebaseFirestore.instance.collection('maestro_productos').where('ean', isEqualTo: codigo).limit(1).get();
        if (qEan.docs.isNotEmpty) _datosMaestros = qEan.docs.first.data();
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
                List<String> todas = snapshot.data!.docs.map((d) => d['nombre'] as String).where((n) => n != 'EN TRÁNSITO').toList();
                List<String> listaMuebles = todas.where((u) => !todas.any((otra) => otra.startsWith('$u > '))).toList();
                if (_ubicacionSeleccionada != null && !listaMuebles.contains(_ubicacionSeleccionada)) listaMuebles.add(_ubicacionSeleccionada!);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ubicación Exacta (Jerarquía):', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    SelectorJerarquicoUbicacion(
                      todasLasRutas: listaMuebles,
                      rutaSeleccionada: _ubicacionSeleccionada,
                      permitirSeleccionParcial: false,
                      textoRaizVacio: '1. Selecciona Área (Piso / Bodega / Display)...',
                      onRutaCambiada: (val) => setState(() => _ubicacionSeleccionada = val),
                    ),
                    if (_ubicacionSeleccionada != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '✅ Destino seleccionado: ${JerarquiaUbicacionHelper.formatearRutaVisual(_ubicacionSeleccionada)}',
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.calendar_month),
              label: Text(
                _fechaSeleccionada == null ? 'Seleccionar Fecha' : "${_fechaSeleccionada!.day.toString().padLeft(2, '0')} / ${_fechaSeleccionada!.month.toString().padLeft(2, '0')} / ${_fechaSeleccionada!.year}",
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
