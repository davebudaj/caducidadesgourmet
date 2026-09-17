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
              bool esAuto = m['mensaje'] != null; 
              
              return Card(
                color: Colors.white10,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: Icon(esAuto ? Icons.auto_awesome : Icons.assignment_late, color: Colors.amber, size: 30),
                  title: Text(m['descripcion'] ?? m['sku'], style: const TextStyle(fontWeight: FontWeight.bold)), 
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ir a: ' + m['ubicacion'].toString()),
                      if (esAuto) Text(m['mensaje'], style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
                      if (!esAuto && m['descontado'] != null) Text('Descontar: ${m['descontado']} pzas', style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 30),
                    onPressed: () {
                       misionesPendientes[i].reference.update({'estado': 'completada'});
                    },
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
