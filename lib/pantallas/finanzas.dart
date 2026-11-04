import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import 'package:universal_html/html.dart' as html;
import '../modelos/selector_jerarquico_ubicacion.dart';

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
  bool _vistaMensual = true;
  bool _sincronizando = false;
  int _anioAcumulado = DateTime.now().year;
  DateTime _mesSeleccionado = DateTime(DateTime.now().year, DateTime.now().month, 1);

  int _rubroSeleccionado = 0;

  static const List<String> _meses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
  ];

  late Stream<QuerySnapshot> _resumenStream;

  DocumentReference<Map<String, dynamic>> get _refTienda =>
      FirebaseFirestore.instance.collection('tiendas').doc(widget.idTiendaGlobal);

  @override
  void initState() {
    super.initState();
    _resumenStream = _refTienda.collection('resumen_financiero').snapshots();
    _verificarYEmpaquetarDatos();
  }

  String _limpiarTextoMojibake(String raw) {
    return raw
        .replaceAll('Ã‘', 'Ñ')
        .replaceAll('Ã±', 'ñ')
        .replaceAll('Ã\x91', 'Ñ')
        .replaceAll('Ã\x81', 'Á')
        .replaceAll('Ã\x89', 'É')
        .replaceAll('Ã\x8d', 'Í')
        .replaceAll('Ã\x93', 'Ó')
        .replaceAll('Ã\x9a', 'Ú')
        .replaceAll('ANTAÃ\ufffdO', 'ANTAÑO')
        .replaceAll('SEÃ\ufffdOR', 'SEÑOR')
        .replaceAll('Ã\ufffd', 'Ñ');
  }

  Future<void> _verificarYEmpaquetarDatos() async {
    try {
      var docEmp = await _refTienda.collection('resumen_financiero').doc('empaquetado_inventario').get();
      if (!docEmp.exists || docEmp.data()?['versionEsquema'] != 2) {
        await _reconstruirResumenYEmpaquetado(silencioso: true);
      } else {
        Timestamp? ts = docEmp.data()?['ultimaActualizacion'];
        if (ts == null || DateTime.now().difference(ts.toDate()).inMinutes >= 5) {
          _empaquetarInventarioSolo();
        }
      }
    } catch (_) {}
  }

  void _acumularEnPeriodo(
    Map<String, Map<String, dynamic>> periodos,
    String keyPeriodo, {
    required double valor,
    required int cant,
    required int dias,
    required String sku,
    required String desc,
    required String ubi,
    required String prov,
    required String grupo,
    required String marca,
    required bool esVistaMensualKey,
  }) {
    var p = periodos.putIfAbsent(keyPeriodo, () => {
      'total': 0.0,
      'sano': 0.0,
      'proximo': 0.0,
      'critico': 0.0,
      'caducado': 0.0,
      'riesgo': 0.0,
      'pzasTotal': 0,
      'pzasRiesgo': 0,
      'lotes': 0,
      'capPiso': 0.0,
      'capBodega': 0.0,
      'capDisplay': 0.0,
      'topSkus': <Map<String, dynamic>>[],
      'proveedores': <String, Map<String, dynamic>>{},
      'grupos': <String, Map<String, dynamic>>{},
      'marcas': <String, Map<String, dynamic>>{},
    });

    String ubiUp = ubi.toUpperCase();
    bool estaEnBodega = ubiUp.contains('BODEGA');
    // Un lote está en riesgo operativo si vence en <=30 días, o si en el mes analizado sigue guardado en BODEGA sin exhibirse en piso
    bool enRiesgoOperativo = (dias <= 30) || (esVistaMensualKey && estaEnBodega);

    p['total'] = (p['total'] as double) + valor;
    p['pzasTotal'] = (p['pzasTotal'] as int) + cant;
    p['lotes'] = (p['lotes'] as int) + 1;

    if (estaEnBodega) {
      p['capBodega'] = (p['capBodega'] as double) + valor;
    } else if (ubiUp.contains('DISPLAY')) {
      p['capDisplay'] = (p['capDisplay'] as double) + valor;
    } else {
      p['capPiso'] = (p['capPiso'] as double) + valor;
    }

    if (dias < 0) {
      p['caducado'] = (p['caducado'] as double) + valor;
    } else if (dias <= 14) {
      p['critico'] = (p['critico'] as double) + valor;
    } else if (dias <= 30) {
      p['proximo'] = (p['proximo'] as double) + valor;
    } else {
      p['sano'] = (p['sano'] as double) + valor;
    }

    if (enRiesgoOperativo) {
      p['riesgo'] = (p['riesgo'] as double) + valor;
      p['pzasRiesgo'] = (p['pzasRiesgo'] as int) + cant;
    }

    if (valor > 0) {
      var listaSkus = p['topSkus'] as List<Map<String, dynamic>>;
      listaSkus.add({
        'sku': sku,
        'descripcion': desc,
        'marca': marca,
        'ubicacion': ubi,
        'dias': dias,
        'pzas': cant,
        'monto': valor,
      });
    }

    void sumarRubro(String mapKey, String nombreClave) {
      var mapaRubro = p[mapKey] as Map<String, Map<String, dynamic>>;
      var item = mapaRubro.putIfAbsent(nombreClave, () => {
        'total': 0.0,
        'riesgo': 0.0,
        'pzas': 0,
        'pzasRiesgo': 0,
      });
      item['total'] = (item['total'] as double) + valor;
      item['pzas'] = (item['pzas'] as int) + cant;
      if (enRiesgoOperativo) {
        item['riesgo'] = (item['riesgo'] as double) + valor;
        item['pzasRiesgo'] = (item['pzasRiesgo'] as int) + cant;
      }
    }

    sumarRubro('proveedores', prov);
    sumarRubro('grupos', grupo);
    sumarRubro('marcas', marca);
  }

  Future<void> _empaquetarInventarioSolo() async {
    try {
      var invSnap = await _refTienda.collection('inventario_activo').get();
      DateTime hoy = DateTime.now();
      Map<String, Map<String, dynamic>> periodos = {};

      double montoCritico15d = 0;
      int lotesCriticos15d = 0;
      int lotesBodega90d = 0;
      double montoBodega90d = 0;
      int lotesArticulosNuevos = 0;
      int lotesEdicionTemporal = 0;
      double capitalPisoGlobal = 0;
      double capitalBodegaGlobal = 0;
      double capitalDisplayGlobal = 0;

      Map<String, double> riesgoCriticoPorProv = {};
      Map<String, double> riesgoPorUbicacion = {};

      for (var doc in invSnap.docs) {
        var data = doc.data();
        String ubi = (data['ubicacion'] ?? 'ND').toString();
        String ubiUp = ubi.toUpperCase();
        if (ubiUp == 'EN TRÁNSITO') continue;

        String desc = _limpiarTextoMojibake((data['descripcion'] ?? '').toString());
        if (desc == 'Artículo Nuevo' || desc == 'ARTÍCULO NUEVO / NO EN CATÁLOGO') {
          lotesArticulosNuevos++;
        } else if (data['edicionTemporal'] == true) {
          lotesEdicionTemporal++;
        }

        Timestamp? ts = data['fechaCaducidad'];
        if (ts == null) continue;
        DateTime cad = ts.toDate();
        int dias = cad.difference(hoy).inDays;

        int cant = (data['cantidad'] ?? 0) as int;
        double precio = double.tryParse((data['precioVenta'] ?? 0).toString()) ?? 0.0;
        double valor = cant * precio;

        if (ubiUp.contains('BODEGA')) {
          capitalBodegaGlobal += valor;
        } else if (ubiUp.contains('DISPLAY')) {
          capitalDisplayGlobal += valor;
        } else {
          capitalPisoGlobal += valor;
        }

        String prov = _limpiarTextoMojibake((data['nombreProveedor'] ?? 'DESCONOCIDO').toString().trim());
        if (prov.isEmpty) prov = 'DESCONOCIDO';
        String grupo = _limpiarTextoMojibake((data['nombreGpoArticulos'] ?? 'SIN GRUPO').toString().trim());
        if (grupo.isEmpty) grupo = 'SIN GRUPO';
        String marca = _limpiarTextoMojibake(JerarquiaUbicacionHelper.obtenerMarcaVisual(data));
        String sku = (data['sku'] ?? 'ND').toString();

        if (dias <= 15) {
          lotesCriticos15d++;
          montoCritico15d += valor;
          riesgoCriticoPorProv[prov] = (riesgoCriticoPorProv[prov] ?? 0) + valor;
          riesgoPorUbicacion[ubi] = (riesgoPorUbicacion[ubi] ?? 0) + valor;
        }
        if (ubiUp.contains('BODEGA') && dias <= 90 && dias > 0) {
          lotesBodega90d++;
          montoBodega90d += valor;
        }

        String keyMes = 'M_${cad.year}_${cad.month}';
        String keyAnio = 'A_${cad.year}';

        _acumularEnPeriodo(
          periodos,
          keyMes,
          valor: valor,
          cant: cant,
          dias: dias,
          sku: sku,
          desc: desc.isEmpty ? 'SIN NOMBRE' : desc,
          ubi: ubi,
          prov: prov,
          grupo: grupo,
          marca: marca,
          esVistaMensualKey: true,
        );
        _acumularEnPeriodo(
          periodos,
          keyAnio,
          valor: valor,
          cant: cant,
          dias: dias,
          sku: sku,
          desc: desc.isEmpty ? 'SIN NOMBRE' : desc,
          ubi: ubi,
          prov: prov,
          grupo: grupo,
          marca: marca,
          esVistaMensualKey: false,
        );
      }

      // Para cada periodo (mes y año), ordenar su propio Top 10 SKUs por mayor impacto en pesos
      for (var p in periodos.values) {
        var listaSkus = p['topSkus'] as List<Map<String, dynamic>>;
        listaSkus.sort((a, b) => (b['monto'] as double).compareTo(a['monto'] as double));
        p['topSkus'] = listaSkus.take(10).toList();
      }

      var topProvsCriticos = riesgoCriticoPorProv.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      var topUbisCriticas = riesgoPorUbicacion.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

      await _refTienda.collection('resumen_financiero').doc('empaquetado_inventario').set({
        'versionEsquema': 2,
        'periodos': periodos,
        'diagnostico_operativo': {
          'montoCritico15d': montoCritico15d,
          'lotesCriticos15d': lotesCriticos15d,
          'lotesBodega90d': lotesBodega90d,
          'montoBodega90d': montoBodega90d,
          'lotesArticulosNuevos': lotesArticulosNuevos,
          'lotesEdicionTemporal': lotesEdicionTemporal,
          'capitalPiso': capitalPisoGlobal,
          'capitalBodega': capitalBodegaGlobal,
          'capitalDisplay': capitalDisplayGlobal,
          'provFoco': topProvsCriticos.isNotEmpty
              ? '${topProvsCriticos.first.key} (MXN ${topProvsCriticos.first.value.toStringAsFixed(2)})'
              : 'Sin proveedores en riesgo crítico',
          'ubiFoco': topUbisCriticas.isNotEmpty ? topUbisCriticas.first.key : 'Ninguna ubicación crítica',
        },
        'ultimaActualizacion': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _reconstruirResumenYEmpaquetado({bool silencioso = false}) async {
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
        if (d.id != 'empaquetado_inventario') {
          batch.delete(d.reference);
        }
      }
      for (var entry in acumuladoPorAnio.entries) {
        batch.set(_refTienda.collection('resumen_financiero').doc('${entry.key}'), entry.value);
      }
      await batch.commit();

      await _empaquetarInventarioSolo();

      if (!silencioso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Datos empaquetados y sincronizados por mes y año.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } finally {
      if (!silencioso && mounted) setState(() => _sincronizando = false);
    }
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

  Map<String, double> _obtenerTratamientosDePeriodo(
    Map<int, Map<String, dynamic>> docsTratamientosPorAnio, {
    required bool mensual,
    required int anio,
    int mes = 1,
  }) {
    double dev = 0, promo = 0, merma = 0;
    double pzasDev = 0, pzasPromo = 0, pzasMerma = 0;
    var r = docsTratamientosPorAnio[anio];
    if (r != null) {
      if (mensual) {
        dev = double.tryParse((r['m${mes}_monto_dev'] ?? 0).toString()) ?? 0.0;
        pzasDev = double.tryParse((r['m${mes}_pzas_dev'] ?? 0).toString()) ?? 0.0;
        promo = double.tryParse((r['m${mes}_monto_promo'] ?? 0).toString()) ?? 0.0;
        pzasPromo = double.tryParse((r['m${mes}_pzas_promo'] ?? 0).toString()) ?? 0.0;
        merma = double.tryParse((r['m${mes}_monto_merma'] ?? 0).toString()) ?? 0.0;
        pzasMerma = double.tryParse((r['m${mes}_pzas_merma'] ?? 0).toString()) ?? 0.0;
      } else {
        dev = double.tryParse((r['anual_monto_dev'] ?? 0).toString()) ?? 0.0;
        pzasDev = double.tryParse((r['anual_pzas_dev'] ?? 0).toString()) ?? 0.0;
        promo = double.tryParse((r['anual_monto_promo'] ?? 0).toString()) ?? 0.0;
        pzasPromo = double.tryParse((r['anual_pzas_promo'] ?? 0).toString()) ?? 0.0;
        merma = double.tryParse((r['anual_monto_merma'] ?? 0).toString()) ?? 0.0;
        pzasMerma = double.tryParse((r['anual_pzas_merma'] ?? 0).toString()) ?? 0.0;
      }
    }
    return {
      'dev': dev,
      'promo': promo,
      'merma': merma,
      'total': dev + promo + merma,
      'pzasDev': pzasDev,
      'pzasPromo': pzasPromo,
      'pzasMerma': pzasMerma,
    };
  }

  List<Map<String, dynamic>> _procesarListaRubro(
    Map<String, dynamic>? rawMapa,
    double totalInventarioPeriodo,
    double pctRiesgoGlobalPeriodo,
  ) {
    if (rawMapa == null || rawMapa.isEmpty) return [];
    List<Map<String, dynamic>> lista = [];
    int numElementos = rawMapa.length;
    double participacionMediaEsperada = numElementos > 0 ? (100.0 / numElementos) : 0.0;

    for (var entry in rawMapa.entries) {
      var m = Map<String, dynamic>.from(entry.value as Map);
      double tot = double.tryParse((m['total'] ?? 0).toString()) ?? 0.0;
      double rsg = double.tryParse((m['riesgo'] ?? 0).toString()) ?? 0.0;
      int pzas = (m['pzas'] ?? 0) as int;
      int pzasRsg = (m['pzasRiesgo'] ?? 0) as int;
      if (tot <= 0) continue;

      double pctRiesgoInterno = (rsg / tot) * 100.0;
      double pctParticipacionTotal = totalInventarioPeriodo > 0 ? (tot / totalInventarioPeriodo) * 100.0 : 0.0;
      // Si el periodo tiene riesgo operativo, mide desviación de riesgo; si todo está en piso lejano, mide desviación de concentración de inventario
      double desviacion = pctRiesgoGlobalPeriodo > 0
          ? (pctRiesgoInterno - pctRiesgoGlobalPeriodo)
          : (pctParticipacionTotal - participacionMediaEsperada);

      lista.add({
        'nombre': _limpiarTextoMojibake(entry.key),
        'total': tot,
        'riesgo': rsg,
        'pzas': pzas,
        'pzasRiesgo': pzasRsg,
        'pctRiesgo': pctRiesgoInterno,
        'pctParticipacion': pctParticipacionTotal,
        'desviacion': desviacion,
      });
    }

    lista.sort((a, b) {
      int cmpR = (b['riesgo'] as double).compareTo(a['riesgo'] as double);
      if (cmpR != 0) return cmpR;
      return (b['total'] as double).compareTo(a['total'] as double);
    });
    return lista;
  }

  Future<void> _mostrarDiagnosticoEjecutivoIA(
    Map<String, dynamic> diagOp,
    Map<int, Map<String, dynamic>> tratamientosPorAnio,
  ) async {
    DateTime hoy = DateTime.now();
    double montoCritico15d = double.tryParse((diagOp['montoCritico15d'] ?? 0).toString()) ?? 0.0;
    int lotesCriticos15d = (diagOp['lotesCriticos15d'] ?? 0) as int;
    int lotesBodega90d = (diagOp['lotesBodega90d'] ?? 0) as int;
    double montoBodega90d = double.tryParse((diagOp['montoBodega90d'] ?? 0).toString()) ?? 0.0;
    int lotesArticulosNuevos = (diagOp['lotesArticulosNuevos'] ?? 0) as int;
    int lotesEdicionTemporal = (diagOp['lotesEdicionTemporal'] ?? 0) as int;
    String provFoco = (diagOp['provFoco'] ?? 'Sin proveedores en riesgo crítico').toString();
    String ubiFoco = (diagOp['ubiFoco'] ?? 'Ninguna ubicación crítica').toString();

    var tratAnual = _obtenerTratamientosDePeriodo(tratamientosPorAnio, mensual: false, anio: hoy.year);
    double mermaAnual = tratAnual['merma']!;
    double promoAnual = tratAnual['promo']!;
    double devAnual = tratAnual['dev']!;
    double totalSalidas = tratAnual['total']!;
    double tasaRescate = totalSalidas > 0 ? ((promoAnual + devAnual) / totalSalidas) * 100 : 100.0;

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
              child: Text('Asistente Ejecutivo IA • Diagnóstico Rápido', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 14)),
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
  }

  String _formatearVariacion(double actual, double anterior) {
    if (anterior <= 0) {
      return actual > 0 ? '+100.0% (Nuevo)' : '0.0% (Sin cambio)';
    }
    double diffPct = ((actual - anterior) / anterior) * 100.0;
    String signo = diffPct >= 0 ? '+' : '';
    return '$signo${diffPct.toStringAsFixed(1)}%';
  }

  void _mostrarDiagnosticoProfundoIA(
    Map<String, dynamic> todosPeriodos,
    Map<int, Map<String, dynamic>> tratamientosPorAnio,
    Map<String, dynamic> diagOp,
  ) {
    DateTime hoy = DateTime.now();
    // El análisis ahora se mueve dinámicamente con el mes y año seleccionado por el usuario
    int anioAct = _vistaMensual ? _mesSeleccionado.year : _anioAcumulado;
    int mesAct = _vistaMensual ? _mesSeleccionado.month : hoy.month;

    DateTime mesBaseProyeccion = _vistaMensual
        ? DateTime(_mesSeleccionado.year, _mesSeleccionado.month, 1)
        : DateTime(anioAct, hoy.month, 1);

    DateTime mesAntDt = DateTime(anioAct, mesAct - 1, 1);
    String keyMesActual = 'M_${anioAct}_$mesAct';
    String keyMesAnterior = 'M_${mesAntDt.year}_${mesAntDt.month}';

    var datosMesAct = Map<String, dynamic>.from((todosPeriodos[keyMesActual] ?? {}) as Map);
    var datosMesAnt = Map<String, dynamic>.from((todosPeriodos[keyMesAnterior] ?? {}) as Map);

    double invMesAct = double.tryParse((datosMesAct['total'] ?? 0).toString()) ?? 0.0;
    double rsgMesAct = double.tryParse((datosMesAct['riesgo'] ?? 0).toString()) ?? 0.0;
    double pctRsgMesAct = invMesAct > 0 ? (rsgMesAct / invMesAct) * 100.0 : 0.0;

    double invMesAnt = double.tryParse((datosMesAnt['total'] ?? 0).toString()) ?? 0.0;
    var tratMesAct = _obtenerTratamientosDePeriodo(tratamientosPorAnio, mensual: true, anio: anioAct, mes: mesAct);
    var tratMesAnt = _obtenerTratamientosDePeriodo(tratamientosPorAnio, mensual: true, anio: mesAntDt.year, mes: mesAntDt.month);

    // Proyección 3 meses futuros A PARTIR DEL MES SELECCIONADO (Mes +1, Mes +2, Mes +3)
    List<Map<String, dynamic>> proyeccion3Meses = [];
    double sumaProy3M = 0.0;
    int pzasProy3M = 0;
    for (int i = 1; i <= 3; i++) {
      DateTime mFut = DateTime(mesBaseProyeccion.year, mesBaseProyeccion.month + i, 1);
      String kFut = 'M_${mFut.year}_${mFut.month}';
      var dFut = Map<String, dynamic>.from((todosPeriodos[kFut] ?? {}) as Map);
      double totFut = double.tryParse((dFut['total'] ?? 0).toString()) ?? 0.0;
      int pzFut = (dFut['pzasTotal'] ?? 0) as int;
      int lotesFut = (dFut['lotes'] ?? 0) as int;
      sumaProy3M += totFut;
      pzasProy3M += pzFut;
      proyeccion3Meses.add({
        'etiqueta': '${_meses[mFut.month - 1]} ${mFut.year}',
        'horizonte': '+${i * 30} días',
        'monto': totFut,
        'pzas': pzFut,
        'lotes': lotesFut,
      });
    }

    // Acumulado Anual dinámico del año que se está consultando (ej. 2027 si ves Enero 2027, o 2026 si ves 2026)
    int y0 = anioAct;
    int y1 = anioAct - 1;
    int y2 = anioAct - 2;
    var dAnio0 = Map<String, dynamic>.from((todosPeriodos['A_$y0'] ?? {}) as Map);
    var dAnio1 = Map<String, dynamic>.from((todosPeriodos['A_$y1'] ?? {}) as Map);
    var dAnio2 = Map<String, dynamic>.from((todosPeriodos['A_$y2'] ?? {}) as Map);

    double invY0 = double.tryParse((dAnio0['total'] ?? 0).toString()) ?? 0.0;
    double rsgY0 = double.tryParse((dAnio0['riesgo'] ?? 0).toString()) ?? 0.0;
    double invY1 = double.tryParse((dAnio1['total'] ?? 0).toString()) ?? 0.0;
    double invY2 = double.tryParse((dAnio2['total'] ?? 0).toString()) ?? 0.0;

    var tratY0 = _obtenerTratamientosDePeriodo(tratamientosPorAnio, mensual: false, anio: y0);
    var tratY1 = _obtenerTratamientosDePeriodo(tratamientosPorAnio, mensual: false, anio: y1);

    double rescateY0 = tratY0['total']! > 0 ? ((tratY0['dev']! + tratY0['promo']!) / tratY0['total']!) * 100.0 : 100.0;
    double mermaPctY0 = tratY0['total']! > 0 ? (tratY0['merma']! / tratY0['total']!) * 100.0 : 0.0;
    double diffMetaRescate = rescateY0 - 75.0;

    // Datos específicos del periodo activo (Mes seleccionado o Año seleccionado)
    String keyActiva = _vistaMensual ? keyMesActual : 'A_$_anioAcumulado';
    String nombrePeriodoActivo = _vistaMensual
        ? '${_meses[_mesSeleccionado.month - 1]} ${_mesSeleccionado.year}'
        : 'Acumulado Anual $_anioAcumulado';
    var datosActivos = Map<String, dynamic>.from((todosPeriodos[keyActiva] ?? {}) as Map);
    double totalAct = double.tryParse((datosActivos['total'] ?? 0).toString()) ?? 0.0;
    double riesgoAct = double.tryParse((datosActivos['riesgo'] ?? 0).toString()) ?? 0.0;
    double pctRiesgoGlobalAct = totalAct > 0 ? (riesgoAct / totalAct) * 100.0 : 0.0;

    // Capital por Área (Piso / Bodega / Display) exclusivo del mes o año seleccionado
    double capPiso = double.tryParse((datosActivos['capPiso'] ?? 0).toString()) ?? 0.0;
    double capBodega = double.tryParse((datosActivos['capBodega'] ?? 0).toString()) ?? 0.0;
    double capDisplay = double.tryParse((datosActivos['capDisplay'] ?? 0).toString()) ?? 0.0;
    double capTotalAreas = capPiso + capBodega + capDisplay;
    double pctBodega = capTotalAreas > 0 ? (capBodega / capTotalAreas) * 100.0 : 0.0;

    // Top 10 SKUs (Pareto 80/20) exclusivo del mes o año seleccionado
    List<Map<String, dynamic>> top10Skus = [];
    if (datosActivos['topSkus'] is List) {
      for (var item in (datosActivos['topSkus'] as List)) {
        top10Skus.add(Map<String, dynamic>.from(item as Map));
      }
    }

    var listaProvs = _procesarListaRubro(datosActivos['proveedores'] as Map<String, dynamic>?, totalAct, pctRiesgoGlobalAct);
    var listaGrupos = _procesarListaRubro(datosActivos['grupos'] as Map<String, dynamic>?, totalAct, pctRiesgoGlobalAct);
    var listaMarcas = _procesarListaRubro(datosActivos['marcas'] as Map<String, dynamic>?, totalAct, pctRiesgoGlobalAct);

    String topProvTxt = listaProvs.isNotEmpty
        ? '${listaProvs.first['nombre']} (Riesgo/Bodega: MXN ${(listaProvs.first['riesgo'] as double).toStringAsFixed(2)} • ${(listaProvs.first['pctRiesgo'] as double).toStringAsFixed(1)}% • Desv: ${(listaProvs.first['desviacion'] as double) >= 0 ? "+" : ""}${(listaProvs.first['desviacion'] as double).toStringAsFixed(1)}%)'
        : 'Sin exposición relevante';
    String topGrupoTxt = listaGrupos.isNotEmpty
        ? '${listaGrupos.first['nombre']} (Riesgo/Bodega: MXN ${(listaGrupos.first['riesgo'] as double).toStringAsFixed(2)} • ${(listaGrupos.first['pctRiesgo'] as double).toStringAsFixed(1)}% • Desv: ${(listaGrupos.first['desviacion'] as double) >= 0 ? "+" : ""}${(listaGrupos.first['desviacion'] as double).toStringAsFixed(1)}%)'
        : 'Sin exposición relevante';
    String topMarcaTxt = listaMarcas.isNotEmpty
        ? '${listaMarcas.first['nombre']} (Riesgo/Bodega: MXN ${(listaMarcas.first['riesgo'] as double).toStringAsFixed(2)} • ${(listaMarcas.first['pctRiesgo'] as double).toStringAsFixed(1)}% • Desv: ${(listaMarcas.first['desviacion'] as double) >= 0 ? "+" : ""}${(listaMarcas.first['desviacion'] as double).toStringAsFixed(1)}%)'
        : 'Sin exposición relevante';

    String textoTopSkus = top10Skus.isEmpty
        ? 'Sin SKUs registrados en $nombrePeriodoActivo.'
        : top10Skus.take(5).map((s) => '  • [${s['sku']}] ${s['marca']} - ${s['descripcion']} (${s['pzas']} pz) ➔ MXN ${(s['monto'] as double).toStringAsFixed(2)} en ${s['ubicacion']}').join('\n');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161620),
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.amber, width: 2)),
        title: Row(
          children: [
            const Icon(Icons.psychology, color: Colors.amber, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '🧠 Diagnóstico Profundo IA • $nombrePeriodoActivo',
                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 540,
          height: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _tarjetaInsightIA(
                  icono: Icons.calendar_month,
                  color: Colors.cyanAccent,
                  titulo: '1. Diagnóstico Mensual y Variación MoM (${_meses[mesAct - 1]} $anioAct vs ${_meses[mesAntDt.month - 1]})',
                  detalle: '• Inventario que vence en ${_meses[mesAct - 1]} $anioAct: MXN ${invMesAct.toStringAsFixed(2)} (En riesgo / Bodega: MXN ${rsgMesAct.toStringAsFixed(2)} • ${pctRsgMesAct.toStringAsFixed(1)}%).\n'
                      '• Variación de inventario vs mes anterior (MoM): ${_formatearVariacion(invMesAct, invMesAnt)} (Mes previo: MXN ${invMesAnt.toStringAsFixed(2)}).\n'
                      '• Tratamientos aplicados en el mes: MXN ${tratMesAct['total']!.toStringAsFixed(2)} vs MXN ${tratMesAnt['total']!.toStringAsFixed(2)} (${_formatearVariacion(tratMesAct['total']!, tratMesAnt['total']!)}).',
                ),
                const SizedBox(height: 10),
                _tarjetaInsightIA(
                  icono: Icons.auto_graph,
                  color: Colors.orangeAccent,
                  titulo: '2. Proyección de los 3 Meses Siguientes a ${_meses[mesBaseProyeccion.month - 1]} ${mesBaseProyeccion.year}',
                  detalle: '• Capital proyectado en los 3 meses posteriores: MXN ${sumaProy3M.toStringAsFixed(2)} ($pzasProy3M pzas).\n' +
                      proyeccion3Meses.map((p) => '  ↳ ${p['etiqueta']} (${p['horizonte']}): MXN ${(p['monto'] as double).toStringAsFixed(2)} (${p['pzas']} pzas en ${p['lotes']} lotes)').join('\n'),
                ),
                const SizedBox(height: 10),
                _tarjetaInsightIA(
                  icono: Icons.stacked_line_chart,
                  color: Colors.greenAccent,
                  titulo: '3. Desempeño Acumulado Anual ($y0 vs $y1 / $y2)',
                  detalle: '• Inventario Acumulado en todo el año $y0: MXN ${invY0.toStringAsFixed(2)} (En riesgo / Bodega: MXN ${rsgY0.toStringAsFixed(2)}) | Variación YoY vs $y1: ${_formatearVariacion(invY0, invY1)} (En $y2: MXN ${invY2.toStringAsFixed(2)}).\n'
                      '• Bajas gestionadas en $y0: MXN ${tratY0['total']!.toStringAsFixed(2)} (Devolución: MXN ${tratY0['dev']!.toStringAsFixed(2)} • Promoción: MXN ${tratY0['promo']!.toStringAsFixed(2)} • Merma: MXN ${tratY0['merma']!.toStringAsFixed(2)}).\n'
                      '• Tasa de Rescate $y0: ${rescateY0.toStringAsFixed(1)}% vs Meta 75% (${diffMetaRescate >= 0 ? "+" : ""}${diffMetaRescate.toStringAsFixed(1)} pts) | Índice Merma: ${mermaPctY0.toStringAsFixed(1)}%.',
                ),
                const SizedBox(height: 10),
                _tarjetaInsightIA(
                  icono: Icons.pie_chart,
                  color: Colors.pinkAccent,
                  titulo: '4. Desviación en los 3 Rubros ($nombrePeriodoActivo • Media Riesgo/Bodega: ${pctRiesgoGlobalAct.toStringAsFixed(1)}%)',
                  detalle: '• 🏢 Proveedor crítico #1: $topProvTxt\n'
                      '• 📦 Grupo de Art. crítico #1: $topGrupoTxt\n'
                      '• 🏷️ Marca crítica #1: $topMarcaTxt',
                ),
                const SizedBox(height: 10),
                _tarjetaInsightIA(
                  icono: Icons.storefront,
                  color: Colors.purpleAccent,
                  titulo: '5. Capital por Área (Piso vs Bodega) y Top SKUs de $nombrePeriodoActivo',
                  detalle: '• Distribución física de $nombrePeriodoActivo: En Piso (Exhibido): MXN ${capPiso.toStringAsFixed(2)} • En Bodega (Guardado): MXN ${capBodega.toStringAsFixed(2)} (${pctBodega.toStringAsFixed(1)}%) • En Display: MXN ${capDisplay.toStringAsFixed(2)}.\n'
                      '• Top SKUs de mayor valor que caducan en $nombrePeriodoActivo:\n$textoTopSkus',
                ),
                const SizedBox(height: 10),
                _tarjetaInsightIA(
                  icono: Icons.lightbulb,
                  color: Colors.amberAccent,
                  titulo: '6. Recomendaciones Estratégicas IA para $nombrePeriodoActivo',
                  detalle: '1. Extraer de Bodega a Piso los MXN ${capBodega.toStringAsFixed(2)} (${pctBodega.toStringAsFixed(1)}% del mes) que siguen guardados sin exhibición.\n'
                      '2. Priorizar negociación comercial con ${listaProvs.isNotEmpty ? listaProvs.first['nombre'] : "el proveedor principal"} y etiquetado oportuno en la marca ${listaMarcas.isNotEmpty ? listaMarcas.first['nombre'] : "líder"}.\n'
                      '3. Preparar capacidad de exhibición para el mes siguiente (${proyeccion3Meses.first['etiqueta']}: MXN ${(proyeccion3Meses.first['monto'] as double).toStringAsFixed(2)} en ${proyeccion3Meses.first['lotes']} lotes).',
                ),
              ],
            ),
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                icon: const Icon(Icons.picture_as_pdf, size: 16),
                label: const Text('PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                onPressed: () => _exportarDiagnosticoProfundoPDF(
                  nombrePeriodoActivo: nombrePeriodoActivo,
                  anioAnalizado: y0,
                  invMesAct: totalAct,
                  rsgMesAct: riesgoAct,
                  pctRsgMesAct: pctRiesgoGlobalAct,
                  varMoM: _formatearVariacion(invMesAct, invMesAnt),
                  proyeccion3Meses: proyeccion3Meses,
                  sumaProy3M: sumaProy3M,
                  invY0: invY0,
                  rsgY0: rsgY0,
                  varYoY: _formatearVariacion(invY0, invY1),
                  tratY0: tratY0,
                  rescateY0: rescateY0,
                  pctRiesgoGlobalAct: pctRiesgoGlobalAct,
                  listaProvs: listaProvs,
                  listaGrupos: listaGrupos,
                  listaMarcas: listaMarcas,
                  top10Skus: top10Skus,
                  capPiso: capPiso,
                  capBodega: capBodega,
                  capDisplay: capDisplay,
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                icon: const Icon(Icons.table_view, size: 16),
                label: const Text('EXCEL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                onPressed: () => _exportarDiagnosticoProfundoExcel(
                  nombrePeriodoActivo: nombrePeriodoActivo,
                  anioAnalizado: y0,
                  invMesAct: totalAct,
                  rsgMesAct: riesgoAct,
                  pctRsgMesAct: pctRiesgoGlobalAct,
                  varMoM: _formatearVariacion(invMesAct, invMesAnt),
                  proyeccion3Meses: proyeccion3Meses,
                  invY0: invY0,
                  rsgY0: rsgY0,
                  varYoY: _formatearVariacion(invY0, invY1),
                  tratY0: tratY0,
                  rescateY0: rescateY0,
                  pctRiesgoGlobalAct: pctRiesgoGlobalAct,
                  listaProvs: listaProvs,
                  listaGrupos: listaGrupos,
                  listaMarcas: listaMarcas,
                  top10Skus: top10Skus,
                  capPiso: capPiso,
                  capBodega: capBodega,
                  capDisplay: capDisplay,
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CERRAR', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _exportarDiagnosticoProfundoExcel({
    required String nombrePeriodoActivo,
    required int anioAnalizado,
    required double invMesAct,
    required double rsgMesAct,
    required double pctRsgMesAct,
    required String varMoM,
    required List<Map<String, dynamic>> proyeccion3Meses,
    required double invY0,
    required double rsgY0,
    required String varYoY,
    required Map<String, double> tratY0,
    required double rescateY0,
    required double pctRiesgoGlobalAct,
    required List<Map<String, dynamic>> listaProvs,
    required List<Map<String, dynamic>> listaGrupos,
    required List<Map<String, dynamic>> listaMarcas,
    required List<Map<String, dynamic>> top10Skus,
    required double capPiso,
    required double capBodega,
    required double capDisplay,
  }) {
    StringBuffer csv = StringBuffer();
    csv.writeln("REPORTE EJECUTIVO DE DIAGNOSTICO PROFUNDO IA - GOURMET GUARD");
    csv.writeln("Tienda,${widget.idTiendaGlobal},Periodo Analizado,$nombrePeriodoActivo,Fecha Generacion,${DateTime.now().toIso8601String().substring(0, 10)}");
    csv.writeln("");

    csv.writeln("1. RESUMEN DEL PERIODO ($nombrePeriodoActivo), ACUMULADO ANUAL ($anioAnalizado) Y CAPITAL POR AREA");
    csv.writeln("INDICADOR,INVENTARIO TOTAL (MXN),MONTO EN RIESGO / BODEGA (MXN),% RIESGO,VARIACION PERIODO ANTERIOR");
    csv.writeln("Periodo Seleccionado ($nombrePeriodoActivo),${invMesAct.toStringAsFixed(2)},${rsgMesAct.toStringAsFixed(2)},${pctRsgMesAct.toStringAsFixed(2)}%,$varMoM");
    csv.writeln("Acumulado Anual ($anioAnalizado),${invY0.toStringAsFixed(2)},${rsgY0.toStringAsFixed(2)},${(invY0 > 0 ? (rsgY0 / invY0) * 100 : 0).toStringAsFixed(2)}%,$varYoY");
    csv.writeln("Capital por Area ($nombrePeriodoActivo),PISO (Exhibido): ${capPiso.toStringAsFixed(2)},BODEGA (Guardado): ${capBodega.toStringAsFixed(2)},DISPLAY: ${capDisplay.toStringAsFixed(2)},TOTAL: ${(capPiso + capBodega + capDisplay).toStringAsFixed(2)}");
    csv.writeln("");

    csv.writeln("2. PROYECCION DE LOS 3 MESES SIGUIENTES A $nombrePeriodoActivo");
    csv.writeln("MES PROYECTADO,HORIZONTE,CAPITAL POR VENCER (MXN),PIEZAS,LOTES");
    for (var p in proyeccion3Meses) {
      csv.writeln("${p['etiqueta']},${p['horizonte']},${(p['monto'] as double).toStringAsFixed(2)},${p['pzas']},${p['lotes']}");
    }
    csv.writeln("");

    csv.writeln("3. GESTION DE TRATAMIENTOS Y TASA DE RESCATE ANUAL ($anioAnalizado)");
    csv.writeln("DEVOLUCION PROVEEDOR (MXN),RESCATADO PROMOCION (MXN),MERMA DESTRUCCION (MXN),TOTAL GESTIONADO (MXN),TASA DE RESCATE (%)");
    csv.writeln("${tratY0['dev']!.toStringAsFixed(2)},${tratY0['promo']!.toStringAsFixed(2)},${tratY0['merma']!.toStringAsFixed(2)},${tratY0['total']!.toStringAsFixed(2)},${rescateY0.toStringAsFixed(2)}%");
    csv.writeln("");

    csv.writeln("4. TOP 10 SKUS DE MAYOR IMPACTO EN $nombrePeriodoActivo (PARETO 80/20)");
    csv.writeln("SKU,MARCA,DESCRIPCION,UBICACION,DIAS RESTANTES,PIEZAS,VALOR EN INVENTARIO (MXN)");
    for (var s in top10Skus) {
      String dLimpia = '"${s['descripcion'].toString().replaceAll('"', '""')}"';
      String uLimpia = '"${s['ubicacion'].toString().replaceAll('"', '""')}"';
      csv.writeln("${s['sku']},${s['marca']},$dLimpia,$uLimpia,${s['dias']},${s['pzas']},${(s['monto'] as double).toStringAsFixed(2)}");
    }
    csv.writeln("");

    void escribirTablaRubro(String titulo, List<Map<String, dynamic>> items) {
      csv.writeln(titulo);
      csv.writeln("NOMBRE,INVENTARIO TOTAL (MXN),MONTO EN RIESGO / BODEGA (MXN),PIEZAS TOTALES,PIEZAS EN RIESGO,% RIESGO RUBRO,% PARTICIPACION INVENTARIO,DESVIACION VS MEDIA (${pctRiesgoGlobalAct.toStringAsFixed(1)}%)");
      for (var it in items) {
        String nom = '"${it['nombre'].toString().replaceAll('"', '""')}"';
        double tot = it['total'] as double;
        double rsg = it['riesgo'] as double;
        double pctR = it['pctRiesgo'] as double;
        double pctP = it['pctParticipacion'] as double;
        double desv = it['desviacion'] as double;
        csv.writeln("$nom,${tot.toStringAsFixed(2)},${rsg.toStringAsFixed(2)},${it['pzas']},${it['pzasRiesgo']},${pctR.toStringAsFixed(2)}%,${pctP.toStringAsFixed(2)}%,${desv >= 0 ? '+' : ''}${desv.toStringAsFixed(2)}%");
      }
      csv.writeln("");
    }

    escribirTablaRubro("5. DESGLOSE Y DESVIACION POR PROVEEDOR ($nombrePeriodoActivo)", listaProvs);
    escribirTablaRubro("6. DESGLOSE Y DESVIACION POR GRUPO DE ARTICULOS ($nombrePeriodoActivo)", listaGrupos);
    escribirTablaRubro("7. DESGLOSE Y DESVIACION POR MARCA ($nombrePeriodoActivo)", listaMarcas);

    final bytes = utf8.encode('\uFEFF${csv.toString()}');
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute("download", "Diagnostico_Profundo_IA_${widget.idTiendaGlobal}_${nombrePeriodoActivo.replaceAll(' ', '_')}.csv")
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  void _exportarDiagnosticoProfundoPDF({
    required String nombrePeriodoActivo,
    required int anioAnalizado,
    required double invMesAct,
    required double rsgMesAct,
    required double pctRsgMesAct,
    required String varMoM,
    required List<Map<String, dynamic>> proyeccion3Meses,
    required double sumaProy3M,
    required double invY0,
    required double rsgY0,
    required String varYoY,
    required Map<String, double> tratY0,
    required double rescateY0,
    required double pctRiesgoGlobalAct,
    required List<Map<String, dynamic>> listaProvs,
    required List<Map<String, dynamic>> listaMarcas,
    required List<Map<String, dynamic>> listaGrupos,
    required List<Map<String, dynamic>> top10Skus,
    required double capPiso,
    required double capBodega,
    required double capDisplay,
  }) {
    String filasRubroHtml(List<Map<String, dynamic>> items) {
      if (items.isEmpty) return '<tr><td colspan="6">Sin registros en este periodo</td></tr>';
      StringBuffer sb = StringBuffer();
      for (var it in items.take(15)) {
        double desv = it['desviacion'] as double;
        String colorDesv = desv > 5 ? '#d32f2f' : (desv < -5 ? '#2e7d32' : '#555');
        sb.write('<tr>');
        sb.write('<td><b>${it['nombre']}</b></td>');
        sb.write('<td>MXN ${(it['total'] as double).toStringAsFixed(2)}</td>');
        sb.write('<td>MXN ${(it['riesgo'] as double).toStringAsFixed(2)}</td>');
        sb.write('<td>${it['pzas']} (${it['pzasRiesgo']} rsg)</td>');
        sb.write('<td>${(it['pctRiesgo'] as double).toStringAsFixed(1)}% (${(it['pctParticipacion'] as double).toStringAsFixed(1)}% inv)</td>');
        sb.write('<td style="color:$colorDesv;font-weight:bold;">${desv >= 0 ? "+" : ""}${desv.toStringAsFixed(1)}%</td>');
        sb.write('</tr>');
      }
      return sb.toString();
    }

    StringBuffer sbProy = StringBuffer();
    for (var p in proyeccion3Meses) {
      sbProy.write('<tr>');
      sbProy.write('<td><b>${p['etiqueta']}</b></td>');
      sbProy.write('<td>${p['horizonte']}</td>');
      sbProy.write('<td>MXN ${(p['monto'] as double).toStringAsFixed(2)}</td>');
      sbProy.write('<td>${p['pzas']} pzas</td>');
      sbProy.write('<td>${p['lotes']} lotes</td>');
      sbProy.write('</tr>');
    }

    StringBuffer sbTopSkus = StringBuffer();
    if (top10Skus.isEmpty) {
      sbTopSkus.write('<tr><td colspan="6">Sin SKUs registrados en $nombrePeriodoActivo</td></tr>');
    } else {
      for (var s in top10Skus) {
        sbTopSkus.write('<tr>');
        sbTopSkus.write('<td><b>${s['sku']}</b></td>');
        sbTopSkus.write('<td>${s['marca']}</td>');
        sbTopSkus.write('<td>${s['descripcion']}</td>');
        sbTopSkus.write('<td>${s['ubicacion']}</td>');
        sbTopSkus.write('<td>${s['dias']}d (${s['pzas']} pz)</td>');
        sbTopSkus.write('<td style="color:#d32f2f;font-weight:bold;">MXN ${(s['monto'] as double).toStringAsFixed(2)}</td>');
        sbTopSkus.write('</tr>');
      }
    }

    StringBuffer htmlDoc = StringBuffer();
    htmlDoc.write('<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8">');
    htmlDoc.write('<title>Diagnóstico Profundo IA - ${widget.idTiendaGlobal} - $nombrePeriodoActivo</title>');
    htmlDoc.write('<style>');
    htmlDoc.write('body { font-family: Arial, sans-serif; margin: 24px; color: #1e1e1e; background: #fff; }');
    htmlDoc.write('.header { display: flex; justify-content: space-between; align-items: center; border-bottom: 3px solid #ffc107; padding-bottom: 10px; margin-bottom: 16px; }');
    htmlDoc.write('h1 { margin: 0; font-size: 20px; color: #111; }');
    htmlDoc.write('h2 { font-size: 13.5px; background: #1e1e28; color: #ffc107; padding: 7px 12px; border-radius: 6px; margin-top: 16px; margin-bottom: 8px; }');
    htmlDoc.write('.kpi-grid { display: flex; gap: 10px; margin-bottom: 14px; }');
    htmlDoc.write('.kpi { flex: 1; border: 1px solid #ccc; border-radius: 8px; padding: 10px; background: #fafafa; }');
    htmlDoc.write('.kpi-title { font-size: 10.5px; color: #666; font-weight: bold; }');
    htmlDoc.write('.kpi-val { font-size: 16px; font-weight: bold; color: #111; margin-top: 4px; }');
    htmlDoc.write('.kpi-sub { font-size: 10.5px; color: #d32f2f; margin-top: 2px; font-weight: bold; }');
    htmlDoc.write('table { width: 100%; border-collapse: collapse; font-size: 10.5px; margin-bottom: 12px; }');
    htmlDoc.write('th { background: #eee; text-align: left; padding: 6px; border: 1px solid #ccc; }');
    htmlDoc.write('td { padding: 6px; border: 1px solid #ddd; }');
    htmlDoc.write('.no-print { margin-bottom: 16px; padding: 10px; background: #1e1e28; color: #fff; border-radius: 8px; text-align: right; }');
    htmlDoc.write('.btn { background: #ffc107; color: #000; border: none; padding: 8px 16px; font-weight: bold; border-radius: 6px; cursor: pointer; }');
    htmlDoc.write('@media print { .no-print { display: none; } body { margin: 0; } }');
    htmlDoc.write('</style></head><body>');
    htmlDoc.write('<div class="no-print"><button class="btn" onclick="window.print()">🖨️ IMPRIMIR / GUARDAR COMO PDF</button></div>');
    htmlDoc.write('<div class="header"><div>');
    htmlDoc.write('<h1>🧠 REPORTE EJECUTIVO DE DIAGNÓSTICO PROFUNDO IA</h1>');
    htmlDoc.write('<div style="font-size:12px;color:#555;">Sucursal: <b>${widget.idTiendaGlobal}</b> • Periodo Analizado: <b>$nombrePeriodoActivo</b></div>');
    htmlDoc.write('</div><div style="font-size:11px;text-align:right;">Fecha: ${DateTime.now().toIso8601String().substring(0, 10)}</div></div>');

    htmlDoc.write('<div class="kpi-grid">');
    htmlDoc.write('<div class="kpi"><div class="kpi-title">PERIODO ($nombrePeriodoActivo)</div><div class="kpi-val">MXN ${invMesAct.toStringAsFixed(2)}</div><div class="kpi-sub">Riesgo/Bodega: MXN ${rsgMesAct.toStringAsFixed(2)} (${pctRsgMesAct.toStringAsFixed(1)}%) • MoM: $varMoM</div></div>');
    htmlDoc.write('<div class="kpi"><div class="kpi-title">PROYECCIÓN 3 MESES SIGUIENTES</div><div class="kpi-val">MXN ${sumaProy3M.toStringAsFixed(2)}</div><div class="kpi-sub">Siguientes +30, +60 y +90 días</div></div>');
    htmlDoc.write('<div class="kpi"><div class="kpi-title">ACUMULADO ANUAL ($anioAnalizado)</div><div class="kpi-val">MXN ${invY0.toStringAsFixed(2)}</div><div class="kpi-sub">Rescate: ${rescateY0.toStringAsFixed(1)}% (Meta 75%) • YoY: $varYoY</div></div>');
    htmlDoc.write('<div class="kpi"><div class="kpi-title">CAPITAL POR ÁREA ($nombrePeriodoActivo)</div><div class="kpi-val">Piso: MXN ${capPiso.toStringAsFixed(0)}</div><div class="kpi-sub">Bodega: MXN ${capBodega.toStringAsFixed(0)} • Display: MXN ${capDisplay.toStringAsFixed(0)}</div></div>');
    htmlDoc.write('</div>');

    htmlDoc.write('<h2>1. Proyección de los 3 Meses Siguientes a $nombrePeriodoActivo (+30 / +60 / +90 Días)</h2>');
    htmlDoc.write('<table><thead><tr><th>Mes Proyectado</th><th>Horizonte</th><th>Capital por Vencer</th><th>Piezas</th><th>Lotes</th></tr></thead><tbody>${sbProy.toString()}</tbody></table>');

    htmlDoc.write('<h2>2. Top 10 SKUs de Mayor Valor en $nombrePeriodoActivo (Pareto 80/20)</h2>');
    htmlDoc.write('<table><thead><tr><th>SKU</th><th>Marca</th><th>Descripción</th><th>Ubicación</th><th>Días / Pzas</th><th>Valor Lote</th></tr></thead><tbody>${sbTopSkus.toString()}</tbody></table>');

    htmlDoc.write('<h2>3. Matriz de Proveedores en Riesgo y Desviación ($nombrePeriodoActivo)</h2>');
    htmlDoc.write('<table><thead><tr><th>Proveedor</th><th>Inventario Total</th><th>Riesgo / Bodega</th><th>Piezas</th><th>% Riesgo (% Inv)</th><th>Desviación vs Media</th></tr></thead><tbody>${filasRubroHtml(listaProvs)}</tbody></table>');

    htmlDoc.write('<h2>4. Matriz de Grupos de Artículos en Riesgo y Desviación ($nombrePeriodoActivo)</h2>');
    htmlDoc.write('<table><thead><tr><th>Grupo de Artículos</th><th>Inventario Total</th><th>Riesgo / Bodega</th><th>Piezas</th><th>% Riesgo (% Inv)</th><th>Desviación vs Media</th></tr></thead><tbody>${filasRubroHtml(listaGrupos)}</tbody></table>');

    htmlDoc.write('<h2>5. Matriz de Marcas en Riesgo y Desviación ($nombrePeriodoActivo)</h2>');
    htmlDoc.write('<table><thead><tr><th>Marca</th><th>Inventario Total</th><th>Riesgo / Bodega</th><th>Piezas</th><th>% Riesgo (% Inv)</th><th>Desviación vs Media</th></tr></thead><tbody>${filasRubroHtml(listaMarcas)}</tbody></table>');

    htmlDoc.write('<script>setTimeout(function(){ window.print(); }, 500);</script></body></html>');

    final bytes = utf8.encode(htmlDoc.toString());
    final blob = html.Blob([bytes], 'text/html;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.window.open(url, '_blank');
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

  Widget _resumenMiniRubro(String titulo, List<Map<String, dynamic>> items, double totalInv, Color color) {
    int conRiesgo = items.where((e) => (e['riesgo'] as double) > 0).length;
    String topNombre = items.isNotEmpty ? items.first['nombre'].toString() : 'Ninguno';
    double topPctRiesgo = items.isNotEmpty ? (items.first['pctRiesgo'] as double) : 0.0;
    double topDesv = items.isNotEmpty ? (items.first['desviacion'] as double) : 0.0;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10.5)),
            const SizedBox(height: 3),
            Text('$conRiesgo de ${items.length} en riesgo/bod.', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5)),
            const SizedBox(height: 2),
            Text(
              'Top: $topNombre',
              style: const TextStyle(color: Colors.white70, fontSize: 9.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Riesgo: ${topPctRiesgo.toStringAsFixed(0)}% (Desv ${topDesv >= 0 ? "+" : ""}${topDesv.toStringAsFixed(0)}%)',
              style: TextStyle(
                color: topDesv > 0 ? Colors.redAccent : Colors.greenAccent,
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirSeccionRubro({
    required String titulo,
    required IconData icono,
    required Color colorTema,
    required List<Map<String, dynamic>> lista,
    required double totalInventarioPeriodo,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorTema.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: colorTema, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(fontSize: 13, color: colorTema, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${lista.length} activos',
                style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 14),
          if (lista.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Text('¡Sin registros con vencimientos en este periodo!', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
              ),
            )
          else
            ...lista.take(15).map((item) {
              double tot = item['total'] as double;
              double rsg = item['riesgo'] as double;
              double pctRiesgo = item['pctRiesgo'] as double;
              double pctPart = item['pctParticipacion'] as double;
              double desv = item['desviacion'] as double;
              int pzas = item['pzas'] as int;
              double barValue = totalInventarioPeriodo > 0 ? (tot / totalInventarioPeriodo).clamp(0.0, 1.0) : 0.0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item['nombre'].toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          'Total: MXN ${tot.toStringAsFixed(2)} ($pzas pz)',
                          style: TextStyle(color: colorTema, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'En riesgo / Bodega: MXN ${rsg.toStringAsFixed(2)} (${pctRiesgo.toStringAsFixed(1)}%)',
                          style: TextStyle(
                            color: rsg > 0 ? Colors.redAccent : Colors.greenAccent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Peso Inv: ${pctPart.toStringAsFixed(1)}% • Desv: ${desv >= 0 ? "+" : ""}${desv.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: desv > 5 ? Colors.orangeAccent : Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: barValue,
                      backgroundColor: Colors.white10,
                      color: rsg > 0 ? Colors.redAccent : colorTema,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int anioHoy = DateTime.now().year;
    List<int> ultimos3Anios = [anioHoy, anioHoy - 1, anioHoy - 2];
    if (!ultimos3Anios.contains(_anioAcumulado)) {
      _anioAcumulado = anioHoy;
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _resumenStream,
      builder: (context, resSnap) {
        Map<String, dynamic> todosPeriodos = {};
        Map<String, dynamic> diagOp = {};
        Map<int, Map<String, dynamic>> tratamientosPorAnio = {};

        if (resSnap.hasData) {
          for (var doc in resSnap.data!.docs) {
            if (doc.id == 'empaquetado_inventario') {
              var dataEmp = doc.data() as Map<String, dynamic>;
              todosPeriodos = Map<String, dynamic>.from((dataEmp['periodos'] ?? {}) as Map);
              diagOp = Map<String, dynamic>.from((dataEmp['diagnostico_operativo'] ?? {}) as Map);
            } else {
              int? anioDoc = int.tryParse(doc.id);
              if (anioDoc != null) {
                tratamientosPorAnio[anioDoc] = doc.data() as Map<String, dynamic>;
              }
            }
          }
        }

        String keyPeriodo = _vistaMensual
            ? 'M_${_mesSeleccionado.year}_${_mesSeleccionado.month}'
            : 'A_$_anioAcumulado';

        var datosP = Map<String, dynamic>.from((todosPeriodos[keyPeriodo] ?? {}) as Map);
        double totalRiesgo = double.tryParse((datosP['total'] ?? 0).toString()) ?? 0.0;
        double valorSano = double.tryParse((datosP['sano'] ?? 0).toString()) ?? 0.0;
        double valorProximo = double.tryParse((datosP['proximo'] ?? 0).toString()) ?? 0.0;
        double valorCritico = double.tryParse((datosP['critico'] ?? 0).toString()) ?? 0.0;
        double valorCaducado = double.tryParse((datosP['caducado'] ?? 0).toString()) ?? 0.0;
        double montoEnRiesgoOBodega = double.tryParse((datosP['riesgo'] ?? 0).toString()) ?? 0.0;
        double pctGlobalEnRiesgo = totalRiesgo > 0 ? (montoEnRiesgoOBodega / totalRiesgo) * 100.0 : 0.0;

        double capPisoPeriodo = double.tryParse((datosP['capPiso'] ?? 0).toString()) ?? 0.0;
        double capBodegaPeriodo = double.tryParse((datosP['capBodega'] ?? 0).toString()) ?? 0.0;

        var tratPeriodo = _obtenerTratamientosDePeriodo(
          tratamientosPorAnio,
          mensual: _vistaMensual,
          anio: _vistaMensual ? _mesSeleccionado.year : _anioAcumulado,
          mes: _mesSeleccionado.month,
        );
        double montoDevolucion = tratPeriodo['dev']!;
        double montoPromo = tratPeriodo['promo']!;
        double montoMerma = tratPeriodo['merma']!;
        int pzasDevolucion = tratPeriodo['pzasDev']!.round();
        int pzasPromo = tratPeriodo['pzasPromo']!.round();
        int pzasMerma = tratPeriodo['pzasMerma']!.round();
        double totalGestionado = tratPeriodo['total']!;

        var proveedoresOrdenados = _procesarListaRubro(
          datosP['proveedores'] as Map<String, dynamic>?,
          totalRiesgo,
          pctGlobalEnRiesgo,
        );
        var gruposOrdenados = _procesarListaRubro(
          datosP['grupos'] as Map<String, dynamic>?,
          totalRiesgo,
          pctGlobalEnRiesgo,
        );
        var marcasOrdenadas = _procesarListaRubro(
          datosP['marcas'] as Map<String, dynamic>?,
          totalRiesgo,
          pctGlobalEnRiesgo,
        );

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
              titleStyle: TextStyle(fontSize: tocado ? 13 : 9, fontWeight: FontWeight.bold, color: color == Colors.redAccent ? Colors.white : Colors.black),
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
            : 'Acumulado $_anioAcumulado (Ene-Dic)';

        return Scaffold(
          appBar: AppBar(
            title: const Text('Salud e Impacto Financiero', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9.0, horizontal: 2.0),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.auto_awesome, size: 14),
                  label: const Text('DIAGNÓSTICO IA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                  onPressed: () => _mostrarDiagnosticoEjecutivoIA(diagOp, tratamientosPorAnio),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9.0, horizontal: 2.0),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.psychology, size: 15),
                  label: const Text('IA PROFUNDA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                  onPressed: () => _mostrarDiagnosticoProfundoIA(todosPeriodos, tratamientosPorAnio, diagOp),
                ),
              ),
              IconButton(
                icon: _sincronizando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber))
                    : const Icon(Icons.sync, color: Colors.amber, size: 20),
                tooltip: 'Actualizar paquete de datos en la BD',
                onPressed: _sincronizando ? null : () => _reconstruirResumenYEmpaquetado(silencioso: false),
              ),
            ],
          ),
          body: !resSnap.hasData
              ? const Center(child: CircularProgressIndicator(color: Colors.amber))
              : Column(
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
                                    backgroundColor: _vistaMensual ? Colors.amber : Colors.white10,
                                    foregroundColor: _vistaMensual ? Colors.black : Colors.white70,
                                  ),
                                  icon: const Icon(Icons.calendar_month, size: 16),
                                  label: const Text('VISTA MENSUAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                  onPressed: () => setState(() => _vistaMensual = true),
                                ),
                              ),
                              const SizedBox(width: 8),
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
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (!_vistaMensual)
                            Row(
                              children: ultimos3Anios.map((anio) {
                                bool sel = _anioAcumulado == anio;
                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: sel ? Colors.amber.withOpacity(0.22) : Colors.white10,
                                        side: BorderSide(color: sel ? Colors.amber : Colors.white24, width: sel ? 1.5 : 1),
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                      ),
                                      onPressed: () => setState(() => _anioAcumulado = anio),
                                      child: Text(
                                        '$anio',
                                        style: TextStyle(
                                          color: sel ? Colors.amberAccent : Colors.white70,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.amber.withOpacity(0.5)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(icon: const Icon(Icons.chevron_left, color: Colors.amber), onPressed: () => _cambiarMes(-1)),
                                  Text(
                                    '${_meses[_mesSeleccionado.month - 1].toUpperCase()} ${_mesSeleccionado.year}',
                                    style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.2),
                                  ),
                                  IconButton(icon: const Icon(Icons.chevron_right, color: Colors.amber), onPressed: () => _cambiarMes(1)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 5,
                                        child: SizedBox(
                                          height: 150,
                                          child: rebanadas.isEmpty
                                              ? Center(
                                                  child: Text(
                                                    "Sin vencimientos en\n$etiquetaPeriodo",
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                                                  ),
                                                )
                                              : PieChart(
                                                  PieChartData(
                                                    sectionsSpace: 3,
                                                    centerSpaceRadius: 26,
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
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        flex: 6,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _vistaMensual ? 'Inventario del Mes ($etiquetaPeriodo)' : 'Inventario Total ($etiquetaPeriodo)',
                                              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'MXN ${totalRiesgo.toStringAsFixed(2)}',
                                              style: const TextStyle(color: Colors.amberAccent, fontSize: 20, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '🏪 Piso: MXN ${capPisoPeriodo.toStringAsFixed(0)}  •  📦 Bodega: MXN ${capBodegaPeriodo.toStringAsFixed(0)}',
                                              style: const TextStyle(color: Colors.cyanAccent, fontSize: 10.5, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 6),
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.redAccent.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Riesgo / Bodega: MXN ${montoEnRiesgoOBodega.toStringAsFixed(2)}',
                                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Índice / Desviación en Riesgo: ${pctGlobalEnRiesgo.toStringAsFixed(1)}%',
                                                    style: const TextStyle(color: Colors.yellowAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      _resumenMiniRubro('🏢 Proveedores', proveedoresOrdenados, totalRiesgo, Colors.amber),
                                      const SizedBox(width: 6),
                                      _resumenMiniRubro('📦 Grupos Art.', gruposOrdenados, totalRiesgo, Colors.cyanAccent),
                                      const SizedBox(width: 6),
                                      _resumenMiniRubro('🏷️ Marcas', marcasOrdenadas, totalRiesgo, Colors.pinkAccent),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
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
                                      const Text('Participación de Tratamientos', style: TextStyle(fontSize: 13, color: Colors.amber, fontWeight: FontWeight.bold)),
                                      Text('Total: MXN ${totalGestionado.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  const Divider(color: Colors.white24, height: 14),
                                  _barraTratamiento('📦 Devolución a Proveedor', montoDevolucion, pzasDevolucion, totalGestionado, Colors.cyanAccent),
                                  _barraTratamiento('🏷️ Rescatado en Promoción', montoPromo, pzasPromo, totalGestionado, Colors.greenAccent),
                                  _barraTratamiento('📉 Merma / Destrucción', montoMerma, pzasMerma, totalGestionado, Colors.redAccent),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                _chipRubro(0, '📊 Los 3 Rubros'),
                                const SizedBox(width: 6),
                                _chipRubro(1, '🏢 Proveedor'),
                                const SizedBox(width: 6),
                                _chipRubro(2, '📦 Grupo Art.'),
                                const SizedBox(width: 6),
                                _chipRubro(3, '🏷️ Marca'),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_rubroSeleccionado == 0 || _rubroSeleccionado == 1)
                              _construirSeccionRubro(
                                titulo: 'Proveedores en Riesgo ($etiquetaPeriodo)',
                                icono: Icons.business,
                                colorTema: Colors.amber,
                                lista: proveedoresOrdenados,
                                totalInventarioPeriodo: totalRiesgo,
                              ),
                            if (_rubroSeleccionado == 0 || _rubroSeleccionado == 2)
                              _construirSeccionRubro(
                                titulo: 'Grupos de Artículos en Riesgo ($etiquetaPeriodo)',
                                icono: Icons.category,
                                colorTema: Colors.cyanAccent,
                                lista: gruposOrdenados,
                                totalInventarioPeriodo: totalRiesgo,
                              ),
                            if (_rubroSeleccionado == 0 || _rubroSeleccionado == 3)
                              _construirSeccionRubro(
                                titulo: 'Marcas en Riesgo ($etiquetaPeriodo)',
                                icono: Icons.sell,
                                colorTema: Colors.pinkAccent,
                                lista: marcasOrdenadas,
                                totalInventarioPeriodo: totalRiesgo,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _chipRubro(int index, String label) {
    bool activo = _rubroSeleccionado == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _rubroSeleccionado = index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: activo ? Colors.amber : Colors.white10,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: activo ? Colors.amberAccent : Colors.white24),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: activo ? Colors.black : Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
