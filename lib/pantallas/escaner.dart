import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../modelos/item_carrito.dart';
import '../modelos/etiqueta_mes.dart';

class PantallaEscaner extends StatefulWidget {
  final bool estaActiva;
  final String usuarioRegistra;

  const PantallaEscaner({
    super.key, 
    this.estaActiva = true, 
    required this.usuarioRegistra
  });

  @override
  State<PantallaEscaner> createState() => _PantallaEscanerState();
}

class _PantallaEscanerState extends State<PantallaEscaner> with SingleTickerProviderStateMixin {
  final TextEditingController _skuController = TextEditingController();
  String? _ubicacionDestino; 
  bool _modoTrasvase = false;
  List<ItemCarrito> _carrito = [];
  
  late AnimationController _laserController;
  late Animation<double> _laserAnimation;
  DateTime? _ultimoEscaneo;
  bool _bloquearEscaneo = false;

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _laserAnimation = Tween<double>(begin: 10.0, end: 230.0).animate(_laserController);
  }

  @override
  void dispose() {
    _laserController.dispose();
    _skuController.dispose();
    super.dispose();
  }

  void _procesarEscaneo(String codigo) async {
    String codigoLimpio = codigo.trim();
    
    if (codigoLimpio.startsWith('LOC:')) {
      setState(() { _ubicacionDestino = codigoLimpio.substring(4); _skuController.clear(); });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('📍 Destino fijado: $_ubicacionDestino'), backgroundColor: Colors.green));
      await Future.delayed(const Duration(seconds: 2)); 
    } else if (codigoLimpio.isNotEmpty) {
      if (_modoTrasvase) {
        if (_ubicacionDestino == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Primero selecciona o escanea el MUEBLE DESTINO arriba.'), backgroundColor: Colors.orangeAccent));
        } else {
          _seleccionarOrigenYCantidad(codigoLimpio);
        }
        await Future.delayed(const Duration(seconds: 2));
      } else {
        await Navigator.push(context, MaterialPageRoute(builder: (context) => PantallaRegistro(skuEscaneado: codigoLimpio, ubicacionPredefinida: _ubicacionDestino, usuarioRegistra: widget.usuarioRegistra)));
      }
      _skuController.clear();
    }
    
    if (mounted) setState(() => _bloquearEscaneo = false);
  }

  void _seleccionarOrigenYCantidad(String codigoBuscado) async {
    var snapshot = await FirebaseFirestore.instance.collection('inventario_activo').where('sku', isEqualTo: codigoBuscado).get();
    
    if (snapshot.docs.isEmpty) {
      snapshot = await FirebaseFirestore.instance.collection('inventario_activo').where('ean', isEqualTo: codigoBuscado).get();
    }
    
    if (snapshot.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay existencias registradas en piso.'), backgroundColor: Colors.redAccent));
      return;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Selecciona el Lote de Origen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amber)),
            const SizedBox(height: 5),
            Text('Código: $codigoBuscado', style: const TextStyle(color: Colors.white70)),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: snapshot.docs.length,
                itemBuilder: (context, i) {
                  var d = snapshot.docs[i].data();
                  DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
                  String ubicacion = d['ubicacion'] ?? 'Desconocida';
                  String fechaFormateada = "${cad.day.toString().padLeft(2,'0')}/${cad.month.toString().padLeft(2,'0')}/${cad.year}";
                  
                  return Card(
                    color: Colors.white10,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      leading: Icon(Icons.outbox, color: EtiquetaMes.obtener(cad)['color'], size: 30),
                      title: Text(d['descripcion'] ?? d['sku'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('📍 Mueble: $ubicacion', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 2),
                            Text('📅 Caducidad: $fechaFormateada', style: const TextStyle(color: Colors.amberAccent, fontSize: 13)),
                            const SizedBox(height: 2),
                            Text('📦 Existencia: ${d['cantidad']} piezas', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                      ),
                      trailing: const Icon(Icons.add_shopping_cart, color: Colors.blueAccent),
                      onTap: () {
                        Navigator.pop(context); 
                        _pedirCantidad(snapshot.docs[i].id, d, ubicacion); 
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pedirCantidad(String docId, Map<String, dynamic> data, String origen) {
    TextEditingController c = TextEditingController(text: "1");
    int maximoPermitido = data['cantidad'] ?? 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2C),
        title: Text('Moviendo de $origen', style: const TextStyle(color: Colors.amber, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Llevando a: $_ubicacionDestino', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(controller: c, keyboardType: TextInputType.number, autofocus: true, decoration: InputDecoration(labelText: 'Piezas (Máx. $maximoPermitido)', filled: true, fillColor: Colors.black45)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              int cant = int.tryParse(c.text) ?? 0;
              if (cant > 0 && cant <= maximoPermitido) {
                setState(() {
                  _carrito.add(ItemCarrito(
                    idOriginal: docId,
                    sku: data['sku'],
                    descripcion: data['descripcion'] ?? "ND",
                    cantidadEnCarrito: cant,
                    fechaCaducidad: (data['fechaCaducidad'] as Timestamp).toDate(),
                    ubicacionOrigen: origen,
                    datosOriginales: data,
                  ));
                });
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Solo puedes mover hasta $maximoPermitido piezas.'), backgroundColor: Colors.red));
              }
            },
            child: const Text('AL CARRITO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      )
    );
  }

  Future<void> _repartirCarga() async {
    if (_ubicacionDestino == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escanea el MUEBLE DE DESTINO'), backgroundColor: Colors.redAccent));
      return;
    }
    var seleccionados = _carrito.where((item) => item.seleccionadoParaMover).toList();
    if (seleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Toca los productos del carrito que dejarás aquí.')));
      return;
    }

    for (var item in seleccionados) {
      var docRef = FirebaseFirestore.instance.collection('inventario_activo').doc(item.idOriginal);
      var docSnap = await docRef.get();
      if (docSnap.exists) {
        int cantActual = docSnap['cantidad'];
        if (cantActual <= item.cantidadEnCarrito) {
          await docRef.delete();
        } else {
          await docRef.update({'cantidad': cantActual - item.cantidadEnCarrito});
        }
        
        var queryDestino = await FirebaseFirestore.instance.collection('inventario_activo')
            .where('sku', isEqualTo: item.sku)
            .where('ubicacion', isEqualTo: _ubicacionDestino)
            .where('fechaCaducidad', isEqualTo: Timestamp.fromDate(item.fechaCaducidad))
            .limit(1).get();
            
        if (queryDestino.docs.isNotEmpty) {
          int cantDestino = queryDestino.docs.first['cantidad'];
          await queryDestino.docs.first.reference.update({'cantidad': cantDestino + item.cantidadEnCarrito});
        } else {
          var newData = Map<String, dynamic>.from(item.datosOriginales);
          newData['cantidad'] = item.cantidadEnCarrito;
          newData['ubicacion'] = _ubicacionDestino;
          newData['fechaCaptura'] = FieldValue.serverTimestamp();
          await FirebaseFirestore.instance.collection('inventario_activo').add(newData);
        }
      }
    }
    setState(() { _carrito.removeWhere((item) => item.seleccionadoParaMover); });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('¡Trasvase exitoso!'), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.logout, color: Colors.redAccent),
          onPressed: () async { await FirebaseAuth.instance.signOut(); },
        ),
        title: const Text('Operaciones de Piso', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 16)),
        actions: [
          const Center(child: Text("TRASVASE ", style: TextStyle(fontSize: 10))),
          Switch(value: _modoTrasvase, onChanged: (v) => setState(() => _modoTrasvase = v), activeColor: Colors.blueAccent),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('ubicaciones').orderBy('nombre').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const LinearProgressIndicator(color: Colors.amber);
                      List<String> listaMuebles = snapshot.data!.docs.map((d) => d['nombre'] as String).toList();
                      if (_ubicacionDestino != null && !listaMuebles.contains(_ubicacionDestino)) {
                        listaMuebles.add(_ubicacionDestino!);
                      }
                      return Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: _ubicacionDestino != null ? Colors.green.withOpacity(0.1) : Colors.white10,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: _ubicacionDestino != null ? Colors.greenAccent : Colors.white24)
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.location_on, color: _ubicacionDestino != null ? Colors.greenAccent : Colors.white54),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  dropdownColor: const Color(0xFF2C2C2C),
                                  hint: Text(_modoTrasvase ? '1. Selecciona DESTINO' : 'Selecciona Mueble', style: TextStyle(color: _modoTrasvase ? Colors.blueAccent : Colors.white54, fontWeight: _modoTrasvase ? FontWeight.bold : FontWeight.normal)),
                                  value: _ubicacionDestino,
                                  items: [
                                    const DropdownMenuItem<String>(value: null, child: Text('Sin anclar', style: TextStyle(color: Colors.white54))),
                                    ...listaMuebles.map((u) => DropdownMenuItem<String>(value: u, child: Text(u, style: const TextStyle(fontWeight: FontWeight.bold))))
                                  ],
                                  onChanged: (val) { setState(() { _ubicacionDestino = val; }); },
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  ),
                ),
                if (_modoTrasvase && _ubicacionDestino != null) 
                  IconButton(icon: const Icon(Icons.download, color: Colors.blueAccent), tooltip: "Jalar todo el mueble al carrito", onPressed: () async {
                    var snap = await FirebaseFirestore.instance.collection('inventario_activo').where('ubicacion', isEqualTo: _ubicacionDestino).get();
                    if(snap.docs.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El mueble está vacío.'))); return; }
                    for(var doc in snap.docs) {
                      var d = doc.data();
                      setState(() {
                        _carrito.add(ItemCarrito(
                          idOriginal: doc.id,
                          sku: d['sku'],
                          descripcion: d['descripcion'] ?? "ND",
                          cantidadEnCarrito: d['cantidad'],
                          fechaCaducidad: (d['fechaCaducidad'] as Timestamp).toDate(),
                          ubicacionOrigen: _ubicacionDestino!,
                          datosOriginales: d,
                        ));
                      });
                    }
                  })
              ],
            ),
          ),
          
          if (_modoTrasvase && _carrito.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text("🛒 Carrito: ${_carrito.length}", style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)), 
                    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)), onPressed: _repartirCarga, child: const Text("DEJAR EN DESTINO"))
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 90,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _carrito.length,
                      itemBuilder: (context, i) => GestureDetector(
                        onTap: () => setState(() => _carrito[i].seleccionadoParaMover = !_carrito[i].seleccionadoParaMover),
                        child: Container(
                          width: 130, margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(color: _carrito[i].seleccionadoParaMover ? Colors.blueAccent.withOpacity(0.4) : Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: _carrito[i].seleccionadoParaMover ? Colors.blueAccent : Colors.transparent)),
                          child: Stack(children: [
                            Padding(padding: const EdgeInsets.all(6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_carrito[i].descripcion, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9)), 
                              Text("${_carrito[i].cantidadEnCarrito} pz", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.amber)), 
                              Text("De: ${_carrito[i].ubicacionOrigen}", style: const TextStyle(fontSize: 8, color: Colors.white54)),
                              const Spacer(), 
                              Container(height: 3, width: 30, color: EtiquetaMes.obtener(_carrito[i].fechaCaducidad)['color'])
                            ])), 
                            Positioned(right: -10, top: -10, child: IconButton(icon: const Icon(Icons.remove_circle, size: 16, color: Colors.redAccent), onPressed: () => setState(() => _carrito.removeAt(i))))
                          ]),
                        ),
                      ),
                    ),
                  )
                ],
              ),
            ),
            
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25), 
                border: Border.all(color: _modoTrasvase ? Colors.blueAccent : Colors.amber, width: 3)
              ),
              clipBehavior: Clip.hardEdge,
              child: widget.estaActiva 
                  ? Stack(
                      children: [
                        MobileScanner(onDetect: (capture) {
                          if (_bloquearEscaneo) return;
                          final barcode = capture.barcodes.first;
                          if (barcode.rawValue != null) {
                            setState(() => _bloquearEscaneo = true);
                            _procesarEscaneo(barcode.rawValue!);
                          }
                        }),
                        Center(
                          child: SizedBox(
                            width: 250, height: 250,
                            child: Stack(
                              children: [
                                Container(decoration: BoxDecoration(border: Border.all(color: Colors.white30, width: 2), borderRadius: BorderRadius.circular(20))),
                                AnimatedBuilder(
                                  animation: _laserAnimation,
                                  builder: (context, child) => Positioned(
                                    top: _laserAnimation.value, left: 10, right: 10,
                                    child: Container(height: 3, decoration: BoxDecoration(color: Colors.redAccent, boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.8), blurRadius: 10, spreadRadius: 2)])),
                                  )
                                )
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
                          Icon(Icons.videocam_off, size: 60, color: Colors.white24),
                          SizedBox(height: 10),
                          Text('Cámara en reposo\n(Ahorro de batería)', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54))
                        ],
                      ),
                    ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _skuController, 
              decoration: InputDecoration(
                hintText: _modoTrasvase ? '2. Busca SKU o UPC a Mover...' : 'SKU / UPC Manual...', 
                filled: true, fillColor: Colors.white10, 
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)), 
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search, color: Colors.amber), 
                  onPressed: () {
                    if (_skuController.text.isNotEmpty) {
                      setState(() => _bloquearEscaneo = true);
                      _procesarEscaneo(_skuController.text);
                    }
                  }
                )
              ), 
              onSubmitted: (val) {
                if (val.isNotEmpty) {
                  setState(() => _bloquearEscaneo = true);
                  _procesarEscaneo(val);
                }
              }
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
  const PantallaRegistro({super.key, required this.skuEscaneado, this.ubicacionPredefinida, required this.usuarioRegistra});
  @override
  State<PantallaRegistro> createState() => _PantallaRegistroState();
}
class _PantallaRegistroState extends State<PantallaRegistro> {
  DateTime? _fechaSeleccionada;
  String? _ubicacionSeleccionada;
  bool _guardando = false;
  final TextEditingController _cantidadController = TextEditingController(text: "1");
  String _descripcion = "Buscando...";
  Map<String, dynamic>? _datosMaestros;

  @override
  void initState() {
    super.initState();
    if (widget.ubicacionPredefinida != null) { _ubicacionSeleccionada = widget.ubicacionPredefinida; }
    _buscarDatosOriginales();
  }
  
  Future<void> _buscarDatosOriginales() async {
    try {
      var doc = await FirebaseFirestore.instance.collection('maestro_productos').doc(widget.skuEscaneado).get();
      if (mounted) {
        setState(() {
          if (doc.exists) {
            _datosMaestros = doc.data();
            _descripcion = _datosMaestros?['descripcion'] ?? "Sin Nombre";
          } else { _descripcion = "Artículo Nuevo"; }
        });
      }
    } catch (e) { if (mounted) setState(() => _descripcion = "Error"); }
  }

  Future<void> _guardarEnNube() async {
    if (_ubicacionSeleccionada == null || _fechaSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Revisa Fecha y Mueble'), backgroundColor: Colors.redAccent));
      return;
    }
    setState(() => _guardando = true);
    try {
      var map = {
        'sku': widget.skuEscaneado,
        'descripcion': _descripcion,
        'ubicacion': _ubicacionSeleccionada,
        'cantidad': int.tryParse(_cantidadController.text) ?? 1,
        'fechaCaducidad': Timestamp.fromDate(_fechaSeleccionada!),
        'fechaCaptura': FieldValue.serverTimestamp(),
        'capturista': widget.usuarioRegistra,
      };
      if (_datosMaestros != null) map.addAll(_datosMaestros!);
      await FirebaseFirestore.instance.collection('inventario_activo').add(map);
      if (mounted) { Navigator.pop(context); }
    } catch (e) { setState(() => _guardando = false); }
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
                  onDateChanged: (DateTime newDate) {
                    tempDate = newDate;
                  },
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
                    child: const Text('Confirmar')
                  ),
                ],
              )
            ],
          ),
        ),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar Entrada')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(children: [
            Text(_descripcion, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.amber)),
            const SizedBox(height: 30),
            TextField(controller: _cantidadController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad de Piezas', filled: true)),
            const SizedBox(height: 20),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('ubicaciones').orderBy('nombre').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                List<String> listaMuebles = snapshot.data!.docs.map((d) => d['nombre'] as String).toList();
                if (_ubicacionSeleccionada != null && !listaMuebles.contains(_ubicacionSeleccionada)) listaMuebles.add(_ubicacionSeleccionada!);
                return Container(
                  height: 56, padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(5), border: const Border(bottom: BorderSide(color: Colors.white54))),
                  child: Row(children: [
                      const Icon(Icons.location_on, color: Colors.white54),
                      const SizedBox(width: 10),
                      Expanded(child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                            isExpanded: true, dropdownColor: const Color(0xFF2C2C2C),
                            hint: const Text('Selecciona Mueble', style: TextStyle(color: Colors.white54)),
                            value: _ubicacionSeleccionada,
                            items: listaMuebles.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                            onChanged: (val) => setState(() => _ubicacionSeleccionada = val),
                      ))),
                  ]),
                );
              }
            ),
            const SizedBox(height: 20),
            
            ElevatedButton.icon(
              icon: const Icon(Icons.calendar_month), 
              label: Text(_fechaSeleccionada == null ? 'Seleccionar Fecha' : "${_fechaSeleccionada!.day.toString().padLeft(2, '0')} / ${_fechaSeleccionada!.month.toString().padLeft(2, '0')} / ${_fechaSeleccionada!.year}", style: const TextStyle(fontSize: 16)), 
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.white10, foregroundColor: Colors.white),
              onPressed: _mostrarSelectorFechaFluido
            ),

            const SizedBox(height: 50),
            SizedBox(width: double.infinity, height: 60, child: ElevatedButton(onPressed: (_fechaSeleccionada == null || _guardando) ? null : _guardarEnNube, child: _guardando ? const CircularProgressIndicator() : const Text('CONFIRMAR Y GUARDAR')))
          ]),
      ),
    );
  }
}
