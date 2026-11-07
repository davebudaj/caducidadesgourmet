import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:universal_html/html.dart' as html;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../modelos/etiqueta_mes.dart';
import '../modelos/selector_jerarquico_ubicacion.dart';
import 'finanzas.dart';

class PantallaDashboard extends StatefulWidget {
  final String usuarioActual;
  final String idTiendaGlobal;
  const PantallaDashboard({super.key, required this.usuarioActual, required this.idTiendaGlobal});
  @override
  State<PantallaDashboard> createState() => PantallaDashboardState();
}

class PantallaDashboardState extends State<PantallaDashboard> {
  final TextEditingController _busquedaController = TextEditingController();
  final ValueNotifier<double> _progresoScrollSabana = ValueNotifier<double>(0.0);

  String _busqueda = "";
  String? _filtroProveedor;
  String? _filtroGrupo;
  String? _filtroRiesgoEspecial;
  String? _filtroTipoUbicacion;
  String? _filtroMueble;
  int? _filtroAnio;
  int? _filtroMes;
  bool _filtroSobrestockIA = false;

  // Modo de visualización de la lista: 'caducidad' (default) o 'captura'
  String _modoVisualizacionSabana = 'caducidad';

  // Filtro de captura (Año, Mes, Días y Horas desplegables con doble toque)
  int? _filtroCapturaAnio;
  int? _filtroCapturaMes;
  Set<int> _filtroCapturaDias = {};
  Map<int, Set<String>> _filtroCapturaHorasPorDia = {};

  // Paginación de 50 en 50 para lotes próximos a 3 meses
  static const int kPasoPaginacionLotes = 50;
  static const int kDiasVentanaTresMeses = 92;
  int _limiteLotesMostrados = 50;

  static const Map<int, String> _nombresMeses = {
    1: 'Enero', 2: 'Febrero', 3: 'Marzo', 4: 'Abril',
    5: 'Mayo', 6: 'Junio', 7: 'Julio', 8: 'Agosto',
    9: 'Septiembre', 10: 'Octubre', 11: 'Noviembre', 12: 'Diciembre'
  };

  bool _modoSeleccion = false;
  bool _filtroDescuadreSAP = false;
  bool _filtrosOcultos = false;
  Set<String> _seleccionados = {};

  late Stream<QuerySnapshot> _inventarioStream;

  @override
  void dispose() {
    _busquedaController.dispose();
    _progresoScrollSabana.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    JerarquiaUbicacionHelper.precargarCacheUpc();
    _inventarioStream = FirebaseFirestore.instance
        .collection('tiendas')
        .doc(widget.idTiendaGlobal)
        .collection('inventario_activo')
        .orderBy('fechaCaducidad')
        .snapshots();
  }

  Future<String> _traducirCodigoASku(String codigo) async {
    String limpio = codigo.trim();
    if (limpio.isEmpty) return limpio;
    var d = await JerarquiaUbicacionHelper.buscarProductoMaestro(limpio);
    if (d != null && d['sku'] != null && d['sku'].toString().trim().isNotEmpty) {
      return d['sku'].toString().trim();
    }
    return limpio;
  }

  String _obtenerPrimerNombre(dynamic nombreCompleto) {
    String raw = (nombreCompleto ?? '').toString().trim();
    if (raw.isEmpty) return 'Piso';
    String primero = raw.split(RegExp(r'\s+')).first;
    return primero.toUpperCase();
  }

  String _formatearFechaCapturaLote(Map<String, dynamic> d) {
    Timestamp? ts = d['fechaCaptura'] as Timestamp?;
    String nombreCorto = _obtenerPrimerNombre(d['capturista']);
    if (ts == null) return 'Sin fecha • $nombreCorto';
    DateTime f = ts.toDate();
    String fecha = "${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}";
    String hora = "${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}";
    return "$fecha $hora • $nombreCorto";
  }

  bool get _tieneFiltroCapturaActivo =>
      _filtroCapturaAnio != null ||
      _filtroCapturaMes != null ||
      _filtroCapturaDias.isNotEmpty ||
      _filtroCapturaHorasPorDia.isNotEmpty;

  String _textoBotonFiltroCaptura() {
    if (!_tieneFiltroCapturaActivo) {
      return 'Filtro de captura: Todos';
    }
    List<String> partes = [];
    if (_filtroCapturaAnio != null) partes.add('$_filtroCapturaAnio');
    if (_filtroCapturaMes != null) partes.add(_nombresMeses[_filtroCapturaMes] ?? 'Mes $_filtroCapturaMes');
    if (_filtroCapturaDias.isNotEmpty) {
      var diasOrd = _filtroCapturaDias.toList()..sort();
      partes.add('Días: ${diasOrd.join(", ")}');
    }
    int totalHorasFiltro = 0;
    for (var hSet in _filtroCapturaHorasPorDia.values) {
      totalHorasFiltro += hSet.length;
    }
    if (totalHorasFiltro > 0) {
      partes.add('$totalHorasFiltro hr(s)');
    }
    return 'Captura: ${partes.join(" • ")}';
  }

  void _abrirSelectorDinamicoFechaCaptura(List<QueryDocumentSnapshot> todosDocs) {
    List<Map<String, dynamic>> registrosConFecha = [];
    for (var doc in todosDocs) {
      var d = doc.data() as Map<String, dynamic>;
      Timestamp? ts = d['fechaCaptura'] as Timestamp?;
      if (ts != null) {
        registrosConFecha.add({
          'fecha': ts.toDate(),
          'capturista': _obtenerPrimerNombre(d['capturista']),
          'descripcion': (d['descripcion'] ?? d['sku'] ?? '').toString(),
          'cantidad': (d['cantidad'] ?? 1) as int,
        });
      }
    }

    int anioCurso = DateTime.now().year;
    int mesCurso = DateTime.now().month;

    List<int> aniosDisp = {
      anioCurso,
      ...registrosConFecha.map((r) => (r['fecha'] as DateTime).year),
    }.toList()
      ..sort((a, b) => b.compareTo(a));

    int? tempAnio = _tieneFiltroCapturaActivo ? _filtroCapturaAnio : anioCurso;
    int? tempMes = _tieneFiltroCapturaActivo ? _filtroCapturaMes : mesCurso;
    Set<int> tempDias = Set<int>.from(_filtroCapturaDias);
    Map<int, Set<String>> tempHorasPorDia = {};
    for (var entry in _filtroCapturaHorasPorDia.entries) {
      tempHorasPorDia[entry.key] = Set<String>.from(entry.value);
    }

    Set<int> diasDesplegadosHoras = {};
    Map<int, DateTime> ultimoToqueDiaNombre = {};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          var filtradasPorAnio = registrosConFecha.where((r) {
            DateTime f = r['fecha'] as DateTime;
            return tempAnio == null || f.year == tempAnio;
          }).toList();

          List<int> mesesDisp = {
            if (tempMes != null) tempMes!,
            mesCurso,
            ...filtradasPorAnio.map((r) => (r['fecha'] as DateTime).month),
          }.toList()
            ..sort();

          var filtradasPorAnioYMes = filtradasPorAnio.where((r) {
            DateTime f = r['fecha'] as DateTime;
            return tempMes == null || f.month == tempMes;
          }).toList();

          Map<int, int> lotesPorDia = {};
          Map<int, Map<String, int>> lotesPorDiaYHora = {};
          Map<int, Map<String, Set<String>>> capturistasPorDiaYHora = {};

          for (var r in filtradasPorAnioYMes) {
            DateTime f = r['fecha'] as DateTime;
            int dia = f.day;
            String horaStr = "${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}";
            String cap = r['capturista'] as String;

            lotesPorDia[dia] = (lotesPorDia[dia] ?? 0) + 1;
            lotesPorDiaYHora.putIfAbsent(dia, () => {});
            lotesPorDiaYHora[dia]![horaStr] = (lotesPorDiaYHora[dia]![horaStr] ?? 0) + 1;

            capturistasPorDiaYHora.putIfAbsent(dia, () => {});
            capturistasPorDiaYHora[dia]!.putIfAbsent(horaStr, () => {});
            capturistasPorDiaYHora[dia]![horaStr]!.add(cap);
          }

          List<int> diasDisponibles = lotesPorDia.keys.toList()..sort();

          void alternarDespliegueHoras(int dia) {
            setModalState(() {
              if (diasDesplegadosHoras.contains(dia)) {
                diasDesplegadosHoras.remove(dia);
              } else {
                diasDesplegadosHoras.add(dia);
              }
            });
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.cyanAccent, width: 1.5)),
            title: const Text(
              'Filtrar por Fecha de Captura',
              style: TextStyle(color: Colors.cyanAccent, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: 460,
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '💡 Tip: Marca la casilla derecha para seleccionar el día, o da DOBLE TOQUE en el nombre del día para desplegar las horas en que se capturaron.',
                    style: TextStyle(color: Colors.amberAccent, fontSize: 10.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Año de Captura', style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Container(
                              height: 38,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white24)),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int?>(
                                  isExpanded: true,
                                  dropdownColor: const Color(0xFF2C2C2C),
                                  value: aniosDisp.contains(tempAnio) ? tempAnio : null,
                                  items: [
                                    const DropdownMenuItem<int?>(
                                      value: null,
                                      child: Text('Año: Todos', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                                    ),
                                    ...aniosDisp.map((a) => DropdownMenuItem<int?>(
                                          value: a,
                                          child: Text('$a', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        )),
                                  ],
                                  onChanged: (val) {
                                    setModalState(() {
                                      tempAnio = val;
                                      tempDias.clear();
                                      tempHorasPorDia.clear();
                                      diasDesplegadosHoras.clear();
                                    });
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Mes de Captura', style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Container(
                              height: 38,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white24)),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int?>(
                                  isExpanded: true,
                                  dropdownColor: const Color(0xFF2C2C2C),
                                  value: mesesDisp.contains(tempMes) ? tempMes : null,
                                  items: [
                                    const DropdownMenuItem<int?>(
                                      value: null,
                                      child: Text('Mes: Todos', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                                    ),
                                    ...mesesDisp.map((m) => DropdownMenuItem<int?>(
                                          value: m,
                                          child: Text(_nombresMeses[m] ?? 'Mes $m', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        )),
                                  ],
                                  onChanged: (val) {
                                    setModalState(() {
                                      tempMes = val;
                                      tempDias.clear();
                                      tempHorasPorDia.clear();
                                      diasDesplegadosHoras.clear();
                                    });
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Días con Capturas (Doble toque en el día = ver horas):',
                          style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Row(
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            onPressed: () => setModalState(() => tempDias.addAll(diasDisponibles)),
                            child: const Text('Todos', style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 6),
                          TextButton(
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            onPressed: () => setModalState(() {
                              tempDias.clear();
                              tempHorasPorDia.clear();
                            }),
                            child: const Text('Limpiar', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 10),
                  Expanded(
                    child: diasDisponibles.isEmpty
                        ? const Center(
                            child: Text(
                              'No hay capturas registradas en este mes. Cambia el mes arriba para ver otros días.',
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            itemCount: diasDisponibles.length,
                            itemBuilder: (c, idx) {
                              int dia = diasDisponibles[idx];
                              int cantLotes = lotesPorDia[dia] ?? 0;
                              bool marcado = tempDias.contains(dia);
                              bool horasAbiertas = diasDesplegadosHoras.contains(dia);
                              var mapaHoras = lotesPorDiaYHora[dia] ?? {};
                              var listaHoras = mapaHoras.keys.toList()..sort();
                              Set<String> horasElegidasDia = tempHorasPorDia[dia] ?? {};

                              return Card(
                                elevation: 0,
                                color: marcado ? Colors.cyanAccent.withOpacity(0.16) : Colors.white10,
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(
                                    color: horasAbiertas ? Colors.amber : (marcado ? Colors.cyanAccent : Colors.white12),
                                    width: horasAbiertas ? 1.4 : 1.0,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      child: Row(
                                        children: [
                                          // DOBLE TOQUE EXCLUSIVO EN EL NOMBRE DEL DÍA PARA DESPLEGAR HORAS
                                          Expanded(
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onDoubleTap: () => alternarDespliegueHoras(dia),
                                              onTap: () {
                                                DateTime ahora = DateTime.now();
                                                DateTime? ult = ultimoToqueDiaNombre[dia];
                                                if (ult != null && ahora.difference(ult).inMilliseconds < 420) {
                                                  ultimoToqueDiaNombre.remove(dia);
                                                  alternarDespliegueHoras(dia);
                                                } else {
                                                  ultimoToqueDiaNombre[dia] = ahora;
                                                }
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 4),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Text(
                                                          'Día ${dia.toString().padLeft(2, '0')}',
                                                          style: TextStyle(
                                                            color: marcado ? Colors.cyanAccent : Colors.white,
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 13.5,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: Colors.amber.withOpacity(0.15),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            horasAbiertas ? '▲ Ocultar horas' : 'Doble toque = ${listaHoras.length} hr(s)',
                                                            style: const TextStyle(color: Colors.amberAccent, fontSize: 9.5, fontWeight: FontWeight.bold),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '$cantLotes lote(s) capturado(s)' +
                                                          (horasElegidasDia.isNotEmpty ? ' • Filtrando ${horasElegidasDia.length} hora(s)' : ''),
                                                      style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          // CASILLA DE SELECCIÓN INDEPENDIENTE A LA DERECHA
                                          Checkbox(
                                            visualDensity: VisualDensity.compact,
                                            activeColor: Colors.cyanAccent,
                                            checkColor: Colors.black,
                                            value: marcado,
                                            onChanged: (v) {
                                              setModalState(() {
                                                if (v == true) {
                                                  tempDias.add(dia);
                                                } else {
                                                  tempDias.remove(dia);
                                                  tempHorasPorDia.remove(dia);
                                                }
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (horasAbiertas)
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.45),
                                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              '🕒 Horas de captura registradas en este día (Toca una hora si deseas filtrar solo ese horario):',
                                              style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: listaHoras.map((hStr) {
                                                int cHora = mapaHoras[hStr] ?? 0;
                                                String caps = (capturistasPorDiaYHora[dia]?[hStr] ?? {}).join('/');
                                                bool horaSel = horasElegidasDia.contains(hStr);
                                                return FilterChip(
                                                  selected: horaSel,
                                                  selectedColor: Colors.amber,
                                                  checkmarkColor: Colors.black,
                                                  backgroundColor: Colors.white10,
                                                  label: Text(
                                                    '$hStr ($cHora lotes • $caps)',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.bold,
                                                      color: horaSel ? Colors.black : Colors.white,
                                                    ),
                                                  ),
                                                  onSelected: (sel) {
                                                    setModalState(() {
                                                      var setH = tempHorasPorDia.putIfAbsent(dia, () => {});
                                                      if (sel) {
                                                        setH.add(hStr);
                                                        tempDias.add(dia);
                                                      } else {
                                                        setH.remove(hStr);
                                                        if (setH.isEmpty) tempHorasPorDia.remove(dia);
                                                      }
                                                    });
                                                  },
                                                );
                                              }).toList(),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
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
                onPressed: () {
                  setState(() {
                    _filtroCapturaAnio = null;
                    _filtroCapturaMes = null;
                    _filtroCapturaDias.clear();
                    _filtroCapturaHorasPorDia.clear();
                    _limiteLotesMostrados = kPasoPaginacionLotes;
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('LIMPIAR TODO', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white54, fontSize: 11)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
                onPressed: () {
                  setState(() {
                    _filtroCapturaAnio = tempAnio;
                    _filtroCapturaMes = tempMes;
                    _filtroCapturaDias = tempDias;
                    _filtroCapturaHorasPorDia = tempHorasPorDia;
                    _limiteLotesMostrados = kPasoPaginacionLotes;
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('APLICAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          );
        },
      ),
    );
  }

  void aplicarFiltroEspecial(String riesgo) {
    setState(() {
      _filtroRiesgoEspecial = riesgo;
      _filtroProveedor = null;
      _filtroAnio = null;
      _filtroMes = null;
      _filtroDescuadreSAP = false;
      _filtroSobrestockIA = false;
      _filtroCapturaAnio = null;
      _filtroCapturaMes = null;
      _filtroCapturaDias.clear();
      _filtroCapturaHorasPorDia.clear();
      _filtroGrupo = null;
      _limiteLotesMostrados = kPasoPaginacionLotes;
    });
  }

  void _borrarSeleccionados() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Borrar Múltiples Lotes', style: TextStyle(color: Colors.redAccent)),
        content: Text('¿Seguro que deseas eliminar ${_seleccionados.length} lote(s) de la Sábana de Riesgos?\n\nEsta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              var batch = FirebaseFirestore.instance.batch();
              for (String id in _seleccionados) {
                batch.delete(FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('inventario_activo').doc(id));
              }
              await batch.commit();
              if (!mounted) return;
              setState(() {
                _modoSeleccion = false;
                _seleccionados.clear();
              });
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lotes eliminados exitosamente'), backgroundColor: Colors.green));
            },
            child: const Text('SÍ, BORRAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _tratamientoMasivo() {
    String motivoSeleccionado = 'Merma / Destrucción';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text('Tratamiento Masivo', style: TextStyle(color: Colors.amber)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Se aplicará a ${_seleccionados.length} lote(s) en su totalidad.', style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Motivo de Salida', filled: true, fillColor: Colors.white10),
                  dropdownColor: const Color(0xFF2C2C2C),
                  value: motivoSeleccionado,
                  items: const [
                    DropdownMenuItem(value: 'Merma / Destrucción', child: Text('📉 Merma / Destrucción')),
                    DropdownMenuItem(value: 'Saldado / Promoción', child: Text('🏷️ Saldado / Promoción')),
                    DropdownMenuItem(value: 'Devolución a Proveedor', child: Text('📦 Devolución a Proveedor')),
                  ],
                  onChanged: (val) => setDialogState(() => motivoSeleccionado = val!),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                onPressed: () async {
                  Navigator.pop(ctx);
                  var batch = FirebaseFirestore.instance.batch();
                  var refTienda = FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal);

                  for (String id in _seleccionados) {
                    var docRef = refTienda.collection('inventario_activo').doc(id);
                    var docSnap = await docRef.get();
                    if (docSnap.exists) {
                      var d = docSnap.data() as Map<String, dynamic>;
                      int cant = d['cantidad'] ?? 0;
                      double precio = double.tryParse((d['precioVenta'] ?? 0).toString()) ?? 0.0;

                      var histRef = refTienda.collection('historial_tratamientos').doc();
                      batch.set(histRef, {
                        'sku': d['sku'],
                        'ean': JerarquiaUbicacionHelper.obtenerUpcVisual(d),
                        'descripcion': d['descripcion'],
                        'nombreProveedor': d['nombreProveedor'] ?? 'ND',
                        'nombreGpoArticulos': d['nombreGpoArticulos'] ?? 'SIN GRUPO',
                        'ubicacion': d['ubicacion'],
                        'cantidadTratada': cant,
                        'motivo': motivoSeleccionado,
                        'costoTotal': cant * precio,
                        'fechaTratamiento': FieldValue.serverTimestamp(),
                        'usuario': widget.usuarioActual,
                      });
                      FinanzasService.actualizarResumenEnBatch(
                        batch: batch,
                        idTiendaGlobal: widget.idTiendaGlobal,
                        motivo: motivoSeleccionado,
                        cantidad: cant,
                        monto: cant * precio,
                      );

                      if (motivoSeleccionado == 'Saldado / Promoción') {
                        batch.update(docRef, {
                          'enPromocion': true,
                          if (d['comentarioCorporativo'] != null) 'instruccionCorpEjecutada': true,
                          if (d['comentarioCorporativo'] != null) 'ejecutadaPorCorp': widget.usuarioActual,
                          if (d['comentarioCorporativo'] != null) 'motivoEjecucionCorp': motivoSeleccionado,
                          'piezasEnPromocion': cant,
                          'fechaPromocion': FieldValue.serverTimestamp(),
                        });
                      } else {
                        batch.delete(docRef);
                      }
                    }
                  }
                  await batch.commit();
                  if (!mounted) return;
                  setState(() {
                    _modoSeleccion = false;
                    _seleccionados.clear();
                  });
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tratamiento masivo aplicado exitosamente'), backgroundColor: Colors.green));
                },
                child: const Text('APLICAR', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _verDetalleCompleto(QueryDocumentSnapshot docSnap) {
    var d = docSnap.data() as Map<String, dynamic>;
    DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(d['descripcion'] ?? 'Sin Nombre', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow("MARCA", JerarquiaUbicacionHelper.obtenerMarcaVisual(d)),
              _infoRow("SKU", d['sku']),
              _infoRow("UPC", JerarquiaUbicacionHelper.obtenerUpcVisual(d)),
              _infoRow("PROVEEDOR", d['nombreProveedor']),
              _infoRow("GRUPO", d['nombreGpoArticulos']),
              _infoRow("UBICACIÓN PISO", d['ubicacion']),
              _infoRow("CANTIDAD FÍSICA", "${d['cantidad']} pzas"),
              _infoRow("PRECIO VENTA", "MXN ${d['precioVenta'] ?? 0}"),
              _infoRow("OH TEÓRICO (SAP)", "${d['oh'] ?? 'No disponible'} pzas"),
              _infoRow("CAPTURADO", _formatearFechaCapturaLote(d)),
              _infoRow("CADUCIDAD", "${cad.day.toString().padLeft(2, '0')}/${cad.month.toString().padLeft(2, '0')}/${cad.year}"),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                  icon: const Icon(Icons.handyman),
                  label: const Text('DAR TRATAMIENTO', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(context);
                    _dialogoTratamiento(docSnap);
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmarBorrado(docSnap);
            },
            child: const Text('BORRAR', style: TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _editarRegistro(docSnap);
            },
            child: const Text('EDITAR', style: TextStyle(color: Colors.blueAccent)),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CERRAR', style: TextStyle(color: Colors.white54))),
        ],
      ),
    );
  }

  void _dialogoTratamiento(QueryDocumentSnapshot docSnap) {
    var d = docSnap.data() as Map<String, dynamic>;
    int cantOriginal = d['cantidad'] ?? 0;
    DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
    int dias = cad.difference(DateTime.now()).inDays;
    bool bloquearPromocion = (d['enPromocion'] == true) || (dias <= 15);
    TextEditingController cantCtrl = TextEditingController(text: cantOriginal.toString());
    String motivoSeleccionado = 'Merma / Destrucción';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text('Tratamiento de Mercancía', style: TextStyle(color: Colors.amber)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Lote: ${d['descripcion']}', style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 15),
                  TextField(
                    controller: cantCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Piezas a retirar', filled: true, fillColor: Colors.white10),
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Motivo de Salida', filled: true, fillColor: Colors.white10),
                    dropdownColor: const Color(0xFF2C2C2C),
                    value: motivoSeleccionado,
                    items: [
                      const DropdownMenuItem(value: 'Merma / Destrucción', child: Text('📉 Merma / Destrucción')),
                      if (!bloquearPromocion)
                        const DropdownMenuItem(value: 'Saldado / Promoción', child: Text('🏷️ Saldado / Promoción')),
                      const DropdownMenuItem(value: 'Devolución a Proveedor', child: Text('📦 Devolución a Proveedor')),
                    ],
                    onChanged: (val) => setDialogState(() => motivoSeleccionado = val!),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
                  onPressed: () async {
                    int cantATratar = int.tryParse(cantCtrl.text) ?? 0;
                    if (cantATratar > 0 && cantATratar <= cantOriginal) {
                      double precio = double.tryParse((d['precioVenta'] ?? 0).toString()) ?? 0.0;

                      var batchTrat = FirebaseFirestore.instance.batch();
                      var histDoc = FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('historial_tratamientos').doc();
                      batchTrat.set(histDoc, {
                        'sku': d['sku'],
                        'ean': JerarquiaUbicacionHelper.obtenerUpcVisual(d),
                        'descripcion': d['descripcion'],
                        'nombreProveedor': d['nombreProveedor'] ?? 'ND',
                        'nombreGpoArticulos': d['nombreGpoArticulos'] ?? 'SIN GRUPO',
                        'ubicacion': d['ubicacion'],
                        'cantidadTratada': cantATratar,
                        'motivo': motivoSeleccionado,
                        'costoTotal': cantATratar * precio,
                        'fechaTratamiento': FieldValue.serverTimestamp(),
                        'usuario': widget.usuarioActual,
                      });
                      FinanzasService.actualizarResumenEnBatch(
                        batch: batchTrat,
                        idTiendaGlobal: widget.idTiendaGlobal,
                        motivo: motivoSeleccionado,
                        cantidad: cantATratar,
                        monto: cantATratar * precio,
                      );
                      await batchTrat.commit();

                      if (motivoSeleccionado == 'Saldado / Promoción') {
                        await docSnap.reference.update({
                          'enPromocion': true,
                          if (d['comentarioCorporativo'] != null) 'instruccionCorpEjecutada': true,
                          if (d['comentarioCorporativo'] != null) 'ejecutadaPorCorp': widget.usuarioActual,
                          if (d['comentarioCorporativo'] != null) 'motivoEjecucionCorp': motivoSeleccionado,
                          'piezasEnPromocion': cantATratar,
                          'fechaPromocion': FieldValue.serverTimestamp(),
                        });
                      } else if (cantATratar == cantOriginal) {
                        await docSnap.reference.delete();
                      } else {
                        await docSnap.reference.update({
                          'cantidad': cantOriginal - cantATratar,
                          if (d['comentarioCorporativo'] != null) 'instruccionCorpEjecutada': true,
                          if (d['comentarioCorporativo'] != null) 'ejecutadaPorCorp': widget.usuarioActual,
                          if (d['comentarioCorporativo'] != null) 'motivoEjecucionCorp': motivoSeleccionado,
                        });
                      }

                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tratamiento registrado en el historial.'), backgroundColor: Colors.green));
                      }
                    }
                  },
                  child: const Text('APLICAR TRATAMIENTO'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmarBorrado(QueryDocumentSnapshot docSnap) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar Registro?', style: TextStyle(color: Colors.white)),
        content: const Text('Esta acción eliminará el producto del inventario en piso. ¿Estás seguro?', style: TextStyle(color: Colors.white70)),
        backgroundColor: const Color(0xFF1E1E1E),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              docSnap.reference.delete();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro eliminado')));
            },
            child: const Text('SÍ, BORRAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _editarRegistro(QueryDocumentSnapshot docSnap) {
    var d = docSnap.data() as Map<String, dynamic>;
    String skuOriginalLote = (d['sku'] ?? '').toString().trim();
    TextEditingController cantCtrl = TextEditingController(text: d['cantidad'].toString());
    TextEditingController skuCtrl = TextEditingController(text: skuOriginalLote);
    TextEditingController eanCtrl = TextEditingController(text: JerarquiaUbicacionHelper.obtenerUpcVisual(d) == 'SIN UPC' ? '' : JerarquiaUbicacionHelper.obtenerUpcVisual(d));
    TextEditingController descCtrl = TextEditingController(text: (d['descripcion'] ?? 'Artículo Nuevo').toString());
    DateTime fechaOriginal = (d['fechaCaducidad'] as Timestamp).toDate();
    DateTime fechaEditada = fechaOriginal;

    String currentDesc = d['descripcion'] ?? 'Artículo Nuevo';
    Map<String, dynamic>? updatedMasterData;
    String? localUbi = d['ubicacion']?.toString();
    FocusNode skuFocus = FocusNode();
    bool listenerAdded = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (!listenerAdded) {
              listenerAdded = true;
              skuFocus.addListener(() async {
                if (!skuFocus.hasFocus && skuCtrl.text.isNotEmpty) {
                  setDialogState(() => currentDesc = "Buscando...");
                  try {
                    String codigoEscrito = skuCtrl.text.trim();
                    var masterDataFound = await JerarquiaUbicacionHelper.buscarProductoMaestro(codigoEscrito);
                    if (masterDataFound != null) {
                      updatedMasterData = masterDataFound;
                      if (updatedMasterData?['sku'] != null && updatedMasterData!['sku'].toString().trim().isNotEmpty) {
                        skuCtrl.text = updatedMasterData!['sku'].toString().trim();
                      }
                      if (updatedMasterData?['ean'] != null && updatedMasterData!['ean'].toString().trim().isNotEmpty) {
                        eanCtrl.text = updatedMasterData!['ean'].toString().trim();
                      }
                      String dOficial = updatedMasterData?['descripcion'] ?? 'Sin Nombre';
                      descCtrl.text = dOficial;
                      setDialogState(() => currentDesc = '✅ Match en Catálogo: $dOficial');
                    } else {
                      updatedMasterData = null;
                      setDialogState(() => currentDesc = 'ℹ️ Código no está en Catálogo Maestro (Puedes escribir su nombre abajo)');
                    }
                  } catch (e) {
                    setDialogState(() => currentDesc = 'Error al buscar');
                  }
                }
              });
            }

            String fechaTexto = "${fechaEditada.day.toString().padLeft(2, '0')}/${fechaEditada.month.toString().padLeft(2, '0')}/${fechaEditada.year}";

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text('Editar Registro', style: TextStyle(color: Colors.amber)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: skuCtrl,
                      focusNode: skuFocus,
                      decoration: const InputDecoration(labelText: 'SKU / UPC', labelStyle: TextStyle(color: Colors.amber), filled: true, fillColor: Colors.white10),
                    ),
                    const SizedBox(height: 5),
                    Align(alignment: Alignment.centerLeft, child: Text(currentDesc, style: const TextStyle(fontSize: 10, color: Colors.greenAccent))),
                    const SizedBox(height: 8),
                    TextField(
                      controller: eanCtrl,
                      decoration: const InputDecoration(labelText: 'UPC / Código de Barras (EAN)', labelStyle: TextStyle(color: Colors.cyanAccent, fontSize: 12), filled: true, fillColor: Colors.white10),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(labelText: 'Descripción / Nombre del Producto', labelStyle: TextStyle(color: Colors.amberAccent, fontSize: 12), filled: true, fillColor: Colors.white10),
                    ),
                    const Divider(color: Colors.white12),
                    TextField(
                      controller: cantCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cantidad Fija (Piezas)', labelStyle: TextStyle(color: Colors.white54)),
                    ),
                    const SizedBox(height: 15),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal).collection('ubicaciones').orderBy('nombre').snapshots(),
                      builder: (context, ubiSnapshot) {
                        if (!ubiSnapshot.hasData) return const LinearProgressIndicator();
                        List<String> todas = ubiSnapshot.data!.docs
                            .map((u) => u['nombre'].toString())
                            .where((n) => n != 'EN TRÁNSITO')
                            .toList();
                        List<String> validUbis = todas
                            .where((u) => !todas.any((otra) => otra.startsWith('$u > ')))
                            .toList();
                        if (localUbi != null && localUbi!.isNotEmpty && !validUbis.contains(localUbi)) {
                          validUbis.add(localUbi!);
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Seleccionar Mueble / Ubicación (Desplegable)",
                              style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            SelectorJerarquicoUbicacion(
                              todasLasRutas: validUbis,
                              rutaSeleccionada: localUbi,
                              permitirSeleccionParcial: false,
                              textoRaizVacio: '1. Selecciona Área (PISO / BODEGA / DISPLAY)...',
                              onRutaCambiada: (val) => setDialogState(() => localUbi = val),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    const Text('Fecha de Caducidad', style: TextStyle(color: Colors.amber, fontSize: 12)),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white10,
                          side: const BorderSide(color: Colors.amber, width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.calendar_month, color: Colors.amber),
                        label: Text(
                          fechaTexto,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                        ),
                        onPressed: () async {
                          DateTime? nuevaFecha = await showDatePicker(
                            context: context,
                            initialDate: fechaEditada,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2036),
                          );
                          if (nuevaFecha != null) {
                            setDialogState(() => fechaEditada = nuevaFecha);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  onPressed: () async {
                    int? nCant = int.tryParse(cantCtrl.text);
                    String nSku = await _traducirCodigoASku(skuCtrl.text);

                    if (localUbi == null || localUbi!.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Selecciona todos los niveles de la ubicación antes de guardar.'), backgroundColor: Colors.orange),
                      );
                      return;
                    }
                    if (nCant != null && nSku.isNotEmpty) {
                      var masterFound = await JerarquiaUbicacionHelper.buscarProductoMaestro(nSku);
                      if (masterFound == null && eanCtrl.text.trim().isNotEmpty) {
                        masterFound = await JerarquiaUbicacionHelper.buscarProductoMaestro(eanCtrl.text.trim());
                      }
                      if (masterFound != null) {
                        updatedMasterData = masterFound;
                        if (masterFound['sku'] != null && masterFound['sku'].toString().trim().isNotEmpty) {
                          nSku = masterFound['sku'].toString().trim();
                        }
                      }

                      String descFinal = (updatedMasterData != null && updatedMasterData!['descripcion'] != null)
                          ? updatedMasterData!['descripcion'].toString()
                          : descCtrl.text.trim();

                      Map<String, dynamic> updateData = {
                        'cantidad': nCant,
                        'sku': nSku,
                        'ean': eanCtrl.text.trim(),
                        'ubicacion': localUbi,
                        'descripcion': descFinal,
                        'fechaCaducidad': Timestamp.fromDate(fechaEditada),
                      };

                      if (fechaEditada.year != fechaOriginal.year ||
                          fechaEditada.month != fechaOriginal.month ||
                          fechaEditada.day != fechaOriginal.day) {
                        updateData['misionGenerada45d'] = FieldValue.delete();
                        updateData['misionBodega90d'] = FieldValue.delete();
                      }

                      await docSnap.reference.update(updateData);

                      int totalInstancias = await JerarquiaUbicacionHelper.actualizarArticuloEnTodasLasInstancias(
                        idTiendaGlobal: widget.idTiendaGlobal,
                        codigoAnterior: skuOriginalLote,
                        nuevoSku: nSku,
                        nuevoEan: eanCtrl.text.trim(),
                        nuevaDescripcion: descFinal,
                        datosMaestros: updatedMasterData,
                        usuarioActual: widget.usuarioActual,
                      );

                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✅ Registro guardado y actualizado en $totalInstancias lote(s) de la tienda.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('GUARDAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _infoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(text: "$label: ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70, fontSize: 12)),
            TextSpan(text: value.toString(), style: const TextStyle(color: Colors.amberAccent, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  void _descargarExcel(List<QueryDocumentSnapshot> docs, {String nombreArchivo = "Sabana_Filtros.csv"}) {
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay datos para descargar')));
      return;
    }

    StringBuffer csv = StringBuffer();
    csv.writeln("SKU,UPC,DESCRIPCION,PROVEEDOR,GRUPO_ARTICULOS,UBICACION,CANTIDAD,PRECIO_VENTA,OH_SAP,FECHA_CAPTURA,FECHA_CADUCIDAD,DIAS_PARA_VENCER");

    DateTime hoy = DateTime.now();

    for (var doc in docs) {
      var d = doc.data() as Map<String, dynamic>;
      DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
      int dias = cad.difference(hoy).inDays;

      String sku = (d['sku'] ?? '').toString();
      String ean = JerarquiaUbicacionHelper.obtenerUpcVisual(d);
      String desc = '"${(d['descripcion'] ?? '').toString().replaceAll('"', '""')}"';
      String prov = '"${(d['nombreProveedor'] ?? '').toString().replaceAll('"', '""')}"';
      String gpo = '"${(d['nombreGpoArticulos'] ?? '').toString().replaceAll('"', '""')}"';
      String ubi = '"${(d['ubicacion'] ?? '').toString().replaceAll('"', '""')}"';
      String cant = (d['cantidad'] ?? 0).toString();
      String precio = (d['precioVenta'] ?? 0).toString();
      String oh = (d['oh'] ?? 0).toString();
      String fCap = '"${_formatearFechaCapturaLote(d)}"';
      String fCad = "${cad.day}/${cad.month}/${cad.year}";

      csv.writeln("$sku,$ean,$desc,$prov,$gpo,$ubi,$cant,$precio,$oh,$fCap,$fCad,$dias");
    }

    final bytes = utf8.encode('\uFEFF${csv.toString()}');
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute("download", nombreArchivo)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  void _mostrarAuditorIASap(List<QueryDocumentSnapshot> todosDocs) {
    Map<String, int> fisicoPorSku = {};
    Map<String, int> pisoPorSku = {};
    Map<String, int> bodegaPorSku = {};
    Map<String, Map<String, dynamic>> muestraPorSku = {};

    for (var doc in todosDocs) {
      var d = doc.data() as Map<String, dynamic>;
      String s = (d['sku'] ?? '').toString().trim();
      if (s.isEmpty) continue;
      int c = (d['cantidad'] ?? 0) as int;
      String u = (d['ubicacion'] ?? '').toString().toUpperCase();
      if (u == 'EN TRÁNSITO') continue;

      fisicoPorSku[s] = (fisicoPorSku[s] ?? 0) + c;
      if (u.contains('BODEGA')) {
        bodegaPorSku[s] = (bodegaPorSku[s] ?? 0) + c;
      } else {
        pisoPorSku[s] = (pisoPorSku[s] ?? 0) + c;
      }
      muestraPorSku.putIfAbsent(s, () => d);
    }

    List<Map<String, dynamic>> estancadosEnBodega = [];
    List<Map<String, dynamic>> mermaFantasma = [];
    List<Map<String, dynamic>> sobrantesFisicos = [];

    for (var entry in muestraPorSku.entries) {
      String s = entry.key;
      var d = entry.value;
      int totalFis = fisicoPorSku[s] ?? 0;
      int enPiso = pisoPorSku[s] ?? 0;
      int enBod = bodegaPorSku[s] ?? 0;
      int ohSap = int.tryParse((d['oh'] ?? '').toString().split('.')[0].trim()) ?? -1;
      double precio = double.tryParse((d['precioVenta'] ?? 0).toString()) ?? 0.0;

      if (enBod > 0 && enPiso == 0) {
        estancadosEnBodega.add({
          'sku': s,
          'datos': d,
          'enBodega': enBod,
          'oh': ohSap,
          'impacto': enBod * precio,
        });
      }

      if (ohSap >= 0 && totalFis != ohSap) {
        int diff = ohSap - totalFis;
        if (diff > 0) {
          mermaFantasma.add({
            'sku': s,
            'datos': d,
            'fisico': totalFis,
            'oh': ohSap,
            'faltante': diff,
            'impacto': diff * precio,
          });
        } else {
          sobrantesFisicos.add({
            'sku': s,
            'datos': d,
            'fisico': totalFis,
            'oh': ohSap,
            'sobrante': -diff,
            'impacto': (-diff) * precio,
          });
        }
      }
    }

    estancadosEnBodega.sort((a, b) => (b['impacto'] as double).compareTo(a['impacto'] as double));
    mermaFantasma.sort((a, b) => (b['impacto'] as double).compareTo(a['impacto'] as double));
    sobrantesFisicos.sort((a, b) => (b['impacto'] as double).compareTo(a['impacto'] as double));

    int tabActiva = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          List<Map<String, dynamic>> listaActual = tabActiva == 0
              ? estancadosEnBodega
              : (tabActiva == 1 ? mermaFantasma : sobrantesFisicos);

          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.cyanAccent, width: 2)),
            title: const Row(
              children: [
                Icon(Icons.policy, color: Colors.cyanAccent, size: 24),
                SizedBox(width: 8),
                Expanded(
                  child: Text('🕵️‍♂️ Auditor IA: SAP vs Piso y Bodega', style: TextStyle(color: Colors.cyanAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 410,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: tabActiva == 0 ? Colors.pinkAccent.withOpacity(0.25) : Colors.white10,
                            side: BorderSide(color: tabActiva == 0 ? Colors.pinkAccent : Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                          onPressed: () => setModalState(() => tabActiva = 0),
                          child: Text('🚨 Bodega (${estancadosEnBodega.length})', style: TextStyle(color: tabActiva == 0 ? Colors.pinkAccent : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: tabActiva == 1 ? Colors.orangeAccent.withOpacity(0.25) : Colors.white10,
                            side: BorderSide(color: tabActiva == 1 ? Colors.orangeAccent : Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                          onPressed: () => setModalState(() => tabActiva = 1),
                          child: Text('📉 Faltante (${mermaFantasma.length})', style: TextStyle(color: tabActiva == 1 ? Colors.orangeAccent : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: tabActiva == 2 ? Colors.cyanAccent.withOpacity(0.25) : Colors.white10,
                            side: BorderSide(color: tabActiva == 2 ? Colors.cyanAccent : Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                          onPressed: () => setModalState(() => tabActiva = 2),
                          child: Text('📦 Sobrante (${sobrantesFisicos.length})', style: TextStyle(color: tabActiva == 2 ? Colors.cyanAccent : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tabActiva == 0
                        ? 'Productos guardados en BODEGA con 0 piezas exhibidas en PISO (Toca uno para filtrarlo):'
                        : (tabActiva == 1
                            ? 'Merma Fantasma: SAP reporta más piezas (OH) de las que hay mapeadas en tienda:'
                            : 'Sobrante Físico: Hay más piezas mapeadas en tienda que el OH teórico de SAP:'),
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: listaActual.isEmpty
                        ? const Center(child: Text('¡Sin hallazgos en esta categoría!', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)))
                        : ListView.builder(
                            itemCount: listaActual.length,
                            itemBuilder: (c, idx) {
                              var item = listaActual[idx];
                              var d = item['datos'] as Map<String, dynamic>;
                              String s = item['sku'].toString();
                              return Card(
                                elevation: 0,
                                color: Colors.white10,
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  dense: true,
                                  title: Text(d['descripcion'] ?? s, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('SKU: $s • UPC: ${JerarquiaUbicacionHelper.obtenerUpcVisual(d)}', style: const TextStyle(color: Colors.greenAccent, fontSize: 10)),
                                      if (tabActiva == 0)
                                        Text('📦 En Bodega: ${item['enBodega']} pzas • En Piso: 0 pzas (Ubicación: ${d['ubicacion']})', style: const TextStyle(color: Colors.pinkAccent, fontSize: 11, fontWeight: FontWeight.bold))
                                      else if (tabActiva == 1)
                                        Text('📊 SAP OH: ${item['oh']} pzas vs Físico: ${item['fisico']} pzas (Faltan ${item['faltante']} pzas • MXN ${(item['impacto'] as double).toStringAsFixed(2)})', style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold))
                                      else
                                        Text('📊 Físico: ${item['fisico']} pzas vs SAP OH: ${item['oh']} pzas (Sobran ${item['sobrante']} pzas)', style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  trailing: const Icon(Icons.search, color: Colors.amber, size: 18),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _busquedaController.text = s;
                                    setState(() {
                                      _busqueda = s.toLowerCase();
                                      _filtroAnio = null;
                                      _filtroMes = null;
                                      _limiteLotesMostrados = kPasoPaginacionLotes;
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CERRAR', style: TextStyle(color: Colors.white54))),
            ],
          );
        },
      ),
    );
  }

  void _descargarProximoMes(List<QueryDocumentSnapshot> todosLosDocs) {
    DateTime hoy = DateTime.now();
    int mesSig = hoy.month == 12 ? 1 : hoy.month + 1;
    int anioSig = hoy.month == 12 ? hoy.year + 1 : hoy.year;

    var docsProximoMes = todosLosDocs.where((doc) {
      var data = doc.data() as Map<String, dynamic>;
      Timestamp? ts = data['fechaCaducidad'];
      if (ts == null) return false;
      DateTime cad = ts.toDate();
      return cad.month == mesSig && cad.year == anioSig;
    }).toList();

    if (docsProximoMes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay caducidades registradas para el próximo mes.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent),
      );
      return;
    }

    _descargarExcel(docsProximoMes, nombreArchivo: "Caducidades_${mesSig}_$anioSig.csv");
  }

  @override
  Widget build(BuildContext context) {
    final bool esZebra = JerarquiaUbicacionHelper.esDispositivoZebra;

    return Scaffold(
      appBar: _modoSeleccion
          ? AppBar(
              backgroundColor: Colors.redAccent.shade700,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _modoSeleccion = false;
                  _seleccionados.clear();
                }),
              ),
              title: Text('${_seleccionados.length} seleccionados', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              actions: [
                IconButton(icon: const Icon(Icons.handyman), tooltip: 'Tratamiento Masivo', onPressed: _tratamientoMasivo),
                IconButton(icon: const Icon(Icons.delete_forever), tooltip: 'Borrar Lotes', onPressed: _borrarSeleccionados),
              ],
            )
          : AppBar(
              title: InkWell(
                onTap: () => setState(() => _filtrosOcultos = !_filtrosOcultos),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Sábana de Riesgo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(width: 6),
                      Icon(
                        _filtrosOcultos ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                        color: Colors.amber,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _inventarioStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.amber));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Inventario sano.'));

          var provs = snapshot.data!.docs.map((doc) => (doc.data() as Map)['nombreProveedor']?.toString() ?? 'ND').toSet().toList()..sort();
          var grupos = snapshot.data!.docs.map((doc) => (doc.data() as Map)['nombreGpoArticulos']?.toString() ?? 'ND').toSet().toList()..sort();
          Map<String, int> conteoPorUbicacion = {};
          for (var doc in snapshot.data!.docs) {
            String u = ((doc.data() as Map)['ubicacion']?.toString() ?? 'ND').trim();
            if (u.isNotEmpty && u != 'EN TRÁNSITO') {
              conteoPorUbicacion[u] = (conteoPorUbicacion[u] ?? 0) + 1;
            }
          }
          var mueblesDisponibles = JerarquiaUbicacionHelper.ordenarRutasPorJerarquia(conteoPorUbicacion.keys);

          Map<String, int> sumaFisicaPorSku = {};
          for (var doc in snapshot.data!.docs) {
            var dMap = doc.data() as Map<String, dynamic>;
            String s = (dMap['sku'] ?? '').toString();
            int c = (dMap['cantidad'] ?? 0) as int;
            if (s.isNotEmpty) {
              sumaFisicaPorSku[s] = (sumaFisicaPorSku[s] ?? 0) + c;
            }
          }

          int anioEnCurso = DateTime.now().year;
          DateTime hoy = DateTime.now();
          bool filtroAnioEnCursoActivo = !_tieneFiltroCapturaActivo && _filtroAnio == anioEnCurso && _filtroMes == null && _filtroRiesgoEspecial == null;

          var docsFiltrados = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            String prov = (data['nombreProveedor'] ?? 'ND').toString();
            String gpo = (data['nombreGpoArticulos'] ?? 'ND').toString();
            String ubi = (data['ubicacion'] ?? 'ND').toString();

            DateTime cad = (data['fechaCaducidad'] as Timestamp).toDate();
            int dias = cad.difference(hoy).inDays;

            bool coincideBusqueda = _busqueda.isEmpty || JerarquiaUbicacionHelper.evaluarConsultaLenguajeNaturalIA(_busqueda, data);
            bool coincideProv = _filtroProveedor == null || prov == _filtroProveedor;
            bool coincideGpo = _filtroGrupo == null || gpo == _filtroGrupo;

            List<String> prefijoUbi = _filtroMueble != null
                ? JerarquiaUbicacionHelper.descomponerRuta(_filtroMueble!)
                : [];
            bool coincideMueble = JerarquiaUbicacionHelper.coincideConPrefijoJerarquico(ubi, prefijoUbi);

            bool coincideSobrestock = !_filtroSobrestockIA || JerarquiaUbicacionHelper.analizarRiesgoSobrestockIA(data) != null;
            bool coincideDescuadre = true;
            if (_filtroDescuadreSAP) {
              String skuRaw = (data['sku'] ?? '').toString();
              int totalFisico = sumaFisicaPorSku[skuRaw] ?? 0;
              int ohSap = int.tryParse((data['oh'] ?? '').toString().split('.')[0].trim()) ?? -1;
              coincideDescuadre = (ohSap >= 0 && totalFisico != ohSap);
            }

            // Si el Filtro de Captura está activo o el Modo de Visualización es por Fecha de Captura
            if (_tieneFiltroCapturaActivo || _modoVisualizacionSabana == 'captura') {
              Timestamp? tsCap = data['fechaCaptura'] as Timestamp?;
              if (_tieneFiltroCapturaActivo) {
                if (tsCap == null) return false;
                DateTime fCap = tsCap.toDate();
                if (_filtroCapturaAnio != null && fCap.year != _filtroCapturaAnio) return false;
                if (_filtroCapturaMes != null && fCap.month != _filtroCapturaMes) return false;
                if (_filtroCapturaDias.isNotEmpty && !_filtroCapturaDias.contains(fCap.day)) return false;
                if (_filtroCapturaHorasPorDia.containsKey(fCap.day) && _filtroCapturaHorasPorDia[fCap.day]!.isNotEmpty) {
                  String hDoc = "${fCap.hour.toString().padLeft(2, '0')}:${fCap.minute.toString().padLeft(2, '0')}";
                  if (!_filtroCapturaHorasPorDia[fCap.day]!.contains(hDoc)) return false;
                }
                return coincideBusqueda && coincideProv && coincideGpo && coincideMueble && coincideSobrestock && coincideDescuadre;
              }
            }

            bool coincideRiesgo = true;
            if (_filtroRiesgoEspecial != null) {
              if (_filtroRiesgoEspecial == 'caducado') coincideRiesgo = dias < 0;
              else if (_filtroRiesgoEspecial == 'critico') coincideRiesgo = dias >= 0 && dias <= 14;
              else if (_filtroRiesgoEspecial == 'proximo') coincideRiesgo = dias > 14 && dias <= 30;
              else if (_filtroRiesgoEspecial == 'sano') coincideRiesgo = dias > 30;
            }

            bool coincideAnio = _filtroAnio == null || cad.year == _filtroAnio;
            bool coincideMes = _filtroMes == null || cad.month == _filtroMes;
            bool coincideVentana3Meses = true;

            return coincideBusqueda &&
                coincideProv &&
                coincideGpo &&
                coincideRiesgo &&
                coincideMueble &&
                coincideAnio &&
                coincideMes &&
                coincideVentana3Meses &&
                coincideSobrestock &&
                coincideDescuadre;
          }).toList();

          if (_modoVisualizacionSabana == 'captura' || _tieneFiltroCapturaActivo) {
            docsFiltrados.sort((a, b) {
              var dA = a.data() as Map<String, dynamic>;
              var dB = b.data() as Map<String, dynamic>;
              Timestamp? tA = dA['fechaCaptura'] as Timestamp?;
              Timestamp? tB = dB['fechaCaptura'] as Timestamp?;
              if (tA == null && tB == null) return 0;
              if (tA == null) return 1;
              if (tB == null) return -1;
              return tB.compareTo(tA); // Más recientes primero
            });
          } else {
            docsFiltrados.sort((a, b) {
              var dA = a.data() as Map<String, dynamic>;
              var dB = b.data() as Map<String, dynamic>;
              Timestamp tA = (dA['fechaCaducidad'] as Timestamp?) ?? Timestamp.now();
              Timestamp tB = (dB['fechaCaducidad'] as Timestamp?) ?? Timestamp.now();
              return tA.compareTo(tB); // Caducidad más próxima primero (Default)
            });
          }

          int limiteActual = _limiteLotesMostrados;
          var docsFinales = docsFiltrados.take(limiteActual).toList();
          bool mostrarPestanaCargar50Mas = docsFiltrados.length > _limiteLotesMostrados;

          return Column(
            children: [
              if (_filtrosOcultos)
                InkWell(
                  onTap: () => setState(() => _filtrosOcultos = false),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border(bottom: BorderSide(color: Colors.amber.withOpacity(0.6), width: 1.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.amber, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          'Bajar Filtros y Buscador (${docsFinales.length} de ${docsFiltrados.length} lotes)',
                          style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.tune, color: Colors.amberAccent, size: 15),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragEnd: (details) {
                      if (details.primaryVelocity != null && details.primaryVelocity! < -150) {
                        setState(() => _filtrosOcultos = true);
                      }
                    },
                    child: Container(
                      color: Colors.black,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, foregroundColor: Colors.white),
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Limpiar', style: TextStyle(fontSize: 12)),
                                onPressed: () {
                                  _busquedaController.clear();
                                  setState(() {
                                    _busqueda = "";
                                    _filtroProveedor = null;
                                    _filtroGrupo = null;
                                    _filtroRiesgoEspecial = null;
                                    _filtroTipoUbicacion = null;
                                    _filtroMueble = null;
                                    _filtroAnio = null;
                                    _filtroMes = null;
                                    _filtroDescuadreSAP = false;
                                    _filtroSobrestockIA = false;
                                    _filtroCapturaAnio = null;
                                    _filtroCapturaMes = null;
                                    _filtroCapturaDias.clear();
      _filtroCapturaHorasPorDia.clear();
                                    _limiteLotesMostrados = kPasoPaginacionLotes;
                                  });
                                },
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
                                icon: const Icon(Icons.download, size: 16),
                                label: const Text('CSV Filtros', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: () => _descargarExcel(docsFiltrados),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black),
                                icon: const Icon(Icons.date_range, size: 16),
                                label: const Text('CSV Próx. Mes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: () => _descargarProximoMes(snapshot.data!.docs),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _filtroDescuadreSAP ? Colors.redAccent : Colors.white10,
                                  foregroundColor: Colors.white,
                                  side: BorderSide(color: _filtroDescuadreSAP ? Colors.amberAccent : Colors.redAccent),
                                ),
                                icon: const Icon(Icons.compare_arrows, size: 16),
                                label: Text(_filtroDescuadreSAP ? 'Viendo Descuadre SAP' : 'Descuadre vs SAP', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: () => setState(() {
                                  _filtroDescuadreSAP = !_filtroDescuadreSAP;
                                  if (_filtroDescuadreSAP) _filtroMes = null;
                                  _limiteLotesMostrados = kPasoPaginacionLotes;
                                }),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _filtroSobrestockIA ? Colors.deepOrangeAccent : Colors.white10,
                                  foregroundColor: Colors.white,
                                  side: BorderSide(color: _filtroSobrestockIA ? Colors.amberAccent : Colors.deepOrangeAccent),
                                ),
                                icon: const Icon(Icons.psychology, size: 16),
                                label: Text(_filtroSobrestockIA ? 'Viendo Sobrestock IA' : '🧠 Sobrestock IA', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: () => setState(() {
                                  _filtroSobrestockIA = !_filtroSobrestockIA;
                                  if (_filtroSobrestockIA) {
                                    _filtroAnio = null;
                                    _filtroMes = null;
                                  }
                                  _limiteLotesMostrados = kPasoPaginacionLotes;
                                }),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.cyanAccent.withOpacity(0.18),
                                  foregroundColor: Colors.cyanAccent,
                                  side: const BorderSide(color: Colors.cyanAccent),
                                ),
                                icon: const Icon(Icons.policy, size: 16),
                                label: const Text('🕵️‍♂️ Auditor IA SAP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: () => _mostrarAuditorIASap(snapshot.data!.docs),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(left: 4, bottom: 4),
                                child: Text(
                                  'Condición para visualizar la lista (Orden principal):',
                                  style: TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 38,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _modoVisualizacionSabana == 'caducidad' ? Colors.amber : Colors.white10,
                                          foregroundColor: _modoVisualizacionSabana == 'caducidad' ? Colors.black : Colors.white70,
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        icon: const Icon(Icons.event_busy, size: 15),
                                        label: const Text(
                                          '1. Caducidad Próxima',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onPressed: () => setState(() {
                                          _modoVisualizacionSabana = 'caducidad';
                                          _limiteLotesMostrados = kPasoPaginacionLotes;
                                        }),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SizedBox(
                                      height: 38,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _modoVisualizacionSabana == 'captura' ? Colors.cyanAccent : Colors.white10,
                                          foregroundColor: _modoVisualizacionSabana == 'captura' ? Colors.black : Colors.white70,
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        icon: const Icon(Icons.history_toggle_off, size: 15),
                                        label: const Text(
                                          '2. Fecha de Captura',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onPressed: () => setState(() {
                                          _modoVisualizacionSabana = 'captura';
                                          _limiteLotesMostrados = kPasoPaginacionLotes;
                                        }),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),                          const SizedBox(height: 10),
                          TextField(
                            controller: _busquedaController,
                            decoration: InputDecoration(
                              hintText: '💬 Buscar SKU, UPC o frase IA (ej. "toyo bodega enero", "< 20 dias")...',
                              prefixIcon: const Icon(Icons.search, color: Colors.amber),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.qr_code_scanner, color: Colors.blueAccent),
                                tooltip: 'Escanear Código',
                                onPressed: () async {
                                  String? codigoEscaneado = await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const PantallaEscanerRapido()),
                                  );
                                  if (codigoEscaneado != null && codigoEscaneado.isNotEmpty) {
                                    String skuTraducido = await _traducirCodigoASku(codigoEscaneado);
                                    _busquedaController.text = skuTraducido;
                                    setState(() {
                                      _busqueda = skuTraducido.toLowerCase();
                                      _limiteLotesMostrados = kPasoPaginacionLotes;
                                    });
                                  }
                                },
                              ),
                              filled: true,
                              fillColor: Colors.white10,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(vertical: 0),
                            ),
                            onChanged: (v) => setState(() {
                              _busqueda = v.toLowerCase();
                              _limiteLotesMostrados = kPasoPaginacionLotes;
                            }),
                            onSubmitted: (v) async {
                              String traducido = await _traducirCodigoASku(v);
                              if (traducido != v.trim()) {
                                _busquedaController.text = traducido;
                                setState(() {
                                  _busqueda = traducido.toLowerCase();
                                  _limiteLotesMostrados = kPasoPaginacionLotes;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(left: 4, bottom: 4),
                                      child: Text('Filtro proveedor', style: TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold)),
                                    ),
                                    Container(
                                      height: 40,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String?>(
                                          isExpanded: true,
                                          dropdownColor: const Color(0xFF2C2C2C),
                                          value: _filtroProveedor,
                                          hint: const Text('Filtro proveedor', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                          items: [
                                            const DropdownMenuItem(value: null, child: Text('Filtro proveedor: Todos', style: TextStyle(fontSize: 12, color: Colors.greenAccent))),
                                            ...provs.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))),
                                          ],
                                          onChanged: (v) => setState(() {
                                            _filtroProveedor = v;
                                            _limiteLotesMostrados = kPasoPaginacionLotes;
                                          }),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(left: 4, bottom: 4),
                                      child: Text('Filtro Grupo de Art.', style: TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold)),
                                    ),
                                    Container(
                                      height: 40,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String?>(
                                          isExpanded: true,
                                          dropdownColor: const Color(0xFF2C2C2C),
                                          value: _filtroGrupo,
                                          hint: const Text('Filtro Grupo de Art.', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                          items: [
                                            const DropdownMenuItem(value: null, child: Text('Filtro Grupo de Art.: Todos', style: TextStyle(fontSize: 12, color: Colors.greenAccent))),
                                            ...grupos.map((g) => DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))),
                                          ],
                                          onChanged: (v) => setState(() {
                                            _filtroGrupo = v;
                                            _limiteLotesMostrados = kPasoPaginacionLotes;
                                          }),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(left: 4, bottom: 4),
                                      child: Text('Filtro Año', style: TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold)),
                                    ),
                                    Container(
                                      height: 40,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<int?>(
                                          isExpanded: true,
                                          dropdownColor: const Color(0xFF2C2C2C),
                                          value: _filtroAnio,
                                          hint: const Text('Filtro Año', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                          items: [
                                            const DropdownMenuItem<int?>(
                                              value: null,
                                              child: Text('Año: Todos los años', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                                            ),
                                            ...({
                                              DateTime.now().year - 1,
                                              DateTime.now().year,
                                              DateTime.now().year + 1,
                                              DateTime.now().year + 2,
                                              DateTime.now().year + 3,
                                              ...snapshot.data!.docs
                                                  .map((doc) => ((doc.data() as Map)['fechaCaducidad'] as Timestamp?)?.toDate().year)
                                                  .whereType<int>(),
                                            }.toList()
                                                  ..sort())
                                                .map((anio) => DropdownMenuItem<int?>(
                                                      value: anio,
                                                      child: Text(
                                                        anio == DateTime.now().year ? 'Año: $anio (En curso)' : 'Año: $anio',
                                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                                      ),
                                                    )),
                                          ],
                                          onChanged: (v) => setState(() {
                                            _filtroAnio = v;
                                            _limiteLotesMostrados = kPasoPaginacionLotes;
                                          }),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(left: 4, bottom: 4),
                                      child: Text('Filtro Mes', style: TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold)),
                                    ),
                                    Container(
                                      height: 40,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<int?>(
                                          isExpanded: true,
                                          dropdownColor: const Color(0xFF2C2C2C),
                                          value: _filtroMes,
                                          hint: const Text('Filtro Mes', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                          items: [
                                            const DropdownMenuItem<int?>(
                                              value: null,
                                              child: Text('Mes: Todos', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                                            ),
                                            ..._nombresMeses.entries.map((e) => DropdownMenuItem<int?>(
                                                  value: e.key,
                                                  child: Text(e.value, style: const TextStyle(fontSize: 12)),
                                                )),
                                          ],
                                          onChanged: (v) => setState(() {
                                            _filtroMes = v;
                                            _limiteLotesMostrados = kPasoPaginacionLotes;
                                          }),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(left: 4, bottom: 4),
                                child: Text('Filtro de captura', style: TextStyle(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 40,
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: _tieneFiltroCapturaActivo ? Colors.black : Colors.cyanAccent,
                                          backgroundColor: _tieneFiltroCapturaActivo ? Colors.cyanAccent : Colors.white10,
                                          side: const BorderSide(color: Colors.cyanAccent),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        onPressed: () => _abrirSelectorDinamicoFechaCaptura(snapshot.data!.docs),
                                        child: Text(
                                          _textoBotonFiltroCaptura(),
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_tieneFiltroCapturaActivo)
                                    IconButton(
                                      icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                                      tooltip: 'Quitar filtro de captura',
                                      onPressed: () => setState(() {
                                        _filtroCapturaAnio = null;
                                        _filtroCapturaMes = null;
                                        _filtroCapturaDias.clear();
      _filtroCapturaHorasPorDia.clear();
                                        _limiteLotesMostrados = kPasoPaginacionLotes;
                                      }),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(left: 4, bottom: 4),
                                child: Text('Filtro Ubicación (Desplegable por Nivel)', style: TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold)),
                              ),
                              SelectorJerarquicoUbicacion(
                                todasLasRutas: mueblesDisponibles,
                                rutaSeleccionada: _filtroMueble,
                                permitirSeleccionParcial: true,
                                textoRaizVacio: '📍 Ubicación: Todas (PISO / BODEGA / DISPLAY)',
                                conteoLotesPorRuta: conteoPorUbicacion,
                                onRutaCambiada: (val) => setState(() {
                                  _filtroMueble = val;
                                  _filtroTipoUbicacion = null;
                                  _limiteLotesMostrados = kPasoPaginacionLotes;
                                }),
                              ),
                            ],
                          ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () => setState(() => _filtrosOcultos = true),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.amber, width: 1.2),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.amber, size: 20),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Subir / Ocultar Filtros (Ver ${docsFiltrados.length} lotes)',
                                    style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_filtrosOcultos)
                Expanded(
                  child: docsFinales.isEmpty
                    ? const Center(child: Text('No hay productos que coincidan.', style: TextStyle(color: Colors.white54)))
                    : ValueListenableBuilder<int>(
                        valueListenable: JerarquiaUbicacionHelper.upcCacheVersion,
                        builder: (context, _, __) {
                          return Stack(
                            children: [
                              NotificationListener<ScrollNotification>(
                                onNotification: (ScrollNotification scrollInfo) {
                                  if (scrollInfo.metrics.axis == Axis.vertical) {
                                    if (!_filtrosOcultos && scrollInfo is ScrollUpdateNotification && (scrollInfo.scrollDelta ?? 0) > 14) {
                                      setState(() => _filtrosOcultos = true);
                                    }
                                    if (scrollInfo.metrics.maxScrollExtent > 0) {
                                      double p = (scrollInfo.metrics.pixels / scrollInfo.metrics.maxScrollExtent).clamp(0.0, 1.0);
                                      if ((p - _progresoScrollSabana.value).abs() > 0.015) {
                                        _progresoScrollSabana.value = p;
                                      }
                                    }
                                  }
                                  return false;
                                },
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  cacheExtent: esZebra ? 220.0 : 500.0,
                                  addRepaintBoundaries: true,
                                  itemCount: docsFinales.length + (mostrarPestanaCargar50Mas ? 1 : 0),
                                  itemBuilder: (context, i) {
                                    if (i == docsFinales.length) {
                                      int restantes = docsFiltrados.length - docsFinales.length;
                                      int loteSiguiente = restantes < kPasoPaginacionLotes ? restantes : kPasoPaginacionLotes;
                                      return Padding(
                                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                                        child: SizedBox(
                                          height: 46,
                                          width: double.infinity,
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.amber,
                                              foregroundColor: Colors.black,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _limiteLotesMostrados += kPasoPaginacionLotes;
                                              });
                                            },
                                            child: Text(
                                              'Cargar $loteSiguiente lotes más (Mostrando ${docsFinales.length} de ${docsFiltrados.length} lotes)',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                      );
                                    }

                                    var d = docsFinales[i].data() as Map<String, dynamic>;
                                    String docId = docsFinales[i].id;
                                    DateTime cad = (d['fechaCaducidad'] as Timestamp).toDate();
                                    int dias = cad.difference(hoy).inDays;
                                    Map<String, dynamic> etiqueta = EtiquetaMes.obtener(cad);
                                    bool isSelected = _seleccionados.contains(docId);
                                    String upcVisual = JerarquiaUbicacionHelper.obtenerUpcVisual(d);

                                    Widget cardWidget = Card(
                                      elevation: esZebra ? 0 : 1,
                                      color: isSelected ? Colors.redAccent.withOpacity(0.2) : Colors.white10,
                                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(15),
                                        side: BorderSide(color: isSelected ? Colors.redAccent : Colors.white24, width: isSelected ? 2 : 1),
                                      ),
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.all(12),
                                        onLongPress: () {
                                          if (!_modoSeleccion) {
                                            setState(() {
                                              _modoSeleccion = true;
                                              _seleccionados.add(docId);
                                            });
                                          }
                                        },
                                        onTap: () {
                                          if (_modoSeleccion) {
                                            setState(() {
                                              if (isSelected) {
                                                _seleccionados.remove(docId);
                                                if (_seleccionados.isEmpty) _modoSeleccion = false;
                                              } else {
                                                _seleccionados.add(docId);
                                              }
                                            });
                                          } else {
                                            _verDetalleCompleto(docsFinales[i]);
                                          }
                                        },
                                        leading: Container(
                                          width: 45,
                                          height: 45,
                                          decoration: BoxDecoration(
                                            color: etiqueta['color'].withOpacity(0.2),
                                            shape: BoxShape.circle,
                                            border: Border.all(color: etiqueta['color']),
                                          ),
                                          child: Center(
                                            child: Text(
                                              dias.toString(),
                                              style: TextStyle(color: etiqueta['color'], fontWeight: FontWeight.bold, fontSize: 14),
                                            ),
                                          ),
                                        ),
                                        title: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              d['descripcion'] ?? d['sku'],
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Marca: ${JerarquiaUbicacionHelper.obtenerMarcaVisual(d)}',
                                              style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                            Text(
                                              'SKU: ${d['sku'] ?? 'ND'}',
                                              style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                            Text(
                                              'UPC: $upcVisual',
                                              style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${d['cantidad']} pzas • Ubicación: ${JerarquiaUbicacionHelper.formatearRutaVisual(d['ubicacion']?.toString())}',
                                                style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Caducidad: ${cad.day.toString().padLeft(2, '0')}/${cad.month.toString().padLeft(2, '0')}/${cad.year}',
                                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Capturado: ${_formatearFechaCapturaLote(d)}',
                                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                                              ),
                                              if (JerarquiaUbicacionHelper.analizarRiesgoSobrestockIA(d) != null)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 4),
                                                  child: Text(
                                                    JerarquiaUbicacionHelper.analizarRiesgoSobrestockIA(d)!['detalle'].toString(),
                                                    style: const TextStyle(color: Colors.deepOrangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                              if (d['edicionTemporal'] == true)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 4),
                                                  child: Text(
                                                    '⏳ EDICIÓN TEMPORAL (Código orig: ${d['codigoOriginalCapturado'] ?? d['ean'] ?? d['sku']}) • En espera de alta oficial en SAP',
                                                    style: const TextStyle(color: Colors.purpleAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                              if (d['enPromocion'] == true)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 4),
                                                  child: Text(
                                                    '🏷️ EN PROMOCIÓN / SALDADO (${d['piezasEnPromocion'] ?? d['cantidad']} pzas) - Pendiente venta o baja',
                                                    style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                              if (_filtroDescuadreSAP)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 4),
                                                  child: Text(
                                                    '📊 Físico Tienda: ${sumaFisicaPorSku[(d['sku'] ?? '').toString()] ?? d['cantidad']} pzas  vs  SAP (OH): ${d['oh'] ?? 0} pzas',
                                                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                              if (d['comentarioCorporativo'] != null)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 4),
                                                  child: Text(
                                                    d['instruccionCorpEjecutada'] == true
                                                        ? '✅ CORP EJECUTADO (${d['motivoEjecucionCorp'] ?? 'Atendido'}) [${d['autorComentarioCorp'] ?? 'CORP'}]: ${d['comentarioCorporativo']}'
                                                        : '🏢 INSTRUCCIÓN (${d['autorComentarioCorp'] ?? 'CORP'}): ${d['comentarioCorporativo']}',
                                                    style: TextStyle(
                                                      color: d['instruccionCorpEjecutada'] == true ? Colors.greenAccent : Colors.pinkAccent,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        trailing: _modoSeleccion
                                            ? Icon(
                                                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                                color: isSelected ? Colors.redAccent : Colors.white54,
                                              )
                                            : const Icon(Icons.info_outline, color: Colors.white54),
                                      ),
                                    );

                                    return esZebra ? RepaintBoundary(child: cardWidget) : cardWidget;
                                  },
                                ),
                              ),
                              Positioned(
                                right: 1.5,
                                top: 6,
                                bottom: 6,
                                width: 3.5,
                                child: IgnorePointer(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      double trackH = constraints.maxHeight;
                                      double thumbH = (trackH * 0.18).clamp(24.0, 60.0);
                                      double maxTop = (trackH - thumbH).clamp(0.0, double.infinity);
                                      return ValueListenableBuilder<double>(
                                        valueListenable: _progresoScrollSabana,
                                        builder: (context, prog, _) {
                                          double thumbTop = maxTop * prog.clamp(0.0, 1.0);
                                          return Container(
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Stack(
                                              children: [
                                                Positioned(
                                                  top: thumbTop,
                                                  left: 0,
                                                  right: 0,
                                                  height: thumbH,
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.amber.withOpacity(0.65),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PantallaEscanerRapido extends StatefulWidget {
  const PantallaEscanerRapido({super.key});
  @override
  State<PantallaEscanerRapido> createState() => _PantallaEscanerRapidoState();
}

class _PantallaEscanerRapidoState extends State<PantallaEscanerRapido> {
  bool _detectado = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear SKU o UPC', style: TextStyle(color: Colors.amber, fontSize: 16))),
      body: MobileScanner(
        onDetect: (capture) {
          if (_detectado) return;
          final barcode = capture.barcodes.first;
          if (barcode.rawValue != null && barcode.rawValue!.trim().isNotEmpty) {
            setState(() => _detectado = true);
            Navigator.pop(context, barcode.rawValue!.trim());
          }
        },
      ),
    );
  }
}
