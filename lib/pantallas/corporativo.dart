import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../modelos/selector_jerarquico_ubicacion.dart';

class PantallaCorporativo extends StatefulWidget {
  final String idTiendaGlobal;
  final String nombreUsuario;
  final String rolUsuario;
  const PantallaCorporativo({
    super.key,
    required this.idTiendaGlobal,
    this.nombreUsuario = 'Administrador',
    this.rolUsuario = 'JEFE',
  });
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

  @override
  void initState() {
    super.initState();
    JerarquiaUbicacionHelper.precargarCacheUpc();
  }

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

  // IA 2: MODAL AUTO-RECOMENDADOR DE INSTRUCCIONES CORPORATIVAS
  void _abrirAutoRecomendadorIA(List<QueryDocumentSnapshot> docsEnRiesgo) {
    List<QueryDocumentSnapshot> objetivos = _seleccionados.isNotEmpty
        ? docsEnRiesgo.where((d) => _seleccionados.contains(d.id)).toList()
        : docsEnRiesgo.where((d) => (d.data() as Map<String, dynamic>)['comentarioCorporativo'] == null).toList();

    if (objetivos.isEmpty) {
      objetivos = docsEnRiesgo;
    }

    Map<String, Map<String, String>> propuestasPorDocId = {};
    for (var doc in objetivos) {
      var d = doc.data() as Map<String, dynamic>;
      propuestasPorDocId[doc.id] = JerarquiaUbicacionHelper.recomendarInstruccionCorporativaIA(d);
    }

    bool aplicando = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.pinkAccent, width: 2)),
            title: const Row(
              children: [
                Icon(Icons.psychology, color: Colors.pinkAccent, size: 24),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '🧠 Auto-Recomendador IA Corporativo',
                    style: TextStyle(color: Colors.pinkAccent, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 400,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'La IA analizó ${objetivos.length} lote(s) según su departamento, días restantes y cantidad:',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: objetivos.length,
                      itemBuilder: (c, idx) {
                        var doc = objetivos[idx];
                        var d = doc.data() as Map<String, dynamic>;
                        var prop = propuestasPorDocId[doc.id]!;
                        return Card(
                          color: Colors.white10,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              d['descripcion'] ?? d['sku'],
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SKU: ${d['sku']} • UPC: ${JerarquiaUbicacionHelper.obtenerUpcVisual(d)}',
                                  style: const TextStyle(fontSize: 10, color: Colors.cyanAccent),
                                ),
                                Text(
                                  '🎯 Criterio IA: ${prop['razon']}',
                                  style: const TextStyle(fontSize: 10, color: Colors.amberAccent, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '🏢 Asignar: ${prop['comentario']}',
                                  style: const TextStyle(fontSize: 11, color: Colors.greenAccent, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: aplicando ? null : () => Navigator.pop(ctx),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent, foregroundColor: Colors.white),
                icon: aplicando
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text('APLICAR A ${objetivos.length} LOTE(S)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                onPressed: aplicando
                    ? null
                    : () async {
                        setModalState(() => aplicando = true);
                        var refTienda = FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal);
                        var batch = FirebaseFirestore.instance.batch();
                        String etiquetaAutor = '${widget.rolUsuario.toUpperCase()} - ${widget.nombreUsuario.toUpperCase()} (IA)';

                        Map<String, String> comentarioPorSku = {};
                        for (var doc in objetivos) {
                          var d = doc.data() as Map<String, dynamic>;
                          String com = propuestasPorDocId[doc.id]!['comentario']!;
                          if (d['sku'] != null) comentarioPorSku[d['sku'].toString()] = com;
                          batch.update(refTienda.collection('inventario_activo').doc(doc.id), {
                            'comentarioCorporativo': com,
                            'autorComentarioCorp': etiquetaAutor,
                          });
                        }

                        if (comentarioPorSku.isNotEmpty) {
                          var misionesSnap = await refTienda.collection('misiones_auditoria').where('estado', isEqualTo: 'pendiente').get();
                          for (var mDoc in misionesSnap.docs) {
                            String mSku = (mDoc.data()['sku'] ?? '').toString();
                            if (comentarioPorSku.containsKey(mSku)) {
                              batch.update(mDoc.reference, {
                                'comentarioCorporativo': comentarioPorSku[mSku],
                                'autorComentarioCorp': etiquetaAutor,
                              });
                            }
                          }
                        }

                        await batch.commit();
                        if (mounted) {
                          setState(() => _seleccionados.clear());
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('🧠 IA asignó instrucciones a ${objetivos.length} lotes y sincronizó con Misiones.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
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
                              String etiquetaAutor = '${widget.rolUsuario.toUpperCase()} - ${widget.nombreUsuario.toUpperCase()}';
                              batch.update(refTienda.collection('inventario_activo').doc(doc.id), {
                                'comentarioCorporativo': comentario,
                                'autorComentarioCorp': etiquetaAutor,
                              });
                            }
                          }

                          if (skusSeleccionados.isNotEmpty) {
                            var misionesSnap = await refTienda.collection('misiones_auditoria').where('estado', isEqualTo: 'pendiente').get();
                            for (var mDoc in misionesSnap.docs) {
                              var mData = mDoc.data();
                              if (skusSeleccionados.contains((mData['sku'] ?? '').toString())) {
                                batch.update(mDoc.reference, {
                                  'comentarioCorporativo': comentario,
                                  'autorComentarioCorp': '${widget.rolUsuario.toUpperCase()} - ${widget.nombreUsuario.toUpperCase()}',
                                });
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
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('inventario_activo').snapshots(),
      builder: (context, snapshot) {
        var docsFiltrados = <QueryDocumentSnapshot>[];
        if (snapshot.hasData) {
          docsFiltrados = snapshot.data!.docs.where((doc) {
            var d = doc.data() as Map<String, dynamic>;
            if (d['fechaCaducidad'] == null) return false;
            DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
            int dias = cad.difference(DateTime.now()).inDays;
            return dias <= 45;
          }).toList();
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Acciones Corporativas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            actions: [
              if (docsFiltrados.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pinkAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    icon: const Icon(Icons.psychology, size: 16),
                    label: const Text('AUTO-ASIGNAR IA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                    onPressed: () => _abrirAutoRecomendadorIA(docsFiltrados),
                  ),
                ),
              if (_provExpandidos.isNotEmpty || _grupoExpandidos.isNotEmpty)
                TextButton.icon(
                  onPressed: _contraerTodo,
                  icon: const Icon(Icons.unfold_less, color: Colors.amber, size: 18),
                  label: const Text('CONTRAER', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
            ],
          ),
          body: !snapshot.hasData
              ? const Center(child: CircularProgressIndicator(color: Colors.pinkAccent))
              : docsFiltrados.isEmpty
                  ? const Center(
                      child: Text('No hay mercancía en riesgo en este momento.', style: TextStyle(color: Colors.greenAccent, fontSize: 18)),
                    )
                  : Builder(
                      builder: (context) {
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
                                            var sugerenciaIA = JerarquiaUbicacionHelper.recomendarInstruccionCorporativaIA(d);

                                            return ListTile(
                                              contentPadding: const EdgeInsets.only(left: 56, right: 16),
                                              leading: Checkbox(
                                                value: isSelected,
                                                activeColor: Colors.pinkAccent,
                                                onChanged: (v) => _toggleDocs([doc], isSelected),
                                              ),
                                              title: Text(d['descripcion'] ?? d['sku'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                              subtitle: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('SKU: ${d['sku'] ?? 'ND'}', style: const TextStyle(fontSize: 10, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                                                  Text('UPC: ${JerarquiaUbicacionHelper.obtenerUpcVisual(d)}', style: const TextStyle(fontSize: 10, color: Colors.cyanAccent, fontWeight: FontWeight.w600)),
                                                  Text('${d['cantidad']} pzas • Vence en $dias días • ${d['ubicacion'] ?? 'ND'}', style: const TextStyle(fontSize: 10, color: Colors.amber)),
                                                  if (d['comentarioCorporativo'] != null)
                                                    Text(
                                                      '🏢 INSTRUCCIÓN (${d['autorComentarioCorp'] ?? 'CORPORATIVO'}): ${d['comentarioCorporativo']}',
                                                      style: const TextStyle(fontSize: 10, color: Colors.pinkAccent, fontWeight: FontWeight.bold),
                                                    )
                                                  else
                                                    Text(
                                                      '🧠 Sugerencia IA: ${sugerenciaIA['comentario']}',
                                                      style: const TextStyle(fontSize: 10, color: Colors.white54, fontStyle: FontStyle.italic),
                                                    ),
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
      },
    );
  }
}
