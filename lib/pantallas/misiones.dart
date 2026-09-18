import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PantallaMisiones extends StatelessWidget {
  const PantallaMisiones({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Misiones de Auditoría', style: TextStyle(fontWeight: FontWeight.bold))),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('misiones_auditoria').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error de Firebase: \n' + snapshot.error.toString(), style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.amber));
          if (!snapshot.hasData) return const Center(child: Text('Todo en orden. Sin misiones pendientes.'));
          
          var misionesPendientes = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            return data['estado'] == 'pendiente';
          }).toList();

          if (misionesPendientes.isEmpty) {
            return const Center(
              child: Text('¡Piso Limpio!\nSin misiones pendientes.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.greenAccent), textAlign: TextAlign.center)
            );
          }

          return ListView.builder(
            itemCount: misionesPendientes.length,
            itemBuilder: (context, i) {
              var m = misionesPendientes[i].data() as Map<String, dynamic>;
              bool esAuto = m['mensaje'] != null; 
              
              int? cantidad = m['cantidad'] ?? m['descontado'];
              DateTime? cad = (m['fechaCaducidad'] as Timestamp?)?.toDate();
              String grupo = m['nombreGpoArticulos'] ?? 'SIN GRUPO';
              String proveedor = m['nombreProveedor'] ?? 'ND';
              
              return Card(
                color: Colors.white10,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.white24)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: Icon(esAuto ? Icons.auto_awesome : Icons.assignment_late, color: Colors.amber, size: 30),
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
                          Text('Ir a: ${m['ubicacion'] ?? 'ND'}', style: const TextStyle(color: Colors.white70)),
                        ]),
                        const SizedBox(height: 4),
                        if (cantidad != null) Row(children: [
                          const Icon(Icons.inventory, size: 14, color: Colors.white54), const SizedBox(width: 4),
                          Text(esAuto ? 'Cantidad registrada: $cantidad pzas' : 'Descontar: $cantidad pzas', style: const TextStyle(color: Colors.white70)),
                        ]),
                        const SizedBox(height: 4),
                        if (cad != null) Row(children: [
                          const Icon(Icons.calendar_today, size: 14, color: Colors.white54), const SizedBox(width: 4),
                          Text('Caducidad exacta: ${cad.day}/${cad.month}/${cad.year}', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 6),
                        if (esAuto) Text(m['mensaje'] ?? '', style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 35),
                    onPressed: () => misionesPendientes[i].reference.update({'estado': 'completada'}),
                  ),
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
