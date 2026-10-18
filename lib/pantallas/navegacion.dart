import 'package:flutter/material.dart';
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
  final String idTiendaGlobal;
  final String nombreTienda;

  const NavegacionPrincipal({
    super.key,
    required this.esJefe,
    required this.nombreUsuario,
    required this.numeroEmpleado,
    required this.idTiendaGlobal,
    required this.nombreTienda,
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _revisarAlertasYGenerarMisiones());
  }

  Future<void> _revisarAlertasYGenerarMisiones() async {
    try {
      var refTienda = FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal);
      var snapshot = await refTienda.collection('inventario_activo').get();

      int caducados = 0;
      int criticos = 0;
      int misionesNuevas = 0;
      int misionesBodegaNuevas = 0;
      int lotesCarritoOlvidados = 0;
      int lotesCarritoActivos = 0;

      DateTime hoy = DateTime.now();
      var batch = FirebaseFirestore.instance.batch();

      for (var doc in snapshot.docs) {
        var data = doc.data();
        String ubicacion = (data['ubicacion'] ?? '').toString().toUpperCase();

        // Revisar si el lote quedó en el CARRITO EN TRÁNSITO
        if (ubicacion == 'EN TRÁNSITO') {
          lotesCarritoActivos++;
          Timestamp? tsTransito = data['fechaTransito'];
          bool esDeDiaAnterior = false;
          if (tsTransito != null) {
            DateTime fT = tsTransito.toDate();
            esDeDiaAnterior = (fT.year != hoy.year || fT.month != hoy.month || fT.day != hoy.day);
          } else {
            esDeDiaAnterior = true;
          }

          if (esDeDiaAnterior) {
            lotesCarritoOlvidados++;
            if (data['misionTransitoGenerada'] != true) {
              var refMision = refTienda.collection('misiones_auditoria').doc();
              batch.set(refMision, {
                'sku': data['sku'],
                'descripcion': data['descripcion'] ?? 'ND',
                'ubicacion': 'EN TRÁNSITO (Origen: ${data['ubicacionOrigen'] ?? 'ND'})',
                'cantidad': data['cantidad'],
                'fechaCaducidad': data['fechaCaducidad'],
                'nombreProveedor': data['nombreProveedor'] ?? 'ND',
                'nombreGpoArticulos': data['nombreGpoArticulos'] ?? 'SIN GRUPO',
                'estado': 'pendiente',
              if (data['comentarioCorporativo'] != null) 'comentarioCorporativo': data['comentarioCorporativo'],
                'fechaGeneracion': FieldValue.serverTimestamp(),
                'mensaje': '🚨 CARRITO ABANDONADO: Mercancía en tránsito desde el día anterior sin acomodar',
              });
              batch.update(doc.reference, {'misionTransitoGenerada': true});
            }
          }
        }

        if (data['fechaCaducidad'] != null) {
          DateTime cad = (data['fechaCaducidad'] as Timestamp).toDate();
          int dias = cad.difference(hoy).inDays;

          if (dias < 0) {
            caducados++;
          } else if (dias <= 14) {
            criticos++;
          }

          if (dias <= 15 && data['misionReactivada15d'] != true) {
            var refMision = refTienda.collection('misiones_auditoria').doc();
            batch.set(refMision, {
              'sku': data['sku'],
              'descripcion': data['descripcion'] ?? 'ND',
              'ubicacion': data['ubicacion'] ?? 'ND',
              'cantidad': data['cantidad'],
              'fechaCaducidad': data['fechaCaducidad'],
              'nombreProveedor': data['nombreProveedor'] ?? 'ND',
              'nombreGpoArticulos': data['nombreGpoArticulos'] ?? 'SIN GRUPO',
              'estado': 'pendiente',
              if (data['comentarioCorporativo'] != null) 'comentarioCorporativo': data['comentarioCorporativo'],
              'soloMermaODevolucion': true,
              'fechaGeneracion': FieldValue.serverTimestamp(),
              'mensaje': '🔥 REACTIVACIÓN 15 DÍAS: Lote en límite crítico. Proceder únicamente con Merma o Devolución',
            });
            batch.update(doc.reference, {'misionReactivada15d': true});
            misionesNuevas++;
          } else if (dias <= 45 && dias > 15 && data['misionGenerada45d'] != true) {
            var refMision = refTienda.collection('misiones_auditoria').doc();
            batch.set(refMision, {
              'sku': data['sku'],
              'descripcion': data['descripcion'] ?? 'ND',
              'ubicacion': data['ubicacion'] ?? 'ND',
              'cantidad': data['cantidad'],
              'fechaCaducidad': data['fechaCaducidad'],
              'nombreProveedor': data['nombreProveedor'] ?? 'ND',
              'nombreGpoArticulos': data['nombreGpoArticulos'] ?? 'SIN GRUPO',
              'estado': 'pendiente',
              if (data['comentarioCorporativo'] != null) 'comentarioCorporativo': data['comentarioCorporativo'],
              'fechaGeneracion': FieldValue.serverTimestamp(),
              'mensaje': 'Verificar lote próximo a vencer (45 días)',
            });
            batch.update(doc.reference, {'misionGenerada45d': true});
            misionesNuevas++;
          }

          if (ubicacion.contains('BODEGA') && dias <= 90 && dias > 0 && data['misionBodega90d'] != true) {
            var refMision = refTienda.collection('misiones_auditoria').doc();
            batch.set(refMision, {
              'sku': data['sku'],
              'descripcion': data['descripcion'] ?? 'ND',
              'ubicacion': data['ubicacion'] ?? 'ND',
              'cantidad': data['cantidad'],
              'fechaCaducidad': data['fechaCaducidad'],
              'nombreProveedor': data['nombreProveedor'] ?? 'ND',
              'nombreGpoArticulos': data['nombreGpoArticulos'] ?? 'SIN GRUPO',
              'estado': 'pendiente',
              if (data['comentarioCorporativo'] != null) 'comentarioCorporativo': data['comentarioCorporativo'],
              'fechaGeneracion': FieldValue.serverTimestamp(),
              'mensaje': '🚨 POLÍTICA 90 DÍAS: Extraer de Bodega y reubicar en Piso/Display',
            });
            batch.update(doc.reference, {'misionBodega90d': true});
            misionesBodegaNuevas++;
          }
        }
      }

      if (misionesNuevas > 0 || misionesBodegaNuevas > 0 || lotesCarritoOlvidados > 0) {
        await batch.commit();
      }

      bool mostrarAlerta = widget.esJefe
          ? (caducados > 0 || criticos > 0 || misionesNuevas > 0 || misionesBodegaNuevas > 0 || lotesCarritoActivos > 0)
          : (lotesCarritoOlvidados > 0 || lotesCarritoActivos > 0);

      if (mostrarAlerta && mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.redAccent, width: 2)),
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 30),
                const SizedBox(width: 10),
                Expanded(child: Text('Hola, ${widget.nombreUsuario}', style: const TextStyle(color: Colors.white, fontSize: 17))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Resumen operativo (${widget.nombreTienda}):', style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 14),
                if (lotesCarritoOlvidados > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      '🚨 ¡ALERTA! $lotesCarritoOlvidados lotes quedaron OLVIDADOS en el CARRITO TEMPORAL desde ayer.',
                      style: const TextStyle(color: Colors.deepOrangeAccent, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  )
                else if (lotesCarritoActivos > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      '🛒 Hay $lotesCarritoActivos lotes pendientes por acomodar en el Carrito Temporal.',
                      style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                if (caducados > 0)
                  Text('• $caducados lotes CADUCADOS', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 15)),
                if (criticos > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $criticos lotes en CRÍTICO (< 15 días)', style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                if (misionesBodegaNuevas > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('• $misionesBodegaNuevas lotes violan Política de Bodega (90 días)', style: const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                if (misionesNuevas > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• Se generaron $misionesNuevas misiones automáticas (45 días).', style: const TextStyle(color: Colors.blueAccent, fontSize: 12)),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ENTENDIDO', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint("Error en alertas: $e");
    }
  }

  void _navegarASabanaConFiltro(String filtroRiesgo) {
    setState(() => _indiceActual = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dashboardKey.currentState?.aplicarFiltroEspecial(filtroRiesgo);
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> pantallas = [
      PantallaEscaner(estaActiva: _indiceActual == 0, usuarioRegistra: widget.nombreUsuario, idTiendaGlobal: widget.idTiendaGlobal),
      PantallaDashboard(key: _dashboardKey, usuarioActual: widget.nombreUsuario, idTiendaGlobal: widget.idTiendaGlobal),
      PantallaMisiones(idTiendaGlobal: widget.idTiendaGlobal, usuarioActual: widget.nombreUsuario),
    ];
    List<BottomNavigationBarItem> items = [
      const BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Escáner'),
      const BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Sábana'),
      const BottomNavigationBarItem(icon: Icon(Icons.assignment_late), label: 'Misiones'),
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
        toolbarHeight: 30,
        backgroundColor: Colors.blueAccent.shade700,
        title: Text(
          'TIENDA: ${widget.nombreTienda.toUpperCase()} (${widget.idTiendaGlobal})',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.white),
        ),
      ),
      body: pantallas[_indiceActual],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 10,
        unselectedFontSize: 9,
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
