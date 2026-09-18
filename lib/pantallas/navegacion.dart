import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'escaner.dart';
import 'sabana.dart';
import 'misiones.dart';
import 'finanzas.dart';
import 'historial.dart';
import 'corporativo.dart';
import 'admin.dart';

class NavegacionPrincipal extends StatefulWidget {
  final bool esJefe;
  final String nombreUsuario;
  final String numeroEmpleado;
  const NavegacionPrincipal({super.key, required this.esJefe, required this.nombreUsuario, required this.numeroEmpleado});
  @override
  State<NavegacionPrincipal> createState() => _NavegacionPrincipalState();
}

class _NavegacionPrincipalState extends State<NavegacionPrincipal> {
  int _indiceActual = 0;
  final GlobalKey<PantallaDashboardState> _dashboardKey = GlobalKey(); 

  @override
  void initState() {
    super.initState();
    if (widget.esJefe) WidgetsBinding.instance.addPostFrameCallback((_) => _revisarAlertasYGenerarMisiones());
  }

  Future<void> _revisarAlertasYGenerarMisiones() async {
    try {
      var snapshot = await FirebaseFirestore.instance.collection('inventario_activo').get();
      int caducados = 0; int criticos = 0; DateTime hoy = DateTime.now();
      var batch = FirebaseFirestore.instance.batch(); 
      int misionesNuevas = 0;
      int misionesBodegaNuevas = 0;

      for (var doc in snapshot.docs) {
        var data = doc.data();
        if (data['fechaCaducidad'] != null) {
          DateTime cad = (data['fechaCaducidad'] as Timestamp).toDate();
          int dias = cad.difference(hoy).inDays;
          String ubicacion = data['ubicacion']?.toString().toUpperCase() ?? '';

          if (dias < 0) caducados++;
          else if (dias <= 14) criticos++;

          // Regla 1: Misiones Generales (<= 45 días)
          if (dias <= 45 && dias > 0 && data['misionGenerada45d'] != true) {
            var refMision = FirebaseFirestore.instance.collection('misiones_auditoria').doc();
            batch.set(refMision, {
              'sku': data['sku'], 'descripcion': data['descripcion'] ?? 'ND', 'ubicacion': data['ubicacion'] ?? 'ND',
              'cantidad': data['cantidad'], 'fechaCaducidad': data['fechaCaducidad'], 'nombreProveedor': data['nombreProveedor'] ?? 'ND',
              'nombreGpoArticulos': data['nombreGpoArticulos'] ?? 'SIN GRUPO', 'estado': 'pendiente', 'fechaGeneracion': FieldValue.serverTimestamp(),
              'mensaje': 'Verificar lote próximo a vencer (45 días)'
            });
            batch.update(doc.reference, {'misionGenerada45d': true}); 
            misionesNuevas++;
          }
          
          // Regla 2: Política de Bodega (<= 90 días)
          if (ubicacion.contains('BODEGA') && dias <= 90 && dias > 0 && data['misionBodega90d'] != true) {
            var refMision = FirebaseFirestore.instance.collection('misiones_auditoria').doc();
            batch.set(refMision, {
              'sku': data['sku'], 'descripcion': data['descripcion'] ?? 'ND', 'ubicacion': data['ubicacion'] ?? 'ND',
              'cantidad': data['cantidad'], 'fechaCaducidad': data['fechaCaducidad'], 'nombreProveedor': data['nombreProveedor'] ?? 'ND',
              'nombreGpoArticulos': data['nombreGpoArticulos'] ?? 'SIN GRUPO', 'estado': 'pendiente', 'fechaGeneracion': FieldValue.serverTimestamp(),
              'mensaje': '🚨 POLÍTICA 90 DÍAS: Extraer de Bodega y reubicar en Piso/Display'
            });
            batch.update(doc.reference, {'misionBodega90d': true}); 
            misionesBodegaNuevas++;
          }
        }
      }
      
      if (misionesNuevas > 0 || misionesBodegaNuevas > 0) await batch.commit();

      if (caducados > 0 || criticos > 0 || misionesNuevas > 0 || misionesBodegaNuevas > 0) {
        if (!mounted) return;
        showDialog(context: context, builder: (context) => AlertDialog(backgroundColor: const Color(0xFF1E1E1E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.redAccent, width: 2)), title: Row(children: [const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 30), const SizedBox(width: 10), Expanded(child: Text('Hola, ${widget.nombreUsuario}', style: const TextStyle(color: Colors.white, fontSize: 18)))]), content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Resumen de alertas en piso:', style: TextStyle(color: Colors.white70)), const SizedBox(height: 15), if (caducados > 0) Text('• $caducados lotes CADUCADOS', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 5), if (criticos > 0) Text('• $criticos lotes en CRÍTICO (< 15 días)', style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 15), if (misionesNuevas > 0) Text('• Se generaron $misionesNuevas misiones automáticas (45 días).', style: const TextStyle(color: Colors.blueAccent, fontSize: 12)), const SizedBox(height: 5), if (misionesBodegaNuevas > 0) Text('• $misionesBodegaNuevas lotes violan Política de Bodega (90 días)', style: const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold, fontSize: 13)),]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ENTENDIDO', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)))]));
      }
    } catch (e) { debugPrint("Error: $e"); }
  }

  void _navegarASabanaConFiltro(String filtroRiesgo) {
    setState(() => _indiceActual = 1); 
    _dashboardKey.currentState?.aplicarFiltroEspecial(filtroRiesgo); 
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> pantallas = [PantallaEscaner(estaActiva: _indiceActual == 0, usuarioRegistra: widget.nombreUsuario), PantallaDashboard(key: _dashboardKey, usuarioActual: widget.nombreUsuario), const PantallaMisiones()];
    List<BottomNavigationBarItem> items = [const BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Escáner'), const BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Sábana'), const BottomNavigationBarItem(icon: Icon(Icons.assignment_late), label: 'Misiones')];
    if (widget.esJefe) {
      pantallas.add(const PantallaHistorial()); items.add(const BottomNavigationBarItem(icon: Icon(Icons.archive), label: 'Historial'));
      pantallas.add(PantallaGraficas(onFiltroSeleccionado: _navegarASabanaConFiltro)); items.add(const BottomNavigationBarItem(icon: Icon(Icons.pie_chart), label: 'Finanzas'));
      pantallas.add(const PantallaCorporativo()); items.add(const BottomNavigationBarItem(icon: Icon(Icons.account_balance), label: 'Corp'));
      pantallas.add(const PantallaAdmin()); items.add(const BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Ajustes'));
    }
    return Scaffold(
      body: IndexedStack(index: _indiceActual, children: pantallas),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed, selectedFontSize: 10, unselectedFontSize: 9, currentIndex: _indiceActual,
        onTap: (index) => setState(() => _indiceActual = index), selectedItemColor: Colors.amber, unselectedItemColor: Colors.white54, backgroundColor: Colors.black, items: items
      ),
    );
  }
}
