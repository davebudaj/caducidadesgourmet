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
  
  // NUEVAS VARIABLES MULTITIENDA
  final String idTiendaGlobal;
  final String nombreTienda;

  const NavegacionPrincipal({
    super.key, 
    required this.esJefe, 
    required this.nombreUsuario, 
    required this.numeroEmpleado,
    required this.idTiendaGlobal,
    required this.nombreTienda
  });
  
  @override
  State<NavegacionPrincipal> createState() => _NavegacionPrincipalState();
}

class _NavegacionPrincipalState extends State<NavegacionPrincipal> {
  int _indiceActual = 0;
  final GlobalKey<PantallaDashboardState> _dashboardKey = GlobalKey(); 

  @override
  void initState() {
    super.initState();
    // Aún no activamos la revisión de misiones automáticas hasta terminar el aislamiento de datos
    // if (widget.esJefe) WidgetsBinding.instance.addPostFrameCallback((_) => _revisarAlertasYGenerarMisiones());
  }

  void _navegarASabanaConFiltro(String filtroRiesgo) {
    setState(() => _indiceActual = 1); 
    _dashboardKey.currentState?.aplicarFiltroEspecial(filtroRiesgo); 
  }

  @override
  Widget build(BuildContext context) {
    // Por ahora, solo pasamos las variables a las pantallas, aunque aún no las usan internamente
    List<Widget> pantallas = [
      PantallaEscaner(estaActiva: _indiceActual == 0, usuarioRegistra: widget.nombreUsuario, idTiendaGlobal: widget.idTiendaGlobal), 
      PantallaDashboard(key: _dashboardKey, usuarioActual: widget.nombreUsuario, idTiendaGlobal: widget.idTiendaGlobal), 
      PantallaMisiones(idTiendaGlobal: widget.idTiendaGlobal)
    ];
    List<BottomNavigationBarItem> items = [
      const BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Escáner'), 
      const BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Sábana'), 
      const BottomNavigationBarItem(icon: Icon(Icons.assignment_late), label: 'Misiones')
    ];
    
    if (widget.esJefe) {
      pantallas.add(PantallaHistorial(idTiendaGlobal: widget.idTiendaGlobal)); 
      items.add(const BottomNavigationBarItem(icon: Icon(Icons.archive), label: 'Historial'));
      
      pantallas.add(PantallaGraficas(onFiltroSeleccionado: _navegarASabanaConFiltro, idTiendaGlobal: widget.idTiendaGlobal)); 
      items.add(const BottomNavigationBarItem(icon: Icon(Icons.pie_chart), label: 'Finanzas'));
      
      pantallas.add(PantallaCorporativo(idTiendaGlobal: widget.idTiendaGlobal)); 
      items.add(const BottomNavigationBarItem(icon: Icon(Icons.account_balance), label: 'Corp'));
      
      pantallas.add(PantallaAdmin(idTiendaGlobal: widget.idTiendaGlobal, nombreTienda: widget.nombreTienda)); 
      items.add(const BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Ajustes'));
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 30, // Una barra pequeñita arriba para que siempre sepan en qué tienda están
        backgroundColor: Colors.blueAccent.shade700,
        title: Text('TIENDA: ${widget.nombreTienda.toUpperCase()} (${widget.idTiendaGlobal})', 
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.white)
        ),
      ),
      body: IndexedStack(index: _indiceActual, children: pantallas),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed, selectedFontSize: 10, unselectedFontSize: 9, currentIndex: _indiceActual,
        onTap: (index) => setState(() => _indiceActual = index), selectedItemColor: Colors.amber, unselectedItemColor: Colors.white54, backgroundColor: Colors.black, items: items
      ),
    );
  }
}
