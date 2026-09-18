import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PantallaMisiones extends StatelessWidget {
  const PantallaMisiones({super.key});

  int _getPriority(Map<String, dynamic> m) {
    if (m['mensaje'] != null && m['mensaje'].toString().contains('90 DÍAS')) return 1;
    if (m['mensaje'] != null && m['mensaje'].toString().contains('45 días')) return 2;
    if (m['descontado'] != null) return 3;
    return 4;
  }

  Widget _buildHeader(int priority) {
    if (priority == 1) return Container(padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12), color: Colors.pinkAccent, width: double.infinity, child: const Text('🚨 URGENTE: POLÍTICA BODEGA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)));
    if (priority == 2) return Container(padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12), color: Colors.orangeAccent, width: double.infinity, child: const Text('⚠️ ALERTA: CADUCIDAD CERCANA', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)));
    if (priority == 3) return Container(padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12), color: Colors.blueAccent, width: double.infinity, child: const Text('🛒 OPERACIÓN: DESCONTAR VENTA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)));
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Misiones de Auditoría', style: TextStyle(fontWeight: FontWeight.bold))),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('misiones_auditoria').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.amber));
          if (!snapshot.hasData) return const Center(child: Text('Sin misiones pendientes.'));
          
          var misionesPendientes = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            return data['estado'] == 'pendiente';
          }).toList();

          if (misionesPendientes.isEmpty) {
            return const Center(child: Text('¡Piso Limpio!\nSin misiones pendientes.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.greenAccent), textAlign: TextAlign.center));
          }

          // ORDENAR POR PRIORIDAD Y LUEGO POR FECHA
          misionesPendientes.sort((a, b) {
            var dataA = a.data() as Map<String, dynamic>;
            var dataB = b.data() as Map<String, dynamic>;
            int pA = _getPriority(dataA);
            int pB = _getPriority(dataB);
            if (pA != pB) return pA.compareTo(pB);
            Timestamp tA = dataA['fechaGeneracion'] ?? Timestamp.now();
            Timestamp tB = dataB['fechaGeneracion'] ?? Timestamp.now();
            return tB.compareTo(tA); // Las actualizadas recientemente salen primero
          });

          return ListView.builder(
            itemCount: misionesPendientes.length,
            itemBuilder: (context, i) {
              var m = misionesPendientes[i].data() as Map<String, dynamic>;
              bool esAuto = m['mensaje'] != null; 
              int prioridad = _getPriority(m);
              
              int? cantidad = m['cantidad'] ?? m['descontado'];
              DateTime? cad = (m['fechaCaducidad'] as Timestamp?)?.toDate();
              String grupo = m['nombreGpoArticulos'] ?? 'SIN GRUPO';
              String proveedor = m['nombreProveedor'] ?? 'ND';
              
              Color borderColor = Colors.white24;
              if (prioridad == 1) borderColor = Colors.pinkAccent;
              if (prioridad == 2) borderColor = Colors.orangeAccent;
              if (prioridad == 3) borderColor = Colors.blueAccent;

              return Card(
                color: Colors.white10,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: borderColor, width: 2)),
                child: Column(
                  children: [
                    _buildHeader(prioridad),
                    ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading: Icon(prioridad == 3 ? Icons.shopping_cart_checkout : Icons.assignment_late, color: borderColor, size: 30),
                      title: Text(m['descripcion'] ?? m['sku'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), 
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.category, size: 14, color: Colors.blueAccent), const SizedBox(width: 4),
                              Expanded(child: Text('Grupo: $grupo', style: const TextStyle(color: Colors.white70), overflow: TextOverflow.ellipsis)),
                            ]),
                            const SizedBox(height: 4),
                            Row(children: [
                              const Icon(Icons.local_shipping, size: 14, color: Colors.greenAccent), const SizedBox(width: 4),
                              Expanded(child: Text('Prov: $proveedor', style: const TextStyle(color: Colors.white70), overflow: TextOverflow.ellipsis)),
                            ]),
                            const SizedBox(height: 4),
                            Row(children: [
                              const Icon(Icons.location_on, size: 14, color: Colors.white54), const SizedBox(width: 4),
                              Text('Ir a: ${m['ubicacion'] ?? 'ND'}', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                            ]),
                            const SizedBox(height: 4),
                            if (cantidad != null) Row(children: [
                              const Icon(Icons.inventory, size: 14, color: Colors.white54), const SizedBox(width: 4),
                              Text(prioridad == 3 ? 'Descontar en piso: $cantidad pzas' : 'Cantidad registrada: $cantidad pzas', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                            ]),
                            const SizedBox(height: 4),
                            if (cad != null) Row(children: [
                              const Icon(Icons.calendar_today, size: 14, color: Colors.white54), const SizedBox(width: 4),
                              Text('Caducidad exacta: ${cad.day}/${cad.month}/${cad.year}', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                            ]),
                            const SizedBox(height: 6),
                            if (esAuto) Text(m['mensaje'] ?? '', style: TextStyle(color: borderColor, fontSize: 11, fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 35),
                        onPressed: () => misionesPendientes[i].reference.update({'estado': 'completada'}),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
