import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PantallaCorporativo extends StatefulWidget {
  const PantallaCorporativo({super.key});
  @override
  State<PantallaCorporativo> createState() => _PantallaCorporativoState();
}

class _PantallaCorporativoState extends State<PantallaCorporativo> {
  final Set<String> _seleccionados = {};

  final List<String> _comentariosPredefinidos = [
    "15 DÍAS ANTES DE CADUCAR, PONER 50% DE DESCUENTO; SI NO SE VENDE, SE DA DE BAJA",
    "DEVOLUCIÓN A PROVEEDOR VÍA CEDIS",
    "GESTIONAR CAMBIO FÍSICO CON PROVEEDOR. EN CASO DE NO OBTENER RESPUESTA, DESTRUCCIÓN CON EVIDENCIA POR CORREO AL PROVEEDOR Y EQUIPO COMERCIAL",
    "REVISAR CON EQUIPO DE VINOS Y LICORES",
    "MANDAR EVIDENCIA POR CORREO",
    "REVISAR CON EQUIPO DE DULCERÍA",
    "SKU INEXISTENTE",
    "REVISAR CON EQUIPO COMERCIAL DE DULCERÍA",
    "REVISAR CON EQUIPO COMERCIAL DE VINOS Y LICORES",
    "MERMAR YA QUE NO SE COMPARTIÓ EN LAS FECHAS CORRECTAS",
    "SE REVISA EN EL SIGUIENTE MES",
    "REVISAR CON PROVEEDOR SI PROCEDE CAMBIO FÍSICO O DEVOLUCIÓN CON DESTRUCCIÓN",
    "PRODUCTO DE TEMPORADA, APLICAR DESCUENTO DEL 50%",
    "MANDAR EVIDENCIA FOTOGRÁFICA",
    "PRODUCTO DE TEMPORADA, APLICAR EL 50% DE DESCUENTO"
  ];

  bool? _estadoCheck(List<QueryDocumentSnapshot> docs) {
    int count = docs.where((d) => _seleccionados.contains(d.id)).length;
    if (count == 0) return false;
    if (count == docs.length) return true;
    return null; // Tristate (algunos seleccionados)
  }

  void _toggleDocs(List<QueryDocumentSnapshot> docs, bool? estadoActual) {
    setState(() {
      if (estadoActual == true) {
        _seleccionados.removeAll(docs.map((d) => d.id));
      } else {
        _seleccionados.addAll(docs.map((d) => d.id));
      }
    });
  }

  void _mostrarOpcionesComentarios() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.9, expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('ASIGNAR INSTRUCCIÓN', style: TextStyle(color: Colors.pinkAccent, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                ),
                const Divider(color: Colors.white24),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _comentariosPredefinidos.length,
                    itemBuilder: (context, index) {
                      String comentario = _comentariosPredefinidos[index];
                      return ListTile(
                        leading: const Icon(Icons.arrow_right, color: Colors.pinkAccent),
                        title: Text(comentario, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
                        onTap: () async {
                          int total = _seleccionados.length;
                          var batch = FirebaseFirestore.instance.batch();
                          for (String id in _seleccionados) {
                            batch.update(FirebaseFirestore.instance.collection('inventario_activo').doc(id), {
                              'comentarioCorporativo': comentario
                            });
                          }
                          await batch.commit();
                          if (mounted) {
                            setState(() => _seleccionados.clear());
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Instrucción asignada a $total lotes.'), backgroundColor: Colors.green));
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acciones Corporativas', style: TextStyle(fontWeight: FontWeight.bold))),
      floatingActionButton: _seleccionados.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: Colors.pinkAccent,
              icon: const Icon(Icons.send, color: Colors.white),
              label: Text('APLICAR A ${_seleccionados.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: _mostrarOpcionesComentarios,
            )
          : null,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('inventario_activo').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.pinkAccent));
          if (!snapshot.hasData) return const Center(child: Text('Sin datos.'));

          // Filtrar solo mercancía próxima a caducar (<= 45 días)
          var docsFiltrados = snapshot.data!.docs.where((doc) {
            var d = doc.data() as Map<String, dynamic>;
            if (d['fechaCaducidad'] == null) return false;
            DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
            int dias = cad.difference(DateTime.now()).inDays;
            return dias <= 45; 
          }).toList();

          if (docsFiltrados.isEmpty) return const Center(child: Text('No hay mercancía en riesgo en este momento.', style: TextStyle(color: Colors.greenAccent, fontSize: 18)));

          // Agrupar: Proveedor -> Grupo -> Items
          Map<String, Map<String, List<QueryDocumentSnapshot>>> agrupado = {};
          for (var doc in docsFiltrados) {
            var d = doc.data() as Map<String, dynamic>;
            String prov = d['nombreProveedor'] ?? 'ND';
            String grupo = d['nombreGpoArticulos'] ?? 'SIN GRUPO';
            agrupado.putIfAbsent(prov, () => {});
            agrupado[prov]!.putIfAbsent(grupo, () => []);
            agrupado[prov]![grupo]!.add(doc);
          }

          var proveedoresOrdenados = agrupado.keys.toList()..sort();

          return Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: proveedoresOrdenados.length,
              itemBuilder: (context, i) {
                String prov = proveedoresOrdenados[i];
                var grupos = agrupado[prov]!;
                List<QueryDocumentSnapshot> docsProv = grupos.values.expand((x) => x).toList();
                bool? provState = _estadoCheck(docsProv);

                return Card(
                  color: Colors.white10,
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ExpansionTile(
                    initiallyExpanded: false,
                    leading: Checkbox(tristate: true, value: provState, activeColor: Colors.pinkAccent, onChanged: (v) => _toggleDocs(docsProv, provState)),
                    title: Text(prov, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text('${docsProv.length} lotes en riesgo', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    children: grupos.keys.toList().map((gpo) {
                      List<QueryDocumentSnapshot> docsGpo = grupos[gpo]!;
                      bool? gpoState = _estadoCheck(docsGpo);

                      return ExpansionTile(
                        leading: Checkbox(tristate: true, value: gpoState, activeColor: Colors.pinkAccent, onChanged: (v) => _toggleDocs(docsGpo, gpoState)),
                        title: Text(gpo, style: const TextStyle(color: Colors.blueAccent, fontSize: 13)),
                        children: docsGpo.map((doc) {
                          var d = doc.data() as Map<String, dynamic>;
                          bool isSelected = _seleccionados.contains(doc.id);
                          DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
                          int dias = cad.difference(DateTime.now()).inDays;
                          
                          return ListTile(
                            contentPadding: const EdgeInsets.only(left: 72, right: 16),
                            leading: Checkbox(value: isSelected, activeColor: Colors.pinkAccent, onChanged: (v) => _toggleDocs([doc], isSelected)),
                            title: Text(d['descripcion'] ?? d['sku'], style: const TextStyle(fontSize: 12)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${d['cantidad']} pzas • Vence en $dias días', style: const TextStyle(fontSize: 10, color: Colors.amber)),
                                if (d['comentarioCorporativo'] != null) Text(d['comentarioCorporativo'], style: const TextStyle(fontSize: 9, color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
