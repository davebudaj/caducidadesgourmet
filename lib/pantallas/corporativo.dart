import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PantallaCorporativo extends StatefulWidget {
  final String idTiendaGlobal;
  const PantallaCorporativo({super.key, required this.idTiendaGlobal});
  @override
  State<PantallaCorporativo> createState() => _PantallaCorporativoState();
}

class _PantallaCorporativoState extends State<PantallaCorporativo> {
  final Set<String> _seleccionados = {};
  final Set<String> _provExpandidos = {};
  final Set<String> _grupoExpandidos = {};
  int _collapseVersion = 0;

  final List<String> _comentariosPredefinidos = [
    "15 DÍAS ANTES DE CADUCAR, PONER EL 50% DE DESCUENTO; SI NO SE VENDE, SE DA DE BAJA",
    "DEVOLUCIÓN A PROVEEDOR VÍA CEDIS",
    "PRODUCTO DE TEMPORADA, APLICAR EL 40% DE DESCUENTO",
    "PRODUCTO DE TEMPORADA, APLICAR EL 50% DE DESCUENTO",
    "PRODUCTO DE TEMPORADA, APLICAR EL 60% DE DESCUENTO",
    "PRODUCTO DE TEMPORADA, APLICAR EL 70% DE DESCUENTO",
    "PRODUCTO DE TEMPORADA, APLICAR EL 80% DE DESCUENTO",
    "PRODUCTO DE TEMPORADA, APLICAR EL 90% DE DESCUENTO",
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
    "MANDAR EVIDENCIA FOTOGRÁFICA"
  ];

  bool? _estadoCheck(List<QueryDocumentSnapshot> docs) {
    int count = docs.where((d) => _seleccionados.contains(d.id)).length;
    if (count == 0) return false;
    if (count == docs.length) return true;
    return null;
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

  void _contraerTodo() {
    setState(() {
      _provExpandidos.clear();
      _grupoExpandidos.clear();
      _collapseVersion++;
    });
  }

  void _mostrarOpcionesComentarios(List<QueryDocumentSnapshot> docsFiltrados) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('ASIGNAR INSTRUCCIÓN', style: TextStyle(color: Colors.pinkAccent, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                ),
                const Divider(color: Colors.white24, height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _comentariosPredefinidos.length,
                    itemBuilder: (context, index) {
                      String comentario = _comentariosPredefinidos[index];
                      bool esTop8 = index < 8;
                      return ListTile(
                        leading: Icon(Icons.arrow_right, color: esTop8 ? Colors.amber : Colors.pinkAccent),
                        title: Text(
                          comentario,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: esTop8 ? Colors.white : Colors.white70,
                          ),
                        ),
                        onTap: () async {
                          int total = _seleccionados.length;
                          var refTienda = FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal);
                          var batch = FirebaseFirestore.instance.batch();

                          Set<String> skusSeleccionados = {};
                          for (var doc in docsFiltrados) {
                            if (_seleccionados.contains(doc.id)) {
                              var data = doc.data() as Map<String, dynamic>;
                              if (data['sku'] != null) skusSeleccionados.add(data['sku'].toString());
                              batch.update(refTienda.collection('inventario_activo').doc(doc.id), {
                                'comentarioCorporativo': comentario,
                              });
                            }
                          }

                          // Conectar con Misiones de Auditoría activas para que los colaboradores vean la instrucción
                          if (skusSeleccionados.isNotEmpty) {
                            var misionesSnap = await refTienda.collection('misiones_auditoria').where('estado', isEqualTo: 'pendiente').get();
                            for (var mDoc in misionesSnap.docs) {
                              var mData = mDoc.data();
                              if (skusSeleccionados.contains((mData['sku'] ?? '').toString())) {
                                batch.update(mDoc.reference, {'comentarioCorporativo': comentario});
                              }
                            }
                          }

                          await batch.commit();
                          if (mounted) {
                            setState(() => _seleccionados.clear());
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Instrucción asignada a $total lotes y sincronizada con Misiones.'), backgroundColor: Colors.green),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Acciones Corporativas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          if (_provExpandidos.isNotEmpty || _grupoExpandidos.isNotEmpty)
            TextButton.icon(
              onPressed: _contraerTodo,
              icon: const Icon(Icons.unfold_less, color: Colors.amber, size: 18),
              label: const Text('CONTRAER TODO', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('inventario_activo').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.pinkAccent));
          if (!snapshot.hasData) return const Center(child: Text('Sin datos.'));

          var docsFiltrados = snapshot.data!.docs.where((doc) {
            var d = doc.data() as Map<String, dynamic>;
            if (d['fechaCaducidad'] == null) return false;
            DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
            int dias = cad.difference(DateTime.now()).inDays;
            return dias <= 45;
          }).toList();

          if (docsFiltrados.isEmpty) {
            return const Center(
              child: Text('No hay mercancía en riesgo en este momento.', style: TextStyle(color: Colors.greenAccent, fontSize: 18)),
            );
          }

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

          return Stack(
            children: [
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 85),
                  itemCount: proveedoresOrdenados.length,
                  itemBuilder: (context, i) {
                    String prov = proveedoresOrdenados[i];
                    var grupos = agrupado[prov]!;
                    List<QueryDocumentSnapshot> docsProv = grupos.values.expand((x) => x).toList();
                    bool? provState = _estadoCheck(docsProv);
                    bool provAbierto = _provExpandidos.contains(prov);

                    return Card(
                      color: Colors.white10,
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ExpansionTile(
                        key: PageStorageKey('prov_${_collapseVersion}_$prov'),
                        initiallyExpanded: provAbierto,
                        onExpansionChanged: (abierto) {
                          setState(() {
                            if (abierto) {
                              _provExpandidos.add(prov);
                            } else {
                              _provExpandidos.remove(prov);
                            }
                          });
                        },
                        leading: Checkbox(
                          tristate: true,
                          value: provState,
                          activeColor: Colors.pinkAccent,
                          onChanged: (v) => _toggleDocs(docsProv, provState),
                        ),
                        title: Text(prov, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text('${docsProv.length} lotes en riesgo', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        children: grupos.keys.toList().map((gpo) {
                          List<QueryDocumentSnapshot> docsGpo = grupos[gpo]!;
                          bool? gpoState = _estadoCheck(docsGpo);
                          String gpoKey = '${prov}__$gpo';
                          bool gpoAbierto = _grupoExpandidos.contains(gpoKey);

                          return ExpansionTile(
                            key: PageStorageKey('gpo_${_collapseVersion}_$gpoKey'),
                            initiallyExpanded: gpoAbierto,
                            onExpansionChanged: (abierto) {
                              setState(() {
                                if (abierto) {
                                  _grupoExpandidos.add(gpoKey);
                                } else {
                                  _grupoExpandidos.remove(gpoKey);
                                }
                              });
                            },
                            leading: Checkbox(
                              tristate: true,
                              value: gpoState,
                              activeColor: Colors.pinkAccent,
                              onChanged: (v) => _toggleDocs(docsGpo, gpoState),
                            ),
                            title: Text(gpo, style: const TextStyle(color: Colors.blueAccent, fontSize: 13)),
                            children: docsGpo.map((doc) {
                              var d = doc.data() as Map<String, dynamic>;
                              bool isSelected = _seleccionados.contains(doc.id);
                              DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
                              int dias = cad.difference(DateTime.now()).inDays;

                              return ListTile(
                                contentPadding: const EdgeInsets.only(left: 72, right: 16),
                                leading: Checkbox(
                                  value: isSelected,
                                  activeColor: Colors.pinkAccent,
                                  onChanged: (v) => _toggleDocs([doc], isSelected),
                                ),
                                title: Text(d['descripcion'] ?? d['sku'], style: const TextStyle(fontSize: 12)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${d['cantidad']} pzas • Vence en $dias días • ${d['ubicacion'] ?? 'ND'}', style: const TextStyle(fontSize: 10, color: Colors.amber)),
                                    if (d['comentarioCorporativo'] != null)
                                      Text('INSTRUCCIÓN: ${d['comentarioCorporativo']}', style: const TextStyle(fontSize: 10, color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
                                    if (d['instruccionCorpEjecutada'] == true)
                                      Text('✅ EJECUTADA POR: ${d['ejecutadaPorCorp'] ?? 'Piso'} (${d['motivoEjecucionCorp'] ?? 'OK'})', style: const TextStyle(fontSize: 10, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
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
              ),
              if (_seleccionados.isNotEmpty)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.extended(
                    backgroundColor: Colors.pinkAccent,
                    icon: const Icon(Icons.send, color: Colors.white),
                    label: Text('APLICAR A ${_seleccionados.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () => _mostrarOpcionesComentarios(docsFiltrados),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
