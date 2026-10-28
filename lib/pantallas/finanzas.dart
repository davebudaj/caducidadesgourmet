import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';

class FinanzasService {
  static void actualizarResumenEnBatch({
    required WriteBatch batch,
    required String idTiendaGlobal,
    required String motivo,
    required int cantidad,
    required double monto,
    DateTime? fecha,
  }) {
    DateTime dt = fecha ?? DateTime.now();
    String tipo = 'merma';
    if (motivo.contains('Devolución')) {
      tipo = 'dev';
    } else if (motivo.contains('Saldado') || motivo.contains('Promoción')) {
      tipo = 'promo';
    }

    int m = dt.month;
    var docRef = FirebaseFirestore.instance
        .collection('tiendas')
        .doc(idTiendaGlobal)
        .collection('resumen_financiero')
        .doc('${dt.year}');

    batch.set(
      docRef,
      {
        'anio': dt.year,
        'anual_monto_$tipo': FieldValue.increment(monto),
        'anual_pzas_$tipo': FieldValue.increment(cantidad),
        'm${m}_monto_$tipo': FieldValue.increment(monto),
        'm${m}_pzas_$tipo': FieldValue.increment(cantidad),
        'ultimaActualizacion': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}

class PantallaGraficas extends StatefulWidget {
  final String idTiendaGlobal;
  final Function(String) onFiltroSeleccionado;
  const PantallaGraficas({super.key, required this.onFiltroSeleccionado, required this.idTiendaGlobal});

  @override
  State<PantallaGraficas> createState() => _PantallaGraficasState();
}

class _PantallaGraficasState extends State<PantallaGraficas> {
  int _indiceTocado = -1;
  bool _vistaMensual = false;
  bool _sincronizando = false;
  int _anioAcumulado = DateTime.now().year;
  DateTime _mesSeleccionado = DateTime(DateTime.now().year, DateTime.now().month, 1);

  static const List<String> _meses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
  ];

  DocumentReference<Map<String, dynamic>> get _refTienda =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal);

  @override
  void initState() {
    super.initState();
    _verificarInicializacionResumen();
  }

  Future<void> _verificarInicializacionResumen() async {
    var snap = await _refTienda.collection('resumen_financiero').limit(1).get();
    if (snap.docs.isEmpty) {
      await _reconstruirResumenDesdeHistorial(silencioso: true);
    }
  }

  Future<void> _reconstruirResumenDesdeHistorial({bool silencioso = false}) async {
    if (!silencioso && mounted) setState(() => _sincronizando = true);
    try {
      var histSnap = await _refTienda.collection('historial_tratamientos').get();
      Map<int, Map<String, dynamic>> acumuladoPorAnio = {};

      for (var doc in histSnap.docs) {
        var h = doc.data();
        Timestamp? ts = h['fechaTratamiento'];
        DateTime dt = ts != null ? ts.toDate() : DateTime.now();
        int anio = dt.year;
        int m = dt.month;

        String motivo = (h['motivo'] ?? '').toString();
        String tipo = 'merma';
        if (motivo.contains('Devolución')) {
          tipo = 'dev';
        } else if (motivo.contains('Saldado') || motivo.contains('Promoción')) {
          tipo = 'promo';
        }

        int cant = (h['cantidadTratada'] ?? 0) as int;
        double costo = double.tryParse((h['costoTotal'] ?? 0).toString()) ?? 0.0;
        if (costo <= 0) continue;

        acumuladoPorAnio.putIfAbsent(anio, () => {'anio': anio});
        var mapa = acumuladoPorAnio[anio]!;

        mapa['anual_monto_$tipo'] = (mapa['anual_monto_$tipo'] ?? 0.0) + costo;
        mapa['anual_pzas_$tipo'] = (mapa['anual_pzas_$tipo'] ?? 0) + cant;
        mapa['m${m}_monto_$tipo'] = (mapa['m${m}_monto_$tipo'] ?? 0.0) + costo;
        mapa['m${m}_pzas_$tipo'] = (mapa['m${m}_pzas_$tipo'] ?? 0) + cant;
        mapa['ultimaActualizacion'] = FieldValue.serverTimestamp();
      }

      var batch = FirebaseFirestore.instance.batch();
      var actuales = await _refTienda.collection('resumen_financiero').get();
      for (var d in actuales.docs) {
        batch.delete(d.reference);
      }
      for (var entry in acumuladoPorAnio.entries) {
        batch.set(_refTienda.collection('resumen_financiero').doc('${entry.key}'), entry.value);
      }
      await batch.commit();

      if (!silencioso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Resumen financiero sincronizado en la base de datos'), backgroundColor: Colors.green),
        );
      }
    } finally {
      if (!silencioso && mounted) setState(() => _sincronizando = false);
    }
  }

  Future<void> _mostrarDiagnosticoEjecutivoIA() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
    );

    try {
      var results = await Future.wait([
        _refTienda.collection('inventario_activo').get(),
        _refTienda.collection('resumen_financiero').get(),
      ]);
      var invDocs = results[0].docs;
      var resDocs = results[1].docs;

      DateTime hoy = DateTime.now();
      double montoCritico15d = 0;
      int lotesCriticos15d = 0;
      int lotesBodega90d = 0;
      double montoBodega90d = 0;
      int lotesArticulosNuevos = 0;
      int lotesEdicionTemporal = 0;
      Map<String, double> riesgoCriticoPorProv = {};
      Map<String, double> riesgoPorUbicacion = {};

      for (var doc in invDocs) {
        var d = doc.data();
        Timestamp? ts = d['fechaCaducidad'];
        int cant = (d['cantidad'] ?? 0) as int;
        double precio = double.tryParse((d['precioVenta'] ?? 0).toString()) ?? 0.0;
        double valor = cant * precio;
        String ubi = (d['ubicacion'] ?? 'ND').toString();
        String prov = (d['nombreProveedor'] ?? 'ND').toString();
        String desc = (d['descripcion'] ?? '').toString();

        if (desc == 'Artículo Nuevo' || desc == 'ARTÍCULO NUEVO / NO EN CATÁLOGO') {
          lotesArticulosNuevos++;
        } else if (d['edicionTemporal'] == true) {
          lotesEdicionTemporal++;
        }

        if (ts != null) {
          int dias = ts.toDate().difference(hoy).inDays;
          if (dias <= 15) {
            lotesCriticos15d++;
            montoCritico15d += valor;
            riesgoCriticoPorProv[prov] = (riesgoCriticoPorProv[prov] ?? 0) + valor;
            riesgoPorUbicacion[ubi] = (riesgoPorUbicacion[ubi] ?? 0) + valor;
          }
          if (ubi.toUpperCase().contains('BODEGA') && dias <= 90 && dias > 0) {
            lotesBodega90d++;
            montoBodega90d += valor;
          }
        }
      }

      double mermaAnual = 0, promoAnual = 0, devAnual = 0;
      for (var rDoc in resDocs) {
        if (rDoc.id == '${hoy.year}') {
          var r = rDoc.data();
          mermaAnual = double.tryParse((r['anual_monto_merma'] ?? 0).toString()) ?? 0.0;
          promoAnual = double.tryParse((r['anual_monto_promo'] ?? 0).toString()) ?? 0.0;
          devAnual = double.tryParse((r['anual_monto_dev'] ?? 0).toString()) ?? 0.0;
        }
      }

      double totalSalidas = mermaAnual + promoAnual + devAnual;
      double tasaRescate = totalSalidas > 0 ? ((promoAnual + devAnual) / totalSalidas) * 100 : 100.0;

      var topProvsCriticos = riesgoCriticoPorProv.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      var topUbisCriticas = riesgoPorUbicacion.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

      String provFoco = topProvsCriticos.isNotEmpty
          ? '${topProvsCriticos.first.key} (MXN ${topProvsCriticos.first.value.toStringAsFixed(2)})'
          : 'Sin proveedores en riesgo crítico';
      String ubiFoco = topUbisCriticas.isNotEmpty ? topUbisCriticas.first.key : 'Ninguna ubicación crítica';

      if (!mounted) return;
      Navigator.pop(context);

      String detalleCritico = lotesCriticos15d > 0
          ? 'Tienes $lotesCriticos15d lote(s) en ventana crítica por MXN ${montoCritico15d.toStringAsFixed(2)}.\n• Mayor concentración en: $ubiFoco.\n• Proveedor clave a gestionar hoy: $provFoco.'
          : '¡Excelente control! No tienes ningún lote en ventana crítica ≤ 15 días.';

      String consejoRescate = tasaRescate < 60
          ? '💡 Recomendación IA: Adelanta la etiqueta de 50% de descuento desde el aviso de 45 días para reducir la proporción de merma.'
          : '💡 Excelente balance: La tienda rescata la mayoría del valor antes del vencimiento.';

      String detalleFinanciero = totalSalidas > 0
          ? 'Tasa de recuperación actual: ${tasaRescate.toStringAsFixed(1)}% (Rescatado en Promoción/Devolución: MXN ${(promoAnual + devAnual).toStringAsFixed(2)} vs Merma: MXN ${mermaAnual.toStringAsFixed(2)}).\n$consejoRescate'
          : 'Aún no hay bajas con costo registradas en el año en curso.';

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.cyanAccent, width: 2)),
          title: const Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.cyanAccent, size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text('Asistente Ejecutivo IA • Diagnóstico', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _tarjetaInsightIA(
                    icono: Icons.local_fire_department,
                    color: Colors.redAccent,
                    titulo: '1. Prioridad Crítica Hoy (≤ 15 Días)',
                    detalle: detalleCritico,
                  ),
                  const SizedBox(height: 10),
                  _tarjetaInsightIA(
                    icono: Icons.warehouse,
                    color: Colors.pinkAccent,
                    titulo: '2. Flujo de Bodega a Piso (Política 90 Días)',
                    detalle: lotesBodega90d > 0
                        ? 'Se detectaron $lotesBodega90d lote(s) en BODEGA con menos de 90 días de vida (MXN ${montoBodega90d.toStringAsFixed(2)}). Se recomienda usar Trasvase Masivo hoy para exhibirlos en Piso/Display.'
                        : 'Bodega saludable: Todos los lotes en bodega superan los 90 días de margen.',
                  ),
                  const SizedBox(height: 10),
                  _tarjetaInsightIA(
                    icono: Icons.trending_up,
                    color: Colors.greenAccent,
                    titulo: '3. Eficiencia de Rescate Financiero (${hoy.year})',
                    detalle: detalleFinanciero,
                  ),
                  const SizedBox(height: 10),
                  _tarjetaInsightIA(
                    icono: Icons.qr_code_2,
                    color: Colors.purpleAccent,
                    titulo: '4. Integridad de Catálogo y Ediciones Temporales',
                    detalle: '• Artículos Nuevos pendientes de validar en anaquel: $lotesArticulosNuevos lote(s).\n• Lotes con Edición Temporal en espera de alta en SAP: $lotesEdicionTemporal lote(s).',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (lotesCriticos15d > 0)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.orangeAccent, side: const BorderSide(color: Colors.orangeAccent)),
                icon: const Icon(Icons.filter_list, size: 16),
                label: const Text('VER CRÍTICOS EN SÁBANA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.onFiltroSeleccionado('critico');
                },
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ENTENDIDO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error generando diagnóstico IA: $e')));
      }
    }
  }

  Widget _tarjetaInsightIA({required IconData icono, required Color color, required String titulo, required String detalle}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(titulo, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12))),
            ],
          ),
          const SizedBox(height: 6),
          Text(detalle, style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.35)),
        ],
      ),
    );
  }

  void _cambiarMes(int delta) {
    int anioMin = DateTime.now().year - 2;
    DateTime nuevo = DateTime(_mesSeleccionado.year, _mesSeleccionado.month + delta, 1);
    if (nuevo.year >= anioMin && nuevo.year <= DateTime.now().year + 5) {
      setState(() {
        _mesSeleccionado = nuevo;
        _indiceTocado = -1;
      });
    }
  }

  bool _entraEnPeriodoInventario(DateTime fecha, int anioActual) {
    if (_vistaMensual) {
      return fecha.year == _mesSeleccionado.year && fecha.month == _mesSeleccionado.month;
    }
    if (_anioAcumulado == 0) {
      return fecha.year >= (anioActual - 2) && fecha.year <= (anioActual + 5);
    }
    return fecha.year == _anioAcumulado;
  }

  Widget _barraTratamiento(String titulo, double monto, int pzas, double totalMonto, Color color) {
    double pct = totalMonto > 0 ? (monto / totalMonto) * 100 : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Text('${pct.toStringAsFixed(1)}%  •  MXN ${monto.toStringAsFixed(2)} ($pzas pz)',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: totalMonto > 0 ? (monto / totalMonto) : 0,
            backgroundColor: Colors.white10,
            color: color,
            minHeight: 8,
            borderRadius: BorderRadius.circular(5),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int anioHoy = DateTime.now().year;
    List<int> ultimos3Anios = [anioHoy, anioHoy - 1, anioHoy - 2];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Salud e Impacto Financiero', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('DIAGNÓSTICO IA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              onPressed: _mostrarDiagnosticoEjecutivoIA,
            ),
          ),
          IconButton(
            icon: _sincronizando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber))
                : const Icon(Icons.sync, color: Colors.amber),
            tooltip: 'Sincronizar sumas pre-calculadas',
            onPressed: _sincronizando ? null : () => _reconstruirResumenDesdeHistorial(silencioso: false),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: !_vistaMensual ? Colors.amber : Colors.white10,
                          foregroundColor: !_vistaMensual ? Colors.black : Colors.white70,
                        ),
                        icon: const Icon(Icons.history_edu, size: 16),
                        label: const Text('ACUMULADO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        onPressed: () => setState(() => _vistaMensual = false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _vistaMensual ? Colors.amber : Colors.white10,
                          foregroundColor: _vistaMensual ? Colors.black : Colors.white70,
                        ),
                        icon: const Icon(Icons.calendar_month, size: 16),
                        label: const Text('VISTA MENSUAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        onPressed: () => setState(() => _vistaMensual = true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (!_vistaMensual)
                  Row(
                    children: [
                      ...ultimos3Anios.map((anio) {
                        bool sel = _anioAcumulado == anio;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: sel ? Colors.amber.withOpacity(0.2) : Colors.white10,
                                side: BorderSide(color: sel ? Colors.amber : Colors.white24),
                                padding: const EdgeInsets.symmetric(vertical: 6),
                              ),
                              onPressed: () => setState(() => _anioAcumulado = anio),
                              child: Text('$anio', style: TextStyle(color: sel ? Colors.amberAccent : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                        );
                      }),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: _anioAcumulado == 0 ? Colors.amber.withOpacity(0.2) : Colors.white10,
                              side: BorderSide(color: _anioAcumulado == 0 ? Colors.amber : Colors.white24),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                            ),
                            onPressed: () => setState(() => _anioAcumulado = 0),
                            child: Text('3 AÑOS', style: TextStyle(color: _anioAcumulado == 0 ? Colors.amberAccent : Colors.white70, fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Container(
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.withOpacity(0.5))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(icon: const Icon(Icons.chevron_left, color: Colors.amber), onPressed: () => _cambiarMes(-1)),
                        Text('${_meses[_mesSeleccionado.month - 1].toUpperCase()} ${_mesSeleccionado.year}',
                            style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.2)),
                        IconButton(icon: const Icon(Icons.chevron_right, color: Colors.amber), onPressed: () => _cambiarMes(1)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _refTienda.collection('inventario_activo').snapshots(),
              builder: (context, invSnap) {
                if (!invSnap.hasData) return const Center(child: CircularProgressIndicator(color: Colors.amber));

                return StreamBuilder<QuerySnapshot>(
                  stream: _refTienda.collection('resumen_financiero').snapshots(),
                  builder: (context, resSnap) {
                    double totalRiesgo = 0, valorSano = 0, valorProximo = 0, valorCritico = 0, valorCaducado = 0;
                    Map<String, double> riesgoPorProveedor = {};
                    DateTime hoy = DateTime.now();

                    for (var doc in invSnap.data!.docs) {
                      var data = doc.data() as Map<String, dynamic>;
                      Timestamp? ts = data['fechaCaducidad'];
                      if (ts == null) continue;
                      DateTime cad = ts.toDate();
                      if (!_entraEnPeriodoInventario(cad, anioHoy)) continue;

                      int dias = cad.difference(hoy).inDays;
                      int cant = data['cantidad'] ?? 0;
                      double precio = double.tryParse((data['precioVenta'] ?? 0).toString()) ?? 0.0;
                      double valor = cant * precio;

                      if (dias < 0) {
                        valorCaducado += valor;
                        totalRiesgo += valor;
                      } else if (dias <= 14) {
                        valorCritico += valor;
                        totalRiesgo += valor;
                      } else if (dias <= 30) {
                        valorProximo += valor;
                        totalRiesgo += valor;
                      } else {
                        valorSano += valor;
                        totalRiesgo += valor;
                      }

                      String prov = data['nombreProveedor'] ?? 'DESCONOCIDO';
                      riesgoPorProveedor[prov] = (riesgoPorProveedor[prov] ?? 0) + valor;
                    }

                    double montoMerma = 0, montoPromo = 0, montoDevolucion = 0;
                    int pzasMerma = 0, pzasPromo = 0, pzasDevolucion = 0;

                    if (resSnap.hasData) {
                      for (var doc in resSnap.data!.docs) {
                        int anioDoc = int.tryParse(doc.id) ?? 0;
                        var r = doc.data() as Map<String, dynamic>;

                        if (_vistaMensual) {
                          if (anioDoc == _mesSeleccionado.year) {
                            int m = _mesSeleccionado.month;
                            montoDevolucion += double.tryParse((r['m${m}_monto_dev'] ?? 0).toString()) ?? 0.0;
                            pzasDevolucion += (r['m${m}_pzas_dev'] ?? 0) as int;
                            montoPromo += double.tryParse((r['m${m}_monto_promo'] ?? 0).toString()) ?? 0.0;
                            pzasPromo += (r['m${m}_pzas_promo'] ?? 0) as int;
                            montoMerma += double.tryParse((r['m${m}_monto_merma'] ?? 0).toString()) ?? 0.0;
                            pzasMerma += (r['m${m}_pzas_merma'] ?? 0) as int;
                          }
                        } else {
                          bool incluirAnio = (_anioAcumulado == 0)
                              ? (anioDoc >= anioHoy - 2 && anioDoc <= anioHoy + 1)
                              : (anioDoc == _anioAcumulado);
                          if (incluirAnio) {
                            montoDevolucion += double.tryParse((r['anual_monto_dev'] ?? 0).toString()) ?? 0.0;
                            pzasDevolucion += (r['anual_pzas_dev'] ?? 0) as int;
                            montoPromo += double.tryParse((r['anual_monto_promo'] ?? 0).toString()) ?? 0.0;
                            pzasPromo += (r['anual_pzas_promo'] ?? 0) as int;
                            montoMerma += double.tryParse((r['anual_monto_merma'] ?? 0).toString()) ?? 0.0;
                            pzasMerma += (r['anual_pzas_merma'] ?? 0) as int;
                          }
                        }
                      }
                    }

                    double totalGestionado = montoMerma + montoPromo + montoDevolucion;
                    var proveedoresOrdenados = riesgoPorProveedor.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

                    List<PieChartSectionData> rebanadas = [];
                    List<String> idFiltro = [];
                    double totalInv = valorSano + valorProximo + valorCritico + valorCaducado;
                    int idx = 0;

                    void agregarRebanada(double valor, Color color, String titulo, String id) {
                      if (valor > 0) {
                        bool tocado = _indiceTocado == idx;
                        String pct = ((valor / totalInv) * 100).toStringAsFixed(1);
                        rebanadas.add(PieChartSectionData(
                          value: valor,
                          color: color,
                          title: tocado ? '$pct%' : titulo,
                          radius: tocado ? 62 : 50,
                          titleStyle: TextStyle(fontSize: tocado ? 14 : 9, fontWeight: FontWeight.bold, color: color == Colors.redAccent ? Colors.white : Colors.black),
                        ));
                        idFiltro.add(id);
                        idx++;
                      }
                    }

                    agregarRebanada(valorSano, Colors.greenAccent, 'Sano\n>30d', 'sano');
                    agregarRebanada(valorProximo, Colors.yellow, 'Próximo\n15-30d', 'proximo');
                    agregarRebanada(valorCritico, Colors.orangeAccent, 'Crítico\n<15d', 'critico');
                    agregarRebanada(valorCaducado, Colors.redAccent, 'Caducado\nYa!', 'caducado');

                    String etiquetaPeriodo = _vistaMensual
                        ? '${_meses[_mesSeleccionado.month - 1]} ${_mesSeleccionado.year}'
                        : (_anioAcumulado == 0 ? 'Últimos 3 Años (${anioHoy - 2}-$anioHoy)' : 'Acumulado $_anioAcumulado (Ene-Dic)');

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 155,
                            child: rebanadas.isEmpty
                                ? Center(child: Text("Sin inventario que venza en $etiquetaPeriodo", style: const TextStyle(color: Colors.white54)))
                                : PieChart(
                                    PieChartData(
                                      sectionsSpace: 4,
                                      centerSpaceRadius: 30,
                                      sections: rebanadas,
                                      pieTouchData: PieTouchData(
                                        touchCallback: (FlTouchEvent event, pieTouchResponse) {
                                          if (!event.isInterestedForInteractions || pieTouchResponse?.touchedSection == null) {
                                            if (_indiceTocado != -1) setState(() => _indiceTocado = -1);
                                            return;
                                          }
                                          int nId = pieTouchResponse!.touchedSection!.touchedSectionIndex;
                                          if (nId != _indiceTocado) setState(() => _indiceTocado = nId);
                                          if (event is FlTapUpEvent && nId >= 0 && nId < idFiltro.length) {
                                            widget.onFiltroSeleccionado(idFiltro[nId]);
                                            setState(() => _indiceTocado = -1);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Colors.redAccent, Colors.orangeAccent]),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  _vistaMensual ? 'Total por Caducar en $etiquetaPeriodo' : 'Inventario Total en $etiquetaPeriodo',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                Text('MXN ${totalRiesgo.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                                if (!_vistaMensual)
                                  Text(
                                    'En riesgo inmediato (≤30d): MXN ${(valorCaducado + valorCritico + valorProximo).toStringAsFixed(2)}',
                                    style: const TextStyle(color: Colors.yellowAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Participación de Tratamientos', style: TextStyle(fontSize: 14, color: Colors.amber, fontWeight: FontWeight.bold)),
                                    Text('Total: MXN ${totalGestionado.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const Divider(color: Colors.white24, height: 16),
                                _barraTratamiento('📦 Devolución a Proveedor', montoDevolucion, pzasDevolucion, totalGestionado, Colors.cyanAccent),
                                _barraTratamiento('🏷️ Rescatado en Promoción', montoPromo, pzasPromo, totalGestionado, Colors.greenAccent),
                                _barraTratamiento('📉 Merma / Destrucción', montoMerma, pzasMerma, totalGestionado, Colors.redAccent),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Proveedores por Caducar ($etiquetaPeriodo)',
                            style: const TextStyle(fontSize: 14, color: Colors.amber, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          if (proveedoresOrdenados.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: Text('¡Sin proveedores con vencimientos en este periodo!', style: TextStyle(color: Colors.greenAccent))),
                            )
                          else
                            ...proveedoresOrdenados.map((item) {
                              double pct = totalRiesgo > 0 ? item.value / totalRiesgo : 0;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(child: Text(item.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), overflow: TextOverflow.ellipsis)),
                                        Text('MXN ${item.value.toStringAsFixed(2)}', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    LinearProgressIndicator(value: pct, backgroundColor: Colors.white10, color: Colors.amber, minHeight: 7, borderRadius: BorderRadius.circular(5)),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
