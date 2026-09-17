import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PantallaHistorial extends StatelessWidget {
  const PantallaHistorial({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de Tratamientos', style: TextStyle(fontWeight: FontWeight.bold))),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('historial_tratamientos').orderBy('fechaTratamiento', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.amber));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Aún no hay tratamientos registrados.'));
          
          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var d = snapshot.data!.docs[index].data() as Map<String, dynamic>;
              DateTime? fecha = (d['fechaTratamiento'] as Timestamp?)?.toDate();
              
              return Card(
                color: Colors.white10,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.history, color: Colors.blueAccent),
                  title: Text(d['descripcion'] ?? 'Sin descripción', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Retirado: ${d['cantidadTratada']} pzas • ${d['motivo']}\nUsuario: ${d['usuario']}'),
                  trailing: Text(fecha != null ? "${fecha.day}/${fecha.month}/${fecha.year}" : "", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
