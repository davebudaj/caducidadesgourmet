import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../modelos/selector_jerarquico_ubicacion.dart';

class PantallaHistorial extends StatefulWidget {
  final String idTiendaGlobal;
  const PantallaHistorial({super.key, required this.idTiendaGlobal});
  @override
  State<PantallaHistorial> createState() => _PantallaHistorialState();
}

class _PantallaHistorialState extends State<PantallaHistorial> {
  // Por defecto inicia en el Año y Mes en curso y limita a los últimos 3 meses para proteger la memoria
  int? _anioFiltro = DateTime.now().year;
  int? _mesFiltro = DateTime.now().month;
  int? _semanaFiltro; // 1..5
  DateTimeRange? _rangoFechas;
  String? _grupoSeleccionado;
  bool _filtrosOcultos = false;

  static const int kLimiteRegistrosMemoria = 100;
  static const int kDiasVentanaMaxima = 92; // ~3 meses

  static const Map<int, String> _nombresMeses = {
    1: 'Enero', 2: 'Febrero', 3: 'Marzo', 4: 'Abril',
    5: 'Mayo', 6: 'Junio', 7: 'Julio', 8: 'Agosto',
    9: 'Septiembre', 10: 'Octubre', 11: 'Noviembre', 12: 'Diciembre'
  };

  @override
  void initState() {
    super.initState();
    JerarquiaUbicacionHelper.precargarCacheUpc();
  }

  int _calcularSemanaDelMes(DateTime fecha) {
    return ((fecha.day - 1) ~/ 7) + 1;
  }

  String _etiquetaRango() {
    if (_rangoFechas == null) return 'Filtrar por Día o Rango de Fechas';
    DateTime s = _rangoFechas!.start;
    DateTime e = _rangoFechas!.end;
    if (s.year == e.year && s.month == e.month && s.day == e.day) {
      return 'Día: ${s.day}/${s.month}/${s.year}';
    }
    return 'Del ${s.day}/${s.month} al ${e.day}/${e.month}/${e.year}';
  }

  void _abrirSelectorDiaORango() {
    DateTime hoy = DateTime.now();
    DateTime hace3Meses = hoy.subtract(const Duration(days: kDiasVentanaMaxima));
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Filtrar por Fecha Exacta o Periodo (Últimos 3 Meses)', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.today, color: Colors.amberAccent),
                title: const Text('Seleccionar 1 solo día específico', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: const Text('Filtra los tratamientos de una fecha única', style: TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () async {
                  Navigator.pop(ctx);
                  DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: _rangoFechas?.start ?? hoy,
                    firstDate: DateTime(hace3Meses.year, hace3Meses.month, 1),
                    lastDate: DateTime(hoy.year + 1, 12, 31),
                  );
                  if (picked != null) {
                    setState(() {
                      _rangoFechas = DateTimeRange(start: picked, end: picked);
                      _anioFiltro = picked.year;
                      _mesFiltro = picked.month;
                      _semanaFiltro = null;
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.date_range, color: Colors.cyanAccent),
                title: const Text('Seleccionar Rango de Fechas (Varios días)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: const Text('Elige fecha inicial y fecha final en el calendario', style: TextStyle(color: Colors.white54, fontSize: 11)),
                onTap: () async {
                  Navigator.pop(ctx);
                  DateTimeRange? pickedRange = await showDateRangePicker(
                    context: context,
                    initialDateRange: _rangoFechas,
                    firstDate: DateTime(hace3Meses.year, hace3Meses.month, 1),
                    lastDate: DateTime(hoy.year + 1, 12, 31),
                    helpText: 'SELECCIONA RANGO DE DÍAS',
                  );
                  if (pickedRange != null) {
                    setState(() {
                      _rangoFechas = pickedRange;
                      _anioFiltro = pickedRange.start.year;
                      _mesFiltro = pickedRange.start.month;
                      _semanaFiltro = null;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    DateTime hoy = DateTime.now();
    DateTime fechaCorte3Meses = hoy.subtract(const Duration(days: kDiasVentanaMaxima));
    int anioActual = hoy.year;
    List<int> aniosDisponibles = {hoy.year, fechaCorte3Meses.year}.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(title: const Text('Historial de Tratamientos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('tiendas')
            .doc(widget.idTiendaGlobal)
            .collection('historial_tratamientos')
            .orderBy('fechaTratamiento', descending: true)
            .limit(200)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.amber));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Aún no hay tratamientos registrados.'));

          // Filtrar primero por ventana de 3 meses para no saturar la memoria RAM
          var docsRecientes3Meses = snapshot.data!.docs.where((doc) {
            var d = doc.data() as Map<String, dynamic>;
            Timestamp? ts = d['fechaTratamiento'];
            if (ts == null) return false;
            return !ts.toDate().isBefore(fechaCorte3Meses);
          }).toList();

          var grupos = docsRecientes3Meses
              .map((doc) => (doc.data() as Map<String, dynamic>)['nombreGpoArticulos']?.toString() ?? 'SIN GRUPO')
              .toSet()
              .toList()
            ..sort();

          var docsFiltrados = docsRecientes3Meses.where((doc) {
            var d = doc.data() as Map<String, dynamic>;
            bool coincideGrupo = true;
            bool coincideFecha = true;

            if (_grupoSeleccionado != null) {
              String gpo = d['nombreGpoArticulos']?.toString() ?? 'SIN GRUPO';
              coincideGrupo = gpo == _grupoSeleccionado;
            }

            Timestamp? ts = d['fechaTratamiento'];
            if (ts == null) return false;
            DateTime dt = ts.toDate();
            DateTime diaDoc = DateTime(dt.year, dt.month, dt.day);

            if (_rangoFechas != null) {
              DateTime ini = DateTime(_rangoFechas!.start.year, _rangoFechas!.start.month, _rangoFechas!.start.day);
              DateTime fin = DateTime(_rangoFechas!.end.year, _rangoFechas!.end.month, _rangoFechas!.end.day);
              coincideFecha = !diaDoc.isBefore(ini) && !diaDoc.isAfter(fin);
            } else {
              if (_anioFiltro != null && dt.year != _anioFiltro) coincideFecha = false;
              if (_mesFiltro != null && dt.month != _mesFiltro) coincideFecha = false;
              if (_semanaFiltro != null && _calcularSemanaDelMes(dt) != _semanaFiltro) coincideFecha = false;
            }

            return coincideGrupo && coincideFecha;
          }).take(kLimiteRegistrosMemoria).toList();

          return Column(
            children: [
              if (_filtrosOcultos)
                InkWell(
                  onTap: () => setState(() => _filtrosOcultos = false),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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
                          'Bajar Filtros de Historial (${docsFiltrados.length} registros • Máx 3 meses)',
                          style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.tune, color: Colors.amberAccent, size: 15),
                      ],
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    border: Border(bottom: BorderSide(color: Colors.white24, width: 1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '⚡ Ventana activa: Últimos 3 meses (Máx. 100 registros)',
                            style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          if (_rangoFechas != null || _semanaFiltro != null || _grupoSeleccionado != null || _mesFiltro != hoy.month || _anioFiltro != anioActual)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: const Icon(Icons.refresh, color: Colors.amberAccent, size: 15),
                              label: const Text('Restaurar Mes Actual', style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: () => setState(() {
                                _rangoFechas = null;
                                _semanaFiltro = null;
                                _grupoSeleccionado = null;
                                _anioFiltro = hoy.year;
                                _mesFiltro = hoy.month;
                              }),
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
                                  padding: EdgeInsets.only(left: 4, bottom: 3),
                                  child: Text('Filtro Año', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                                ),
                                Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int?>(
                                      isExpanded: true,
                                      dropdownColor: const Color(0xFF2C2C2C),
                                      value: aniosDisponibles.contains(_anioFiltro) ? _anioFiltro : null,
                                      items: [
                                        const DropdownMenuItem(value: null, child: Text('Año: Últimos 3 meses', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                                        ...aniosDisponibles.map((a) => DropdownMenuItem(value: a, child: Text('📅 Año $a', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
                                      ],
                                      onChanged: (v) => setState(() {
                                        _anioFiltro = v;
                                        _rangoFechas = null;
                                      }),
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
                                const Padding(
                                  padding: EdgeInsets.only(left: 4, bottom: 3),
                                  child: Text('Filtro Mes', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                                ),
                                Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int?>(
                                      isExpanded: true,
                                      dropdownColor: const Color(0xFF2C2C2C),
                                      value: _mesFiltro,
                                      items: [
                                        const DropdownMenuItem(value: null, child: Text('Mes: Últimos 3 meses', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                                        ..._nombresMeses.entries.map((e) => DropdownMenuItem(value: e.key, child: Text('📅 ${e.value}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
                                      ],
                                      onChanged: (v) => setState(() {
                                        _mesFiltro = v;
                                        if (v == null) _semanaFiltro = null;
                                        _rangoFechas = null;
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
                                  padding: EdgeInsets.only(left: 4, bottom: 3),
                                  child: Text('Filtro Semana del Mes', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                                ),
                                Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int?>(
                                      isExpanded: true,
                                      dropdownColor: const Color(0xFF2C2C2C),
                                      value: _semanaFiltro,
                                      items: const [
                                        DropdownMenuItem(value: null, child: Text('Semana: Todas las del mes', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                                        DropdownMenuItem(value: 1, child: Text('Semana 1 (Días 1 al 7)', style: TextStyle(fontSize: 12))),
                                        DropdownMenuItem(value: 2, child: Text('Semana 2 (Días 8 al 14)', style: TextStyle(fontSize: 12))),
                                        DropdownMenuItem(value: 3, child: Text('Semana 3 (Días 15 al 21)', style: TextStyle(fontSize: 12))),
                                        DropdownMenuItem(value: 4, child: Text('Semana 4 (Días 22 al 28)', style: TextStyle(fontSize: 12))),
                                        DropdownMenuItem(value: 5, child: Text('Semana 5 (Días 29 al 31)', style: TextStyle(fontSize: 12))),
                                      ],
                                      onChanged: (v) => setState(() {
                                        _semanaFiltro = v;
                                        _rangoFechas = null;
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
                            child: SizedBox(
                              height: 40,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _rangoFechas != null ? Colors.amber : Colors.white10,
                                  foregroundColor: _rangoFechas != null ? Colors.black : Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.date_range, size: 16),
                                label: Text(
                                  _etiquetaRango(),
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onPressed: _abrirSelectorDiaORango,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String?>(
                                  isExpanded: true,
                                  dropdownColor: const Color(0xFF2C2C2C),
                                  value: grupos.contains(_grupoSeleccionado) ? _grupoSeleccionado : null,
                                  hint: const Text('Grupo Art.', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                  items: [
                                    const DropdownMenuItem(value: null, child: Text('Grupo: Todos', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                                    ...grupos.map((g) => DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))
                                  ],
                                  onChanged: (v) => setState(() => _grupoSeleccionado = v),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => setState(() => _filtrosOcultos = true),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.withOpacity(0.4)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.keyboard_arrow_up_rounded, color: Colors.amber, size: 18),
                              SizedBox(width: 4),
                              Text('Subir / Ocultar Filtros', style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: docsFiltrados.isEmpty
                    ? const Center(child: Text('No hay tratamientos registrados en este periodo (Últimos 3 meses).', style: TextStyle(color: Colors.white54)))
                    : ListView.builder(
                        itemCount: docsFiltrados.length,
                        itemBuilder: (context, index) {
                          var d = docsFiltrados[index].data() as Map<String, dynamic>;
                          DateTime? fecha = (d['fechaTratamiento'] as Timestamp?)?.toDate();
                          String grupo = d['nombreGpoArticulos'] ?? 'SIN GRUPO';
                          String proveedor = d['nombreProveedor'] ?? 'ND';
                          String ubicacion = JerarquiaUbicacionHelper.formatearRutaVisual(d['ubicacion']?.toString());

                          return Card(
                            color: Colors.white10,
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white24)),
                            child: ListTile(
                              leading: const Icon(Icons.history, color: Colors.blueAccent),
                              title: Text(d['descripcion'] ?? 'Sin descripción', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('SKU: ${d['sku'] ?? 'ND'} • Grupo: $grupo', style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                    Text('UPC: ${JerarquiaUbicacionHelper.obtenerUpcVisual(d)}', style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                                    Text('Prov: $proveedor', style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                    Text('Ubicación: $ubicacion', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                    const SizedBox(height: 2),
                                    Text('Retirado: ${d['cantidadTratada']} pzas • ${d['motivo']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                    Text('Usuario: ${d['usuario']}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                  ],
                                ),
                              ),
                              trailing: Text(fecha != null ? "${fecha.day}/${fecha.month}/${fecha.year}" : "", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                              isThreeLine: true,
                            ),
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
