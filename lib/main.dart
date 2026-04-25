import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:universal_html/html.dart' as html;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const GourmetGuardApp());
}

class ItemCarrito {
  final String idOriginal;
  final String sku;
  final String descripcion;
  int cantidadEnCarrito;
  final DateTime fechaCaducidad;
  final String ubicacionOrigen;
  final Map<String, dynamic> datosOriginales;
  bool seleccionadoParaMover = false;

  ItemCarrito({
    required this.idOriginal,
    required this.sku,
    required this.descripcion,
    required this.cantidadEnCarrito,
    required this.fechaCaducidad,
    required this.ubicacionOrigen,
    required this.datosOriginales,
  });
}

class EtiquetaMes {
  static Map<int, Map<String, dynamic>> colores = {
    1: {'nombre': 'AZUL', 'color': Colors.blue},
    2: {'nombre': 'ROSA', 'color': Colors.pinkAccent},
    3: {'nombre': 'AMARILLO', 'color': Colors.yellow},
    4: {'nombre': 'VERDE', 'color': Colors.green},
    5: {'nombre': 'NARANJA', 'color': Colors.orange},
    6: {'nombre': 'MORADO', 'color': Colors.purple},
    7: {'nombre': 'CELESTE', 'color': Colors.cyan},
    8: {'nombre': 'ROJO', 'color': Colors.red},
    9: {'nombre': 'CAFÉ', 'color': Colors.brown},
    10: {'nombre': 'GRIS', 'color': Colors.grey},
    11: {'nombre': 'LIMA', 'color': Colors.lightGreen},
    12: {'nombre': 'BLANCO', 'color': Colors.white},
  };
  static Map<String, dynamic> obtener(DateTime? fecha) {
    if (fecha == null) return {'nombre': 'NINGUNO', 'color': Colors.transparent};
    return colores[fecha.month] ?? {'nombre': 'BLANCO', 'color': Colors.white};
  }
}

class GourmetGuardApp extends StatelessWidget {
  const GourmetGuardApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gourmet Guard',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(primary: Colors.amber, secondary: Colors.amberAccent),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF000000), centerTitle: true, elevation: 4),
      ),
      home: const EnrutadorSeguridad(),
    );
  }
}

class EnrutadorSeguridad extends StatelessWidget {
  const EnrutadorSeguridad({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (snapshot.hasData) return const NavegacionPrincipal();
        return const PantallaLogin();
      },
    );
  }
}

class PantallaLogin extends StatelessWidget {
  const PantallaLogin({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF121212), Color(0xFF2C2C2C)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield_moon, size: 120, color: Colors.amber),
            const SizedBox(height: 20),
            const Text('GOURMET GUARD', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4, color: Colors.amber)),
            const SizedBox(height: 60),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
              icon: const Icon(Icons.g_mobiledata, size: 30, color: Colors.red),
              label: const Text('Acceder con Google', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              onPressed: () async {
                try { 
                  final creds = await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
                  final user = creds.user;
                  if (user != null) {
                    final email = user.email ?? '';
                    // REGLA DE DOMINIO Y CORREO MAESTRO
                    if (email.endsWith('@liverpool.com.mx') || email == 'davidbustamante1300@gmail.com') {
                       if (context.mounted) {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('¡Bienvenido(a) a Gourmet Guard, ${user.displayName ?? email.split("@")[0]}! 👋'), backgroundColor: Colors.green));
                       }
                    } else {
                       await FirebaseAuth.instance.signOut();
                       if (context.mounted) {
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Acceso denegado: Usa tu correo @liverpool.com.mx'), backgroundColor: Colors.redAccent));
                       }
                    }
                  }
                } catch (e) { debugPrint(e.toString()); }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class NavegacionPrincipal extends StatefulWidget {
  const NavegacionPrincipal({super.key});
  @override
  State<NavegacionPrincipal> createState() => _NavegacionPrincipalState();
}

class _NavegacionPrincipalState extends State<NavegacionPrincipal> {
  int _indiceActual = 0;
  bool _esJefe = false;
  final GlobalKey<PantallaDashboardState> _dashboardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _verificarPrivilegios();
  }

  Future<void> _verificarPrivilegios() async {
    User? usuario = FirebaseAuth.instance.currentUser;
    if (usuario != null) {
      var docUID = await FirebaseFirestore.instance.collection('colaboradores').doc(usuario.uid).get();
      if (docUID.exists && docUID.data()?['rol'] == 'jefe') { setState(() => _esJefe = true); return;
      }
      var docCorreo = await FirebaseFirestore.instance.collection('colaboradores').where('correo', isEqualTo: usuario.email).limit(1).get();
      if (docCorreo.docs.isNotEmpty && docCorreo.docs.first.data()['rol'] == 'jefe') { setState(() => _esJefe = true);
      }
    }
  }

  void _navegarASabanaConFiltro(String filtroRiesgo) {
    setState(() { _indiceActual = 1; });
    _dashboardKey.currentState?.aplicarFiltroEspecial(filtroRiesgo);
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> pantallas = [
      const PantallaEscaner(), 
      PantallaDashboard(key: _dashboardKey), 
      const PantallaMisiones()
    ];
    List<BottomNavigationBarItem> items = [
      const BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Escanear'),
      const BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Sábana'),
      const BottomNavigationBarItem(icon: Icon(Icons.assignment_late), label: 'Misiones'),
    ];
    if (_esJefe) {
      pantallas.add(PantallaGraficas(onFiltroSeleccionado: _navegarASabanaConFiltro));
      items.add(const BottomNavigationBarItem(icon: Icon(Icons.pie_chart), label: 'Finanzas'));
      pantallas.add(const PantallaAdmin());
      items.add(const BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Ajustes'));
    }

    return Scaffold(
      body: IndexedStack(index: _indiceActual, children: pantallas),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _indiceActual,
        onTap: (index) => setState(() => _indiceActual = index),
        selectedItemColor: Colors.amber,
        unselectedItemColor: Colors.white54,
        backgroundColor: Colors.black,
        items: items,
      ),
    );
  }
}

// -------------------------------------------------------------
// PANTALLA ESCÁNER
// -------------------------------------------------------------
class PantallaEscaner extends StatefulWidget {
  const PantallaEscaner({super.key});
  @override
  State<PantallaEscaner> createState() => _PantallaEscanerState();
}

class _PantallaEscanerState extends State<PantallaEscaner> {
  final TextEditingController _skuController = TextEditingController();
  String? _ubicacionActual;
  bool _modoTrasvase = false;
  List<ItemCarrito> _carrito = [];
  
  bool _bloquearEscaneo = false;

  void _procesarEscaneo(String codigo) async {
    String codigoLimpio = codigo.trim();
    
    if (codigoLimpio.startsWith('LOC:')) {
      setState(() { _ubicacionActual = codigoLimpio.substring(4); _skuController.clear(); });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('📍 Ubicación: $_ubicacionActual'), backgroundColor: Colors.green));
      await Future.delayed(const Duration(seconds: 2)); 
    } else if (codigoLimpio.isNotEmpty) {
      if (_modoTrasvase) {
        _abrirSelectorLotes(codigoLimpio);
        await Future.delayed(const Duration(seconds: 2));
      } else {
        await Navigator.push(context, MaterialPageRoute(builder: (context) => PantallaRegistro(skuEscaneado: codigoLimpio, ubicacionPredefinida: _ubicacionActual)));
      }
      _skuController.clear();
    }
    
    if (mounted) {
      setState(() => _bloquearEscaneo = false);
    }
  }

  void _recolectarDeMueble(String nombreMueble) async {
    var snapshot = await FirebaseFirestore.instance.collection('inventario_activo').where('ubicacion', isEqualTo: nombreMueble).get();
    if (snapshot.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este mueble está vacío.')));
      return;
    }
    _mostrarListaRecoleccion(snapshot.docs, nombreMueble);
  }

  void _mostrarListaRecoleccion(List<QueryDocumentSnapshot> docs, String mueble) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Contenido en: $mueble', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amber)),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  var d = docs[i].data() as Map<String, dynamic>;
                  DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
                  return ListTile(
                    leading: Icon(Icons.inventory_2, color: EtiquetaMes.obtener(cad)['color']),
                    title: Text(d['descripcion'] ?? d['sku']),
                    subtitle: Text('Existencia: ${d['cantidad']}'),
                    trailing: const Icon(Icons.add_shopping_cart, color: Colors.amber),
                    onTap: () {
                      Navigator.pop(context);
                      _pedirCantidad(docs[i].id, d);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirSelectorLotes(String sku) async {
    var snapshot = await FirebaseFirestore.instance.collection('inventario_activo').where('sku', isEqualTo: sku).get();
    if (snapshot.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay existencias.')));
      return;
    }
    _mostrarListaRecoleccion(snapshot.docs, "Resultados SKU");
  }

  void _pedirCantidad(String docId, Map<String, dynamic> data) {
    TextEditingController c = TextEditingController(text: data['cantidad'].toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mover cantidad'),
        content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'Piezas')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          ElevatedButton(
            onPressed: () {
              int cant = int.tryParse(c.text) ?? 0;
              if (cant > 0 && cant <= (data['cantidad'] ?? 0)) {
                setState(() {
                  _carrito.add(ItemCarrito(
                    idOriginal: docId,
                    sku: data['sku'],
                    descripcion: data['descripcion'] ?? "ND",
                    cantidadEnCarrito: cant,
                    fechaCaducidad: (data['fechaCaducidad'] as Timestamp).toDate(),
                    ubicacionOrigen: data['ubicacion'],
                    datosOriginales: data,
                  ));
                });
                Navigator.pop(context);
              }
            },
            child: const Text('AL CARRITO'),
          )
        ],
      )
    );
  }

  Future<void> _repartirCarga() async {
    if (_ubicacionActual == null) {
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
        if (cantActual == item.cantidadEnCarrito) {
          await docRef.delete();
        } else {
          await docRef.update({'cantidad': cantActual - item.cantidadEnCarrito});
        }
        var queryDestino = await FirebaseFirestore.instance.collection('inventario_activo')
            .where('sku', isEqualTo: item.sku)
            .where('ubicacion', isEqualTo: _ubicacionActual)
            .where('fechaCaducidad', isEqualTo: Timestamp.fromDate(item.fechaCaducidad))
            .limit(1).get();
        if (queryDestino.docs.isNotEmpty) {
          int cantDestino = queryDestino.docs.first['cantidad'];
          await queryDestino.docs.first.reference.update({'cantidad': cantDestino + item.cantidadEnCarrito});
        } else {
          var newData = Map<String, dynamic>.from(item.datosOriginales);
          newData['cantidad'] = item.cantidadEnCarrito;
          newData['ubicacion'] = _ubicacionActual;
          newData['fechaCaptura'] = FieldValue.serverTimestamp();
          await FirebaseFirestore.instance.collection('inventario_activo').add(newData);
        }
      }
    }
    setState(() { _carrito.removeWhere((item) => item.seleccionadoParaMover); });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trasvase parcial éxito!'), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Operaciones de Piso', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
        actions: [
          const Center(child: Text("TRASVASE ", style: TextStyle(fontSize: 10))),
          Switch(value: _modoTrasvase, onChanged: (v) => setState(() => _modoTrasvase = v), activeColor: Colors.blueAccent),
          // BOTÓN DE CERRAR SESIÓN
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Cerrar Sesión',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // NUEVO CINTILLO: Centro y Operador
          FutureBuilder<QuerySnapshot>(
            future: FirebaseFirestore.instance.collection('maestro_productos').limit(1).get(),
            builder: (context, snapshot) {
              String centro = "Buscando centro...";
              if (snapshot.connectionState == ConnectionState.done) {
                if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                  centro = snapshot.data!.docs.first['centro']?.toString() ?? 'LIVERPOOL';
                } else {
                  centro = 'LIVERPOOL (Sin BD)';
                }
              }
              String operador = FirebaseAuth.instance.currentUser?.displayName ?? FirebaseAuth.instance.currentUser?.email?.split('@')[0] ?? 'Operador';
              
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white10)),
                  color: Colors.black26,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.storefront, color: Colors.amber, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Cen: $centro', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                    const Icon(Icons.person, color: Colors.blueAccent, size: 18),
                    const SizedBox(width: 5),
                    Text(operador, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }
          ),
          
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
                      if (_ubicacionActual != null && !listaMuebles.contains(_ubicacionActual)) {
                        listaMuebles.add(_ubicacionActual!);
                      }
                      return Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: _ubicacionActual != null ? Colors.green.withOpacity(0.1) : Colors.white10,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: _ubicacionActual != null ? Colors.greenAccent : Colors.white24)
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.location_on, color: _ubicacionActual != null ? Colors.greenAccent : Colors.white54),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  dropdownColor: const Color(0xFF2C2C2C),
                                  hint: const Text('Selecciona Mueble / Destino', style: TextStyle(color: Colors.white54)),
                                  value: _ubicacionActual,
                                  items: [
                                    const DropdownMenuItem<String>(value: null, child: Text('Sin anclar', style: TextStyle(color: Colors.white54))),
                                    ...listaMuebles.map((u) => DropdownMenuItem<String>(value: u, child: Text(u, style: const TextStyle(fontWeight: FontWeight.bold))))
                                  ],
                                  onChanged: (val) { setState(() { _ubicacionActual = val; }); },
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  ),
                ),
                if (_modoTrasvase && _ubicacionActual != null) 
                  IconButton(icon: const Icon(Icons.file_download, color: Colors.amber), onPressed: () => _recolectarDeMueble(_ubicacionActual!))
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
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("🛒 Carrito: ${_carrito.length}"), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)), onPressed: _repartirCarga, child: const Text("DEJAR SELECCIONADOS"))]),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 90,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _carrito.length,
                      itemBuilder: (context, i) => GestureDetector(
                        onTap: () => setState(() => _carrito[i].seleccionadoParaMover = !_carrito[i].seleccionadoParaMover),
                        child: Container(
                          width: 110, margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(color: _carrito[i].seleccionadoParaMover ? Colors.blueAccent.withOpacity(0.4) : Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: _carrito[i].seleccionadoParaMover ? Colors.blueAccent : Colors.transparent)),
                          child: Stack(children: [Padding(padding: const EdgeInsets.all(6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_carrito[i].descripcion, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9)), Text("${_carrito[i].cantidadEnCarrito} pz", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.amber)), const Spacer(), Container(height: 3, width: 30, color: EtiquetaMes.obtener(_carrito[i].fechaCaducidad)['color'])])), Positioned(right: -10, top: -10, child: IconButton(icon: const Icon(Icons.remove_circle, size: 16, color: Colors.redAccent), onPressed: () => setState(() => _carrito.removeAt(i))))]),
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double centerX = constraints.maxWidth / 2;
                  final double centerY = constraints.maxHeight / 2;
                  final Rect zonaEscaneo = Rect.fromCenter(
                    center: Offset(centerX, centerY),
                    width: 250,
                    height: 250,
                  );

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      MobileScanner(
                        scanWindow: zonaEscaneo,
                        onDetect: (capture) {
                          if (_bloquearEscaneo) return;

                          final barcode = capture.barcodes.first;
                          if (barcode.rawValue != null) {
                            setState(() => _bloquearEscaneo = true);
                            _procesarEscaneo(barcode.rawValue!);
                          }
                        }
                      ),
                      Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Container(
                            width: 250,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              boxShadow: [
                                BoxShadow(color: Colors.red.withOpacity(0.8), blurRadius: 10, spreadRadius: 2)
                              ]
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _skuController, 
              decoration: InputDecoration(
                hintText: 'SKU / EAN Manual...', 
                filled: true, 
                fillColor: Colors.white10, 
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)), 
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send, color: Colors.amber), 
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

// -------------------------------------------------------------
// PANTALLA REGISTRO
// -------------------------------------------------------------
class PantallaRegistro extends StatefulWidget {
  final String skuEscaneado;
  final String? ubicacionPredefinida;
  const PantallaRegistro({super.key, required this.skuEscaneado, this.ubicacionPredefinida});
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
        'capturista': FirebaseAuth.instance.currentUser?.email,
      };
      if (_datosMaestros != null) map.addAll(_datosMaestros!);
      await FirebaseFirestore.instance.collection('inventario_activo').add(map);
      if (mounted) { Navigator.pop(context); }
    } catch (e) { setState(() => _guardando = false); }
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
            ElevatedButton.icon(icon: const Icon(Icons.calendar_month), label: Text(_fechaSeleccionada == null ? 'Seleccionar Fecha' : _fechaSeleccionada.toString()), onPressed: () async {
                final s = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 2000)));
                if (s != null) setState(() => _fechaSeleccionada = s);
            }),
            const SizedBox(height: 50),
            SizedBox(width: double.infinity, height: 60, child: ElevatedButton(onPressed: (_fechaSeleccionada == null || _guardando) ? null : _guardarEnNube, child: _guardando ? const CircularProgressIndicator() : const Text('CONFIRMAR Y GUARDAR')))
          ]),
      ),
    );
  }
}

// -------------------------------------------------------------
// PANTALLA DASHBOARD (SÁBANA CON FILTROS E INTERACTIVIDAD)
// -------------------------------------------------------------
class PantallaDashboard extends StatefulWidget {
  const PantallaDashboard({super.key});
  @override
  State<PantallaDashboard> createState() => PantallaDashboardState();
}

class PantallaDashboardState extends State<PantallaDashboard> {
  String _busqueda = "";
  String? _filtroProveedor;
  String? _filtroGrupo;
  String? _filtroRiesgoEspecial; 

  void aplicarFiltroEspecial(String riesgo) {
    setState(() {
      _filtroRiesgoEspecial = riesgo;
      _filtroProveedor = null; 
      _filtroGrupo = null;
    });
  }

  void _verDetalleCompleto(Map<String, dynamic> d) {
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
              _infoRow("EAN", d['ean'] ?? 'ND'),
              _infoRow("PROVEEDOR", d['nombreProveedor']),
              _infoRow("GRUPO", d['nombreGpoArticulos']),
              _infoRow("UBICACIÓN PISO", d['ubicacion']),
              _infoRow("CANTIDAD", d['cantidad'].toString() + " pzas"),
              _infoRow("PRECIO VENTA", "MXN " + d['precioVenta'].toString()),
              _infoRow("OH TEÓRICO SAP", d['oh'] ?? '0'),
              _infoRow("CADUCIDAD", "${cad.day}/${cad.month}/${cad.year}"),
              const Divider(color: Colors.white24),
              _infoRow("CAPTURISTA", d['capturista']),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('CERRAR', style: TextStyle(color: Colors.white54)))],
      )
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sábana de Riesgo', style: TextStyle(fontWeight: FontWeight.bold))),
      body: Column(
        children: [
          if (_filtroRiesgoEspecial != null)
            Container(
              color: Colors.redAccent.withOpacity(0.8),
              child: ListTile(
                title: Text('Viendo solo riesgo: ${_filtroRiesgoEspecial!.toUpperCase()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                trailing: IconButton(icon: const Icon(Icons.clear, color: Colors.white), onPressed: () => setState(() => _filtroRiesgoEspecial = null)),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.black,
              border: Border(bottom: BorderSide(color: Colors.white24, width: 1))
            ),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar SKU o Artículo...',
                    prefixIcon: const Icon(Icons.search, color: Colors.amber),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0)
                  ),
                  onChanged: (v) => setState(() => _busqueda = v.toLowerCase()),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('inventario_activo').snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const SizedBox();
                          var provs = snapshot.data!.docs.map((doc) {
                            var data = doc.data() as Map<String, dynamic>;
                            return data['nombreProveedor']?.toString() ?? 'ND';
                          }).toSet().toList()..sort();
                          return Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                isExpanded: true, 
                                dropdownColor: const Color(0xFF2C2C2C),
                                value: _filtroProveedor, 
                                hint: const Text('Proveedor', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('Todos', style: TextStyle(fontSize: 12, color: Colors.greenAccent))), 
                                  ...provs.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))
                                ],
                                onChanged: (v) => setState(() => _filtroProveedor = v),
                              ),
                            ),
                          );
                        }
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('inventario_activo').snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const SizedBox();
                          var grupos = snapshot.data!.docs.map((doc) {
                            var data = doc.data() as Map<String, dynamic>;
                            return data['nombreGpoArticulos']?.toString() ?? 'ND';
                          }).toSet().toList()..sort();
                          
                          return Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                isExpanded: true, 
                                dropdownColor: const Color(0xFF2C2C2C),
                                value: _filtroGrupo, 
                                hint: const Text('Gpo Artículos', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('Todos', style: TextStyle(fontSize: 12, color: Colors.greenAccent))), 
                                  ...grupos.map((g) => DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))
                                ],
                                onChanged: (v) => setState(() => _filtroGrupo = v),
                              ),
                            ),
                          );
                        }
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('inventario_activo').orderBy('fechaCaducidad').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.amber));
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Inventario sano.'));
                
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

                if (docsFinales.isEmpty) {
                  return const Center(child: Text('No hay productos que coincidan.', style: TextStyle(color: Colors.white54)));
                }

                return ListView.builder(
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: etiqueta['color'].withOpacity(0.5))),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        onTap: () => _verDetalleCompleto(d),
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// PANTALLA MISIONES (Corregida y Mejorada)
// -------------------------------------------------------------
class PantallaMisiones extends StatelessWidget {
  const PantallaMisiones({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Misiones de Auditoría', style: TextStyle(fontWeight: FontWeight.bold))),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('misiones_auditoria').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error de Firebase: \n${snapshot.error}', style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.amber));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Todo en orden. Sin misiones pendientes.'));
          }
          
          var misionesPendientes = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            return data['estado'] == 'pendiente';
          }).toList();

          if (misionesPendientes.isEmpty) {
            return const Center(
              child: Text(
                '¡Piso Limpio!\nSin misiones pendientes.', 
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                textAlign: TextAlign.center,
              )
            );
          }

          return ListView.builder(
            itemCount: misionesPendientes.length,
            itemBuilder: (context, i) {
              var m = misionesPendientes[i].data() as Map<String, dynamic>;
              return Card(
                color: Colors.white10,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.assignment_late, color: Colors.amber, size: 30),
                  title: Text(m['descripcion'] ?? m['sku'], style: const TextStyle(fontWeight: FontWeight.bold)), 
                  subtitle: Text('Ir a: ${m['ubicacion']}\nDescontar: ${m['descontado']} pzas', style: const TextStyle(color: Colors.white70)), 
                  trailing: const Icon(Icons.chevron_right, color: Colors.amber),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// -------------------------------------------------------------
// FINANZAS: DASHBOARD REAL CON GRÁFICO INTERACTIVO (Mejorado)
// -------------------------------------------------------------
class PantallaGraficas extends StatefulWidget {
  final Function(String) onFiltroSeleccionado;
  const PantallaGraficas({super.key, required this.onFiltroSeleccionado});

  @override
  State<PantallaGraficas> createState() => _PantallaGraficasState();
}

class _PantallaGraficasState extends State<PantallaGraficas> {
  int _indiceTocado = -1; 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Salud e Impacto Financiero', style: TextStyle(fontWeight: FontWeight.bold))),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('inventario_activo').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.amber));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Sin datos financieros.'));

          double totalRiesgo = 0;
          double valorSano = 0, valorProximo = 0, valorCritico = 0, valorCaducado = 0;
          Map<String, double> riesgoPorProveedor = {};
          DateTime hoy = DateTime.now();

          for (var doc in snapshot.data!.docs) {
            var data = doc.data() as Map<String, dynamic>;
            Timestamp? ts = data['fechaCaducidad'];
            if (ts == null) continue;
            
            DateTime cad = ts.toDate();
            int dias = cad.difference(hoy).inDays;
            int cant = data['cantidad'] ?? 0;
            double precio = double.tryParse(data['precioVenta'].toString()) ?? 0.0;
            double valor = cant * precio;

            if (dias < 0) {
              valorCaducado += valor;
            } else if (dias <= 14) {
              valorCritico += valor;
              totalRiesgo += valor;
            } else if (dias <= 30) {
              valorProximo += valor;
              totalRiesgo += valor; 
            } else {
              valorSano += valor;
            }

            if (dias <= 30) {
              String prov = data['nombreProveedor'] ?? 'DESCONOCIDO';
              riesgoPorProveedor[prov] = (riesgoPorProveedor[prov] ?? 0) + valor;
            }
          }

          var proveedoresOrdenados = riesgoPorProveedor.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          List<PieChartSectionData> rebanadas = [];
          List<String> idFiltro = [];
          double totalInventario = valorSano + valorProximo + valorCritico + valorCaducado;
          int indiceConstruccion = 0;

          void agregarRebanada(double valor, Color color, String titulo, String id) {
            if (valor > 0) {
              final esTocado = _indiceTocado == indiceConstruccion;
              final porcentaje = ((valor / totalInventario) * 100).toStringAsFixed(1);
              
              rebanadas.add(PieChartSectionData(
                value: valor,
                color: color,
                title: esTocado ? '$porcentaje%' : titulo,
                radius: esTocado ? 70 : 55, 
                titleStyle: TextStyle(
                  fontSize: esTocado ? 16 : 10, 
                  fontWeight: FontWeight.bold, 
                  color: color == Colors.redAccent ? Colors.white : Colors.black,
                  shadows: esTocado ? [const Shadow(color: Colors.black45, blurRadius: 2)] : [],
                )
              ));
              idFiltro.add(id);
              indiceConstruccion++;
            }
          }

          agregarRebanada(valorSano, Colors.greenAccent, 'Sano\n>30d', 'sano');
          agregarRebanada(valorProximo, Colors.yellow, 'Próximo\n15-30d', 'proximo');
          agregarRebanada(valorCritico, Colors.orangeAccent, 'Crítico\n<15d', 'critico');
          agregarRebanada(valorCaducado, Colors.redAccent, 'Caducado\nYa!', 'caducado');

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const Align(alignment: Alignment.centerLeft, child: Text('Distribución Global del Inventario (MXN)', style: TextStyle(fontSize: 16, color: Colors.white70))),
                const SizedBox(height: 10),
                
                SizedBox(
                  height: 180,
                  child: rebanadas.isEmpty ? const Center(child: Text("No hay valor registrado")) : PieChart(
                    PieChartData(
                      sectionsSpace: 4,
                      centerSpaceRadius: 35,
                      sections: rebanadas,
                      pieTouchData: PieTouchData(
                        touchCallback: (FlTouchEvent event, pieTouchResponse) {
                          if (!event.isInterestedForInteractions || pieTouchResponse == null || pieTouchResponse.touchedSection == null) {
                            if (_indiceTocado != -1) {
                              setState(() => _indiceTocado = -1);
                            }
                            return;
                          }
                          
                          int nuevoIndice = pieTouchResponse.touchedSection!.touchedSectionIndex;
                          
                          if (nuevoIndice != _indiceTocado) {
                            setState(() => _indiceTocado = nuevoIndice);
                          }
                          
                          if (event is FlTapUpEvent && nuevoIndice >= 0 && nuevoIndice < idFiltro.length) {
                            widget.onFiltroSeleccionado(idFiltro[nuevoIndice]);
                            setState(() => _indiceTocado = -1); 
                          }
                        }
                      )
                    )
                  ),
                ),
                const SizedBox(height: 20),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Colors.redAccent, Colors.orangeAccent]),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))]
                  ),
                  child: Column(
                    children: [
                      const Text('Riesgo Total de Merma (≤ 30 días)', style: TextStyle(color: Colors.white, fontSize: 14)),
                      const SizedBox(height: 5),
                      Text('MXN ${totalRiesgo.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                const Align(alignment: Alignment.centerLeft, child: Text('Top Proveedores en Riesgo', style: TextStyle(fontSize: 16, color: Colors.amber, fontWeight: FontWeight.bold))),
                const SizedBox(height: 10),
                Expanded(
                  child: proveedoresOrdenados.isEmpty
                      ? const Center(child: Text('No hay mercancía en riesgo a 30 días. ¡Excelente!', style: TextStyle(color: Colors.greenAccent)))
                      : ListView.builder(
                          itemCount: proveedoresOrdenados.length,
                          itemBuilder: (context, index) {
                            var item = proveedoresOrdenados[index];
                            double porcentaje = totalRiesgo > 0 ? item.value / totalRiesgo : 0;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(child: Text(item.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), overflow: TextOverflow.ellipsis)),
                                      Text('MXN ${item.value.toStringAsFixed(2)}', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  LinearProgressIndicator(
                                    value: porcentaje,
                                    backgroundColor: Colors.white10,
                                    color: Colors.amber,
                                    minHeight: 8,
                                    borderRadius: BorderRadius.circular(5),
                                  )
                                ],
                              ),
                            );
                          },
                        ),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}

// -------------------------------------------------------------
// PANTALLA ADMIN
// -------------------------------------------------------------
class PantallaAdmin extends StatefulWidget {
  const PantallaAdmin({super.key});
  @override
  State<PantallaAdmin> createState() => _PantallaAdminState();
}

class _PantallaAdminState extends State<PantallaAdmin> {
  final TextEditingController _muebleController = TextEditingController();
  final TextEditingController _correoEmpleadoController = TextEditingController();
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
          child: Container(
            color: Colors.white,
            width: 250, height: 250,
            alignment: Alignment.center,
            child: QrImageView(data: 'LOC:$nombreMueble', version: QrVersions.auto, size: 200.0, backgroundColor: Colors.white),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CERRAR', style: TextStyle(color: Colors.grey))),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
            icon: const Icon(Icons.download),
            label: const Text('DESCARGAR PNG'),
            onPressed: () => _descargarQRComoImagen(nombreMueble),
          )
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
      final anchor = html.AnchorElement(href: url)
        ..setAttribute("download", "QR_" + nombre + ".png")
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      debugPrint("Error descargando QR: " + e.toString());
    }
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
            String zonaVentas = columnas[0].replaceAll('"', '').trim();
            String centro = columnas[1].replaceAll('"', '').trim();
            String almacen = columnas[2].replaceAll('"', '').trim();
            String idProveedor = columnas[3].replaceAll('"', '').trim();
            String nombreProveedor = columnas[4].replaceAll('"', '').trim();
            String idCategoria = columnas[5].replaceAll('"', '').trim();
            String nombreGpoArticulos = columnas[6].replaceAll('"', '').trim();
            String estadoProd = columnas[7].replaceAll('"', '').trim();
            String ean = columnas[8].replaceAll('"', '').split('.')[0].trim();
            String sku = columnas[9].replaceAll('"', '').split('.')[0].trim(); 
            String descripcion = columnas[10].replaceAll('"', '').trim();
            String precioVenta = columnas[11].replaceAll('"', '').trim(); 
            String oh = columnas[12].replaceAll('"', '').trim();
            
            Map<String, dynamic> dataProducto = {
              'zonaVentas': zonaVentas, 'centro': centro, 'almacen': almacen, 'idProveedor': idProveedor,
              'nombreProveedor': nombreProveedor, 'idCategoria': idCategoria, 'nombreGpoArticulos': nombreGpoArticulos,
              'estado': estadoProd, 'sku': sku, 'ean': ean, 'descripcion': descripcion, 'precioVenta': precioVenta, 'oh': oh
            };
            if (ean.isNotEmpty && ean != "0") { lote.set(db.collection('maestro_productos').doc(ean), dataProducto); operacionesEnLote++; contadorSubidas++; }
            if (sku.isNotEmpty) { lote.set(db.collection('maestro_productos').doc(sku), dataProducto); operacionesEnLote++; contadorSubidas++; }
            if (operacionesEnLote >= 450) { await lote.commit(); lote = db.batch(); operacionesEnLote = 0; }
          }
        }
        if (operacionesEnLote > 0) { await lote.commit(); }
        setState(() { _procesando = false; _estado = "¡Éxito!\nSe mapearon " + contadorSubidas.toString() + " registros al Catálogo."; });
      }
    } catch (e) {
      setState(() { _procesando = false; _estado = "Ocurrió un error:\n" + e.toString(); });
    }
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
            int cantidadVendida = int.tryParse(columnas[1].replaceAll('"', '').trim()) ?? 0;
            if (sku.isNotEmpty && cantidadVendida > 0) {
              ventasProcesadas[sku] = (ventasProcesadas[sku] ?? 0) + cantidadVendida;
            }
          }
        }

        int misionesGeneradas = 0;

        for (var sku in ventasProcesadas.keys) {
          int porDescontar = ventasProcesadas[sku]!;
          var query = await FirebaseFirestore.instance.collection('inventario_activo').where('sku', isEqualTo: sku).orderBy('fechaCaducidad').get();

          for (var doc in query.docs) {
            if (porDescontar <= 0) break;

            int cantActual = doc['cantidad'] ?? 0;
            int descontadoAqui = 0;

            if (cantActual <= porDescontar) {
              descontadoAqui = cantActual;
              porDescontar -= cantActual;
              await doc.reference.delete(); 
            } else {
              descontadoAqui = porDescontar;
              await doc.reference.update({'cantidad': cantActual - porDescontar});
              porDescontar = 0;
            }

            if (descontadoAqui > 0) {
              Map<String, dynamic> data = doc.data();
              await FirebaseFirestore.instance.collection('misiones_auditoria').add({
                'sku': sku,
                'descripcion': data['descripcion'] ?? 'ND',
                'ubicacion': data['ubicacion'] ?? 'ND',
                'descontado': descontadoAqui,
                'fechaCaducidad': data['fechaCaducidad'], 
                'nombreProveedor': data['nombreProveedor'] ?? 'ND',
                'nombreGpoArticulos': data['nombreGpoArticulos'] ?? 'ND',
                'precioVenta': data['precioVenta'] ?? 0,
                'estado': 'pendiente',
                'fechaGeneracion': FieldValue.serverTimestamp(),
              });
              misionesGeneradas++;
            }
          }
        }
        setState(() { _procesando = false; _estado = "¡Cierre Exitoso!\nSe generaron " + misionesGeneradas.toString() + " misiones para piso."; });
      }
    } catch (e) {
      setState(() { _procesando = false; _estado = "Error en ventas:\n" + e.toString(); });
    }
  }

  Future<void> _agregarMueble() async {
    if (_muebleController.text.trim().isNotEmpty) {
      await FirebaseFirestore.instance.collection('ubicaciones').add({'nombre': _muebleController.text.trim().toUpperCase()});
      _muebleController.clear();
    }
  }

  Future<void> _agregarColaborador() async {
    String correo = _correoEmpleadoController.text.trim().toLowerCase();
    if (correo.isNotEmpty && correo.contains('@')) {
      await FirebaseFirestore.instance.collection('colaboradores').add({'correo': correo, 'rol': _rolSeleccionado});
      _correoEmpleadoController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Empleado autorizado.'), backgroundColor: Colors.green));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes del Sistema (Jefe)', style: TextStyle(fontSize: 16)),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
              ),
              icon: const Icon(Icons.cloud_download, size: 18),
              label: const Text('DESCARGAR SAP BD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              onPressed: () {
                html.window.open('https://sapbjp00db.liverpool.com.mx/irj/servlet/prt/portal/prtroot/pcd!3aportal_content!2fcom.sap.pct!2fplatform_add_ons!2fcom.sap.ip.bi!2fiViews!2fcom.sap.ip.bi.bex?BOOKMARK=1TUPM9LFHL4Q6JPS3QRZFIZMX', '_blank');
              },
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.settings_applications, size: 80, color: Colors.white24),
              const SizedBox(height: 10),
              Text(_estado, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.amber)),
              const SizedBox(height: 20),
              
              if (_procesando) 
                const CircularProgressIndicator(color: Colors.amber)
              else 
                Column(
                  children: [
                    SizedBox(
                      height: 50, width: double.infinity, 
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, foregroundColor: Colors.white), 
                        icon: const Icon(Icons.upload_file), 
                        label: const Text('ACTUALIZAR CATÁLOGO MAESTRO (CSV)'), 
                        onPressed: _cargarCSV
                      )
                    ),
                    const SizedBox(height: 15),
                    SizedBox(
                      height: 50, width: double.infinity, 
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black), 
                        icon: const Icon(Icons.point_of_sale), 
                        label: const Text('CARGAR VENTAS DEL DÍA (CSV)'), 
                        onPressed: _cargarVentasCSV
                      )
                    ),
                  ],
                ),
              
              const SizedBox(height: 40),
              const Divider(color: Colors.white24),
              const SizedBox(height: 20),

              const Text('Gestión de Accesos (Gafetes)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.amber)),
              const SizedBox(height: 20),
              
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _correoEmpleadoController,
                      decoration: InputDecoration(hintText: 'correo@gmail.com', filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 1,
                    child: Container(
                      height: 56, 
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _rolSeleccionado,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF2C2C2C),
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.amber),
                          items: const [
                            DropdownMenuItem(value: 'piso', child: Text('Piso')),
                            DropdownMenuItem(value: 'jefe', child: Text('Jefe'))
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _rolSeleccionado = val);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: _agregarColaborador,
                    child: const Icon(Icons.person_add),
                  )
                ],
              ),

              const SizedBox(height: 20),
              Container(
                height: 200, 
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)),
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('colaboradores').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.amber));
                    if (snapshot.data!.docs.isEmpty) return const Center(child: Text('Nadie autorizado.'));
                    return ListView.builder(
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        var doc = snapshot.data!.docs[index];
                        return ListTile(
                          leading: Icon(doc['rol'] == 'jefe' ? Icons.star : Icons.person, color: doc['rol'] == 'jefe' ? Colors.amber : Colors.white54),
                          title: Text(doc['correo'], style: const TextStyle(fontWeight: FontWeight.w500)),
                          trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => doc.reference.delete()),
                        );
                      },
                    );
                  }
                ),
              ),

              const SizedBox(height: 40),
              const Divider(color: Colors.white24),
              const SizedBox(height: 20),

              const Text('Gestión de Ubicaciones y QR', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.amber)),
              const SizedBox(height: 20),
              
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _muebleController,
                      decoration: InputDecoration(hintText: 'Ej. BODEGA LACTEOS', filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: _agregarMueble,
                    child: const Icon(Icons.add),
                  )
                ],
              ),
              
              const SizedBox(height: 20),
              Container(
                height: 250, 
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)),
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('ubicaciones').orderBy('nombre').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    if (snapshot.data!.docs.isEmpty) return const Center(child: Text('Sin muebles.'));
                    return ListView.builder(
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        var doc = snapshot.data!.docs[index];
                        String nombreMueble = doc['nombre'];
                        return ListTile(
                          title: Text(nombreMueble, style: const TextStyle(fontWeight: FontWeight.w500)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.qr_code, color: Colors.blueAccent), tooltip: "Imprimir QR", onPressed: () => _mostrarYDescargarQR(nombreMueble)),
                              IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => doc.reference.delete()),
                            ],
                          ),
                        );
                      },
                    );
                  }
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
