import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class JerarquiaUbicacionHelper {
  static final Map<String, String> _cacheUpcPorSku = {};
  static bool _cargandoCacheUpc = false;
  static bool _cacheUpcListo = false;
  static final ValueNotifier<int> upcCacheVersion = ValueNotifier<int>(0);

  static Future<void> precargarCacheUpc() async {
    if (_cacheUpcListo || _cargandoCacheUpc) return;
    _cargandoCacheUpc = true;
    try {
      var snap = await FirebaseFirestore.instance.collection('maestro_productos').get();
      for (var doc in snap.docs) {
        var d = doc.data();
        String s = (d['sku'] ?? '').toString().trim();
        String e = (d['ean'] ?? '').toString().trim();
        if (s.isNotEmpty && e.isNotEmpty && e != '0' && e != 'NaN') {
          _cacheUpcPorSku[s] = e;
        }
      }
      _cacheUpcListo = true;
      upcCacheVersion.value++;
    } catch (_) {
    } finally {
      _cargandoCacheUpc = false;
    }
  }

  static String obtenerUpcVisual(Map<String, dynamic>? d) {
    if (!_cacheUpcListo && !_cargandoCacheUpc) {
      precargarCacheUpc();
    }
    if (d == null) return 'ND';
    String ean = (d['ean'] ?? '').toString().trim();
    if (ean.isNotEmpty && ean != '0' && ean != 'NaN') return ean;

    String sku = (d['sku'] ?? '').toString().trim();
    if (sku.isNotEmpty && _cacheUpcPorSku.containsKey(sku)) {
      return _cacheUpcPorSku[sku]!;
    }

    String orig = (d['codigoOriginalCapturado'] ?? '').toString().trim();
    if (orig.length >= 8 && orig != sku) return orig;
    if (sku.length >= 11) return sku;
    return 'SIN UPC';
  }

  // Normaliza texto quitando acentos, diéresis, signos y exceso de espacios
  static String normalizarTextoBusqueda(String input) {
    if (input.isEmpty) return '';
    String s = input.toLowerCase();
    const mapaAcentos = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
      'ñ': 'n',
    };
    mapaAcentos.forEach((k, v) {
      s = s.replaceAll(k, v);
    });
    s = s.replaceAll(RegExp(r'[^a-z0-9\s<>]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static bool coincideBusquedaInteligente(String consultaRaw, List<String?> camposDocumento) {
    String q = normalizarTextoBusqueda(consultaRaw).replaceAll(RegExp(r'[<>]'), ' ');
    if (q.trim().isEmpty) return true;
    List<String> palabras = q.split(' ').where((w) => w.isNotEmpty).toList();
    String acumulado = camposDocumento
        .map((c) => normalizarTextoBusqueda(c ?? ''))
        .join(' ');
    for (String p in palabras) {
      if (!acumulado.contains(p)) return false;
    }
    return true;
  }

  // IA 1: PREDICTOR DE RIESGO DE NO VENTA (SOBRESTOCK VS DÍAS PARA VENCER)
  static Map<String, dynamic>? analizarRiesgoSobrestockIA(Map<String, dynamic> d) {
    Timestamp? ts = d['fechaCaducidad'];
    if (ts == null) return null;
    int dias = ts.toDate().difference(DateTime.now()).inDays;
    int cant = (d['cantidad'] ?? 0) as int;

    if (cant <= 1 || dias <= 0 || dias > 100) return null;

    double ventaDiaria = double.tryParse((d['ventaDiariaPromedio'] ?? 0).toString()) ?? 0.0;
    if (ventaDiaria > 0) {
      double diasNecesarios = cant / ventaDiaria;
      if (diasNecesarios > dias * 1.15) {
        int sobrantes = (cant - (ventaDiaria * dias).floor()).clamp(1, cant);
        return {
          'enRiesgo': true,
          'pzasEnRiesgo': sobrantes,
          'detalle': '🧠 IA SOBRESTOCK: Al ritmo de venta (${ventaDiaria.toStringAsFixed(1)}/día), sobrarán ~$sobrantes pzas al vencer.',
        };
      }
    }

    // Heurística preventiva cuando un lote acumula demasiado volumen para su ventana de vida
    bool volumenAlto = (dias <= 20 && cant >= 6) ||
        (dias <= 35 && cant >= 10) ||
        (dias <= 60 && cant >= 18) ||
        (dias <= 90 && cant >= 30);

    if (volumenAlto) {
      double ventaSemanalRequerida = (cant / dias) * 7.0;
      if (ventaSemanalRequerida >= 2.0) {
        return {
          'enRiesgo': true,
          'pzasEnRiesgo': (cant * 0.5).round(),
          'detalle': '🧠 IA SOBRESTOCK: $cant pzas para $dias días (Requiere vender ${ventaSemanalRequerida.toStringAsFixed(1)} pzas/sem). Priorizar exhibición.',
        };
      }
    }
    return null;
  }

  // IA 2: AUTO-RECOMENDADOR DE INSTRUCCIÓN CORPORATIVA
  static Map<String, String> recomendarInstruccionCorporativaIA(Map<String, dynamic> d) {
    Timestamp? ts = d['fechaCaducidad'];
    int dias = ts != null ? ts.toDate().difference(DateTime.now()).inDays : 30;
    int cant = (d['cantidad'] ?? 1) as int;
    String gpo = (d['nombreGpoArticulos'] ?? '').toString().toUpperCase();
    String desc = (d['descripcion'] ?? '').toString().toUpperCase();
    String prov = (d['nombreProveedor'] ?? '').toString().toUpperCase();

    if (desc.contains('ARTÍCULO NUEVO') || prov.contains('SIN MATCH')) {
      return {
        'comentario': 'SKU INEXISTENTE',
        'razon': 'Lote sin match en catálogo SAP',
      };
    }
    if (gpo.contains('VINO') || gpo.contains('LICOR') || desc.contains('VINO') || desc.contains('LICOR') || desc.contains('SAKE') || desc.contains('CERVEZA')) {
      return {
        'comentario': 'REVISAR CON EQUIPO COMERCIAL DE VINOS Y LICORES',
        'razon': 'Categoría Vinos y Licores detectada',
      };
    }
    if (dias < 0) {
      return {
        'comentario': 'MERMAR YA QUE NO SE COMPARTIÓ EN LAS FECHAS CORRECTAS',
        'razon': 'Lote ya vencido ($dias días)',
      };
    }
    if (dias <= 15) {
      return {
        'comentario': '15 DÍAS ANTES DE CADUCAR, PONER EL 50% DE DESCUENTO; SI NO SE VENDE, SE DA DE BAJA',
        'razon': 'Ventana crítica ≤ 15 días ($dias d)',
      };
    }
    if (dias <= 25 && cant >= 10) {
      return {
        'comentario': 'PRODUCTO DE TEMPORADA, APLICAR EL 50% DE DESCUENTO',
        'razon': 'Volumen alto ($cant pzas) con $dias días restantes',
      };
    }
    if (gpo.contains('DULCE') || gpo.contains('CONFITERIA') || gpo.contains('CHOCOLAT') || desc.contains('GOMITA') || desc.contains('POCKY') || desc.contains('GALLETA')) {
      if (dias <= 30) {
        return {
          'comentario': 'GESTIONAR CAMBIO FÍSICO CON PROVEEDOR. EN CASO DE NO OBTENER RESPUESTA, DESTRUCCIÓN CON EVIDENCIA POR CORREO AL PROVEEDOR Y EQUIPO COMERCIAL',
          'razon': 'Dulcería / Confitería en ventana de 30 días',
        };
      }
      return {
        'comentario': 'REVISAR CON EQUIPO COMERCIAL DE DULCERÍA',
        'razon': 'Categoría Dulcería / Importados ($dias d)',
      };
    }
    if (dias <= 35) {
      return {
        'comentario': 'REVISAR CON PROVEEDOR SI PROCEDE CAMBIO FÍSICO O DEVOLUCIÓN CON DESTRUCCIÓN',
        'razon': 'Ventana preventiva de negociación ($dias d)',
      };
    }
    return {
      'comentario': 'PRODUCTO DE TEMPORADA, APLICAR EL 40% DE DESCUENTO',
      'razon': 'Desplazamiento preventivo ($dias d • $cant pzas)',
    };
  }

  // IA 4: BUSCADOR POR LENGUAJE NATURAL (Ej. "comercial toyo en bodega enero", "menos de 20 dias en piso")
  static const Map<String, int> _mesesLenguajeNatural = {
    'enero': 1, 'febrero': 2, 'marzo': 3, 'abril': 4,
    'mayo': 5, 'junio': 6, 'julio': 7, 'agosto': 8,
    'septiembre': 9, 'octubre': 10, 'noviembre': 11, 'diciembre': 12,
  };

  static bool evaluarConsultaLenguajeNaturalIA(String consultaRaw, Map<String, dynamic> d) {
    String q = normalizarTextoBusqueda(consultaRaw);
    if (q.isEmpty) return true;

    Timestamp? ts = d['fechaCaducidad'] ?? d['fechaGeneracion'];
    DateTime? cad = ts?.toDate();
    int dias = cad != null ? cad.difference(DateTime.now()).inDays : 999;

    // 1. Detectar expresiones de límite máximo de días: "menos de 20 dias", "menor a 15 dias", "< 30 dias"
    final regMenosDias = RegExp(r'(?:menos de|menor a|menores a|maximo|hasta|<|<=)\s*(\d+)\s*(?:dias|dia|d)?\b');
    var matchMenos = regMenosDias.firstMatch(q);
    if (matchMenos != null) {
      int lim = int.tryParse(matchMenos.group(1)!) ?? 999;
      if (dias > lim) return false;
      q = q.replaceFirst(regMenosDias, ' ').trim();
    }

    // 2. Detectar expresiones de límite mínimo de días: "mas de 30 dias", "mayor a 45 dias", "> 60 dias"
    final regMasDias = RegExp(r'(?:mas de|mayor a|mayores a|minimo|>|>=)\s*(\d+)\s*(?:dias|dia|d)?\b');
    var matchMas = regMasDias.firstMatch(q);
    if (matchMas != null) {
      int lim = int.tryParse(matchMas.group(1)!) ?? 0;
      if (dias < lim) return false;
      q = q.replaceFirst(regMasDias, ' ').trim();
    }

    // 3. Palabras clave de estado operativo
    List<String> tokens = q.replaceAll(RegExp(r'[<>]'), ' ').split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    List<String> tokensRestantes = [];

    const stopwords = {
      'en', 'de', 'del', 'con', 'que', 'vencen', 'vence', 'caducan', 'caduca',
      'para', 'el', 'la', 'los', 'las', 'un', 'una', 'lotes', 'lote',
      'productos', 'producto', 'articulos', 'dias', 'dia', 'mes', 'por'
    };

    for (String t in tokens) {
      if (t == 'caducado' || t == 'caducados' || t == 'vencido' || t == 'vencidos') {
        if (dias >= 0) return false;
        continue;
      }
      if (t == 'critico' || t == 'criticos') {
        if (dias < 0 || dias > 15) return false;
        continue;
      }
      if (t == 'sobrestock') {
        if (analizarRiesgoSobrestockIA(d) == null) return false;
        continue;
      }
      if (t == 'promocion' || t == 'saldado') {
        if (d['enPromocion'] != true) return false;
        continue;
      }
      if (t == 'temporal' || t == 'temporales') {
        if (d['edicionTemporal'] != true) return false;
        continue;
      }
      if (_mesesLenguajeNatural.containsKey(t)) {
        if (cad == null || cad.month != _mesesLenguajeNatural[t]) return false;
        continue;
      }
      if (stopwords.contains(t)) continue;
      tokensRestantes.add(t);
    }

    if (tokensRestantes.isEmpty) return true;

    String upc = obtenerUpcVisual(d);
    String acumulado = normalizarTextoBusqueda(
      '${d['descripcion'] ?? ''} ${d['sku'] ?? ''} ${d['ean'] ?? ''} $upc ${d['nombreProveedor'] ?? ''} ${d['nombreGpoArticulos'] ?? ''} ${d['ubicacion'] ?? ''} ${d['mensaje'] ?? ''}',
    );

    for (String p in tokensRestantes) {
      if (!acumulado.contains(p)) return false;
    }
    return true;
  }

  static const Map<String, List<String>> _diccionarioSemanticoSAP = {
    'tea': ['te', 'beb', 'infusion'],
    'te': ['tea', 'beb', 'infusion'],
    'green': ['verde', 'vde', 'matcha'],
    'verde': ['vde', 'green', 'matcha'],
    'black': ['negro', 'neg'],
    'milk': ['leche', 'lch'],
    'strawberry': ['fresa', 'frsa'],
    'fresa': ['frsa', 'strawberry'],
    'chocolate': ['choc', 'choco', 'cacao'],
    'choc': ['chocolate', 'choco'],
    'cookie': ['galleta', 'gall', 'biscuit'],
    'cookies': ['galleta', 'gall', 'biscuit'],
    'galleta': ['gall', 'cookie'],
    'galletas': ['gall', 'cookie'],
    'cheese': ['queso', 'qso'],
    'queso': ['qso', 'cheese'],
    'spicy': ['picante', 'pic', 'hot', 'chile'],
    'hot': ['picante', 'pic', 'spicy'],
    'chicken': ['pollo', 'pll'],
    'beef': ['res', 'carne'],
    'shrimp': ['camaron', 'cam'],
    'noodle': ['ramen', 'sopa', 'pasta', 'fideo'],
    'noodles': ['ramen', 'sopa', 'pasta', 'fideo'],
    'ramen': ['sopa', 'pasta', 'noodle', 'bowl', 'cup'],
    'sauce': ['salsa', 'sls'],
    'salsa': ['sls', 'sauce'],
    'drink': ['bebida', 'beb', 'refresco', 'jugo'],
    'bebida': ['beb', 'drink', 'jugo'],
    'water': ['agua', 'mineral'],
    'coffee': ['cafe', 'caf', 'soluble', 'liofilizado'],
    'cafe': ['caf', 'coffee'],
    'candy': ['dulce', 'dlc', 'gomita', 'caramelo'],
    'gummy': ['gomita', 'gomitas', 'dulce'],
    'gomitas': ['gomita', 'gummy', 'dulce'],
    'chips': ['fritura', 'botana', 'papas', 'churro'],
    'snack': ['botana', 'fritura'],
    'peanut': ['cacahuate', 'cacahuates'],
    'almond': ['almendra', 'almendras'],
    'rice': ['arroz', 'arz'],
    'seaweed': ['alga', 'nori'],
    'japanese': ['japones', 'japon'],
    'korean': ['coreano', 'coreana', 'corea'],
  };

  static double _similitudBigramas(String a, String b) {
    if (a == b) return 1.0;
    if (a.length < 2 || b.length < 2) return 0.0;
    Set<String> bgA = {};
    Set<String> bgB = {};
    for (int i = 0; i < a.length - 1; i++) {
      bgA.add(a.substring(i, i + 2));
    }
    for (int i = 0; i < b.length - 1; i++) {
      bgB.add(b.substring(i, i + 2));
    }
    int interseccion = bgA.intersection(bgB).length;
    return (2.0 * interseccion) / (bgA.length + bgB.length);
  }

  static List<Map<String, dynamic>> buscarSugerenciasSemanticasIA(
    String consultaComercial,
    Iterable<Map<String, dynamic>> catalogoCompleto,
  ) {
    String qNorm = normalizarTextoBusqueda(consultaComercial);
    if (qNorm.isEmpty) return [];

    List<String> tokensOriginales = qNorm
        .split(' ')
        .where((t) => t.length >= 2 && !['de', 'el', 'la', 'los', 'las', 'con', 'en', 'por', 'para', 'del', 'the', 'with', 'and'].contains(t))
        .toList();

    if (tokensOriginales.isEmpty) return [];

    Set<String> numerosGramaje = {};
    for (var m in RegExp(r'\d{2,4}').allMatches(consultaComercial)) {
      numerosGramaje.add(m.group(0)!);
    }

    List<Map<String, dynamic>> resultadosConScore = [];

    for (var prod in catalogoCompleto) {
      if (prod['esTemporal'] == true) continue;
      String desc = (prod['descripcion'] ?? '').toString();
      String prov = (prod['nombreProveedor'] ?? '').toString();
      String gpo = (prod['nombreGpoArticulos'] ?? '').toString();
      String sku = (prod['sku'] ?? '').toString();

      String textoProdNorm = normalizarTextoBusqueda('$desc $prov $gpo $sku');
      List<String> tokensProd = textoProdNorm.split(' ').where((t) => t.isNotEmpty).toList();

      double puntos = 0.0;
      double maxPuntosPosibles = tokensOriginales.length * 10.0;
      List<String> razones = [];

      for (String tokenQ in tokensOriginales) {
        if (tokensProd.any((tp) => tp == tokenQ || tp.startsWith(tokenQ) || tokenQ.startsWith(tp) && tp.length >= 3)) {
          puntos += 10.0;
          razones.add(tokenQ.toUpperCase());
          continue;
        }

        List<String> sinonimos = _diccionarioSemanticoSAP[tokenQ] ?? [];
        bool matchSinonimo = false;
        for (String sin in sinonimos) {
          if (tokensProd.any((tp) => tp == sin || tp.startsWith(sin))) {
            puntos += 8.5;
            razones.add('$tokenQ➔${sin.toUpperCase()}');
            matchSinonimo = true;
            break;
          }
        }
        if (matchSinonimo) continue;

        double mejorSim = 0.0;
        for (String tp in tokensProd) {
          double sim = _similitudBigramas(tokenQ, tp);
          if (sim > mejorSim) mejorSim = sim;
        }
        if (mejorSim >= 0.55) {
          puntos += 7.0 * mejorSim;
        }
      }

      for (String numG in numerosGramaje) {
        if (desc.contains('.$numG') || textoProdNorm.contains(numG)) {
          puntos += 4.5;
          razones.add('${numG}g/ml');
        }
      }

      if (puntos > 0) {
        int porcentaje = ((puntos / (maxPuntosPosibles + (numerosGramaje.isNotEmpty ? 4.5 : 0.0))) * 100).round().clamp(15, 99);
        if (porcentaje >= 30 || puntos >= 7.0) {
          var copia = Map<String, dynamic>.from(prod);
          copia['scoreIA'] = porcentaje;
          copia['puntosRaw'] = puntos;
          copia['razonIA'] = razones.isNotEmpty ? razones.take(4).join(' • ') : 'Similitud de nombre';
          resultadosConScore.add(copia);
        }
      }
    }

    resultadosConScore.sort((a, b) {
      double pA = (a['puntosRaw'] as double?) ?? 0.0;
      double pB = (b['puntosRaw'] as double?) ?? 0.0;
      return pB.compareTo(pA);
    });

    return resultadosConScore.take(15).toList();
  }

  static List<String> generarVariantesCodigo(String codigoRaw) {
    String limpio = codigoRaw.trim();
    if (limpio.isEmpty) return [];
    String sinCeros = limpio.replaceFirst(RegExp(r'^0+'), '');
    return <String>{
      limpio,
      if (sinCeros.isNotEmpty) sinCeros,
      if (sinCeros.isNotEmpty) '0$sinCeros',
      if (sinCeros.isNotEmpty) '00$sinCeros',
    }.toList();
  }

  static Future<Map<String, dynamic>?> buscarProductoMaestro(String codigoRaw, {bool soloOficialSAP = false}) async {
    List<String> candidatos = generarVariantesCodigo(codigoRaw);
    if (candidatos.isEmpty) return null;
    var col = FirebaseFirestore.instance.collection('maestro_productos');

    for (String cand in candidatos) {
      var doc = await col.doc(cand).get();
      if (doc.exists && doc.data() != null) {
        var d = doc.data()!;
        if (soloOficialSAP && d['esTemporal'] == true) continue;
        return d;
      }
    }
    for (String cand in candidatos) {
      var qEan = await col.where('ean', isEqualTo: cand).limit(1).get();
      if (qEan.docs.isNotEmpty) {
        var d = qEan.docs.first.data();
        if (soloOficialSAP && d['esTemporal'] == true) continue;
        return d;
      }
    }
    for (String cand in candidatos) {
      var qSku = await col.where('sku', isEqualTo: cand).limit(1).get();
      if (qSku.docs.isNotEmpty) {
        var d = qSku.docs.first.data();
        if (soloOficialSAP && d['esTemporal'] == true) continue;
        return d;
      }
    }
    return null;
  }

  static Future<int> actualizarArticuloEnTodasLasInstancias({
    required String idTiendaGlobal,
    required String codigoAnterior,
    required String nuevoSku,
    String? nuevoEan,
    String? nuevaDescripcion,
    Map<String, dynamic>? datosMaestros,
    String? usuarioActual,
  }) async {
    var db = FirebaseFirestore.instance;
    var refTienda = db.collection('tiendas').doc(idTiendaGlobal);

    String skuFinal = nuevoSku.trim();
    String codigoViejo = codigoAnterior.trim();

    bool esMatchOficialSAP = datosMaestros != null &&
        datosMaestros['esTemporal'] != true &&
        datosMaestros['nombreProveedor'] != null &&
        datosMaestros['nombreProveedor'] != 'POR ASIGNAR' &&
        datosMaestros['nombreProveedor'] != 'EDICIÓN TEMPORAL (PENDIENTE SAP)';

    String eanFinal = (nuevoEan != null && nuevoEan.trim().isNotEmpty)
        ? nuevoEan.trim()
        : (datosMaestros?['ean']?.toString().trim() ?? (codigoViejo.length >= 11 && codigoViejo != skuFinal ? codigoViejo : ''));

    if (skuFinal.isNotEmpty && eanFinal.isNotEmpty) {
      _cacheUpcPorSku[skuFinal] = eanFinal;
    }

    String descFinal = (esMatchOficialSAP && datosMaestros!['descripcion'] != null)
        ? datosMaestros['descripcion'].toString().trim()
        : ((nuevaDescripcion != null && nuevaDescripcion.trim().isNotEmpty && nuevaDescripcion.trim() != 'Artículo Nuevo')
            ? nuevaDescripcion.trim().toUpperCase()
            : (datosMaestros?['descripcion']?.toString().trim() ?? 'SIN NOMBRE'));

    WriteBatch batch = db.batch();
    int ops = 0;
    int lotesActualizados = 0;
    int totalPiezasAfectadas = 0;
    String primeraUbicacion = 'TIENDA';

    Future<void> checkBatch() async {
      ops++;
      if (ops >= 400) {
        await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    }

    Map<String, dynamic> fichaMaestra = {
      'sku': skuFinal,
      'ean': eanFinal,
      'descripcion': descFinal,
      'idProveedor': esMatchOficialSAP ? (datosMaestros!['idProveedor'] ?? 'ND') : 'TEMP',
      'nombreProveedor': esMatchOficialSAP ? (datosMaestros!['nombreProveedor'] ?? 'ND') : 'EDICIÓN TEMPORAL (PENDIENTE SAP)',
      'idCategoria': esMatchOficialSAP ? (datosMaestros!['idCategoria'] ?? 'ND') : 'TEMP',
      'nombreGpoArticulos': esMatchOficialSAP ? (datosMaestros!['nombreGpoArticulos'] ?? 'SIN GRUPO') : 'EDICIÓN TEMPORAL',
      'precioVenta': esMatchOficialSAP ? (datosMaestros!['precioVenta'] ?? '0') : '0',
      'oh': esMatchOficialSAP ? (datosMaestros!['oh'] ?? '0') : '0',
      'esTemporal': !esMatchOficialSAP,
      'codigoOriginalCapturado': codigoViejo,
    };

    if (skuFinal.isNotEmpty) {
      batch.set(db.collection('maestro_productos').doc(skuFinal), fichaMaestra, SetOptions(merge: true));
      await checkBatch();
    }
    if (eanFinal.isNotEmpty && eanFinal != '0') {
      batch.set(db.collection('maestro_productos').doc(eanFinal), fichaMaestra, SetOptions(merge: true));
      await checkBatch();
    }
    if (codigoViejo.isNotEmpty && codigoViejo != skuFinal && codigoViejo != eanFinal) {
      batch.set(db.collection('maestro_productos').doc(codigoViejo), fichaMaestra, SetOptions(merge: true));
      await checkBatch();
    }

    var invSnap = await refTienda.collection('inventario_activo').get();
    for (var doc in invSnap.docs) {
      var d = doc.data();
      String sDoc = (d['sku'] ?? '').toString().trim();
      String eDoc = (d['ean'] ?? '').toString().trim();
      String origDoc = (d['codigoOriginalCapturado'] ?? '').toString().trim();

      if (sDoc == codigoViejo ||
          (codigoViejo.isNotEmpty && eDoc == codigoViejo) ||
          (codigoViejo.isNotEmpty && origDoc == codigoViejo) ||
          sDoc == skuFinal) {
        String codigoSemilla = origDoc.isNotEmpty ? origDoc : (codigoViejo.isNotEmpty ? codigoViejo : sDoc);
        primeraUbicacion = (d['ubicacion'] ?? primeraUbicacion).toString();
        totalPiezasAfectadas += ((d['cantidad'] ?? 0) as int);

        Map<String, dynamic> cambios = {
          'sku': skuFinal,
          'descripcion': descFinal,
          'codigoOriginalCapturado': codigoSemilla,
          'edicionTemporal': !esMatchOficialSAP,
          'usuarioEdicionTemporal': usuarioActual ?? 'Colaborador',
          'fechaEdicionTemporal': FieldValue.serverTimestamp(),
          'misionArticuloNuevo': FieldValue.delete(),
        };
        if (eanFinal.isNotEmpty) cambios['ean'] = eanFinal;
        if (esMatchOficialSAP) {
          cambios['idProveedor'] = fichaMaestra['idProveedor'];
          cambios['nombreProveedor'] = fichaMaestra['nombreProveedor'];
          cambios['idCategoria'] = fichaMaestra['idCategoria'];
          cambios['nombreGpoArticulos'] = fichaMaestra['nombreGpoArticulos'];
          cambios['precioVenta'] = fichaMaestra['precioVenta'];
          cambios['oh'] = fichaMaestra['oh'];
        } else {
          cambios['nombreProveedor'] = 'EDICIÓN TEMPORAL (PENDIENTE SAP)';
        }
        batch.update(doc.reference, cambios);
        lotesActualizados++;
        await checkBatch();
      }
    }

    var misSnap = await refTienda.collection('misiones_auditoria').get();
    for (var mDoc in misSnap.docs) {
      var m = mDoc.data();
      String mSku = (m['sku'] ?? '').toString().trim();
      String mEan = (m['ean'] ?? '').toString().trim();
      String mOrig = (m['codigoOriginalCapturado'] ?? '').toString().trim();

      if (mSku == codigoViejo ||
          (codigoViejo.isNotEmpty && mEan == codigoViejo) ||
          (codigoViejo.isNotEmpty && mOrig == codigoViejo) ||
          mSku == skuFinal) {
        String msg = (m['mensaje'] ?? '').toString();
        bool esMisionArticuloNuevo = m['esArticuloNuevo'] == true || msg.contains('ARTÍCULO NUEVO');

        Map<String, dynamic> cambiosMision = {
          'sku': skuFinal,
          'descripcion': descFinal,
          'codigoOriginalCapturado': mOrig.isNotEmpty ? mOrig : codigoViejo,
          'edicionTemporal': !esMatchOficialSAP,
          if (eanFinal.isNotEmpty) 'ean': eanFinal,
          'nombreProveedor': fichaMaestra['nombreProveedor'],
          'nombreGpoArticulos': fichaMaestra['nombreGpoArticulos'],
        };

        if (esMisionArticuloNuevo && m['estado'] == 'pendiente') {
          cambiosMision['estado'] = 'completada';
          cambiosMision['completadaPor'] = '${usuarioActual ?? 'Colaborador'} (${esMatchOficialSAP ? 'Match SAP' : 'Edición Temporal'})';
          cambiosMision['accionRealizada'] = esMatchOficialSAP ? 'validacion_sap' : 'edicion_temporal';
        }

        batch.update(mDoc.reference, cambiosMision);
        await checkBatch();
      }
    }

    batch.set(refTienda.collection('historial_tratamientos').doc(), {
      'sku': skuFinal,
      'ean': eanFinal,
      'codigoOriginalCapturado': codigoViejo,
      'descripcion': descFinal,
      'nombreProveedor': fichaMaestra['nombreProveedor'],
      'nombreGpoArticulos': fichaMaestra['nombreGpoArticulos'],
      'ubicacion': lotesActualizados > 1 ? '$primeraUbicacion (+${lotesActualizados - 1} lotes)' : primeraUbicacion,
      'cantidadTratada': totalPiezasAfectadas > 0 ? totalPiezasAfectadas : 1,
      'motivo': esMatchOficialSAP
          ? '✅ Validación con Match Oficial SAP (Orig: $codigoViejo)'
          : '⏳ Edición Temporal en espera de SAP (Orig: $codigoViejo)',
      'costoTotal': 0.0,
      'fechaTratamiento': FieldValue.serverTimestamp(),
      'usuario': usuarioActual ?? 'Colaborador',
    });
    await checkBatch();

    if (ops > 0) await batch.commit();
    return lotesActualizados;
  }

  static List<String> descomponerRuta(String raw) {
    String limpia = raw.trim();
    if (limpia.isEmpty) return ['SIN UBICACIÓN'];

    List<String> partes = limpia.split('>').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (partes.isEmpty) return [limpia];

    String primero = partes.first.toUpperCase();
    for (String pref in ['PISO', 'BODEGA', 'DISPLAY']) {
      if (primero.startsWith('$pref ') && primero.length > pref.length + 1) {
        String resto = partes.first.substring(pref.length + 1).trim();
        return [pref, resto, ...partes.sublist(1)];
      }
    }
    return partes;
  }

  static String formatearRutaVisual(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'ND';
    return descomponerRuta(raw).join(' > ');
  }

  static int _prioridadArea(String area) {
    String u = area.toUpperCase().trim();
    if (u == 'PISO') return 0;
    if (u == 'BODEGA') return 1;
    if (u == 'DISPLAY') return 2;
    return 3;
  }

  static int _compararTextoNatural(String a, String b) {
    RegExp reg = RegExp(r'(\d+)|(\D+)');
    var mA = reg.allMatches(a.toUpperCase()).map((m) => m.group(0)!).toList();
    var mB = reg.allMatches(b.toUpperCase()).map((m) => m.group(0)!).toList();
    int len = mA.length < mB.length ? mA.length : mB.length;
    for (int i = 0; i < len; i++) {
      int? nA = int.tryParse(mA[i]);
      int? nB = int.tryParse(mB[i]);
      int cmp = (nA != null && nB != null) ? nA.compareTo(nB) : mA[i].compareTo(mB[i]);
      if (cmp != 0) return cmp;
    }
    return mA.length.compareTo(mB.length);
  }

  static int compararRutasJerarquicas(String rutaA, String rutaB) {
    List<String> nivA = descomponerRuta(rutaA);
    List<String> nivB = descomponerRuta(rutaB);

    int prioA = _prioridadArea(nivA.first);
    int prioB = _prioridadArea(nivB.first);
    if (prioA != prioB) return prioA.compareTo(prioB);

    int minLen = nivA.length < nivB.length ? nivA.length : nivB.length;
    for (int i = 0; i < minLen; i++) {
      int cmp = _compararTextoNatural(nivA[i], nivB[i]);
      if (cmp != 0) return cmp;
    }
    return nivA.length.compareTo(nivB.length);
  }

  static List<String> ordenarRutasPorJerarquia(Iterable<String> rutas) {
    List<String> lista = rutas.toList();
    lista.sort(compararRutasJerarquicas);
    return lista;
  }

  static bool coincideConPrefijoJerarquico(String rutaReal, List<String> nivelesSeleccionados) {
    if (nivelesSeleccionados.isEmpty) return true;
    List<String> nivelesRuta = descomponerRuta(rutaReal);
    if (nivelesRuta.length < nivelesSeleccionados.length) return false;
    for (int i = 0; i < nivelesSeleccionados.length; i++) {
      if (nivelesRuta[i].toUpperCase() != nivelesSeleccionados[i].toUpperCase()) return false;
    }
    return true;
  }
}

class SelectorJerarquicoUbicacion extends StatefulWidget {
  final List<String> todasLasRutas;
  final String? rutaSeleccionada;
  final bool permitirSeleccionParcial;
  final String textoRaizVacio;
  final Map<String, int>? conteoLotesPorRuta;
  final ValueChanged<String?> onRutaCambiada;

  const SelectorJerarquicoUbicacion({
    super.key,
    required this.todasLasRutas,
    required this.rutaSeleccionada,
    required this.onRutaCambiada,
    this.permitirSeleccionParcial = false,
    this.textoRaizVacio = 'Todas las ubicaciones',
    this.conteoLotesPorRuta,
  });

  @override
  State<SelectorJerarquicoUbicacion> createState() => _SelectorJerarquicoUbicacionState();
}

class _SelectorJerarquicoUbicacionState extends State<SelectorJerarquicoUbicacion> {
  List<String> _nivelesElegidos = [];
  String? _ultimaRutaEmitida;

  @override
  void initState() {
    super.initState();
    _ultimaRutaEmitida = widget.rutaSeleccionada;
    _sincronizarDesdeRuta(widget.rutaSeleccionada);
  }

  @override
  void didUpdateWidget(covariant SelectorJerarquicoUbicacion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rutaSeleccionada != _ultimaRutaEmitida) {
      _ultimaRutaEmitida = widget.rutaSeleccionada;
      _sincronizarDesdeRuta(widget.rutaSeleccionada);
    }
  }

  void _sincronizarDesdeRuta(String? ruta) {
    if (ruta == null || ruta.isEmpty || ruta == 'Sin anclar') {
      _nivelesElegidos = [];
    } else {
      _nivelesElegidos = JerarquiaUbicacionHelper.descomponerRuta(ruta);
    }
  }

  int _contarLotesBajoPrefijo(List<String> prefijo) {
    if (widget.conteoLotesPorRuta == null) return 0;
    int total = 0;
    for (var entry in widget.conteoLotesPorRuta!.entries) {
      if (JerarquiaUbicacionHelper.coincideConPrefijoJerarquico(entry.key, prefijo)) {
        total += entry.value;
      }
    }
    return total;
  }

  String? _resolverValorParaCallback() {
    if (_nivelesElegidos.isEmpty) return null;

    for (String r in widget.todasLasRutas) {
      List<String> nr = JerarquiaUbicacionHelper.descomponerRuta(r);
      if (nr.length == _nivelesElegidos.length) {
        bool igual = true;
        for (int i = 0; i < nr.length; i++) {
          if (nr[i].toUpperCase() != _nivelesElegidos[i].toUpperCase()) {
            igual = false;
            break;
          }
        }
        if (igual) return r;
      }
    }

    if (widget.permitirSeleccionParcial) {
      return _nivelesElegidos.join(' > ');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    List<List<String>> rutasDescompuestas = widget.todasLasRutas
        .map((r) => JerarquiaUbicacionHelper.descomponerRuta(r))
        .toList();

    List<Widget> selectores = [];
    int nivelActual = 0;

    while (true) {
      List<String> prefijo = _nivelesElegidos.take(nivelActual).toList();
      Set<String> opcionesSet = {};

      if (nivelActual == 0) {
        opcionesSet.addAll(['PISO', 'BODEGA', 'DISPLAY']);
      }

      for (var nr in rutasDescompuestas) {
        if (nr.length > nivelActual) {
          bool coincide = true;
          for (int i = 0; i < nivelActual; i++) {
            if (nr[i].toUpperCase() != prefijo[i].toUpperCase()) {
              coincide = false;
              break;
            }
          }
          if (coincide) {
            opcionesSet.add(nr[nivelActual]);
          }
        }
      }

      List<String> opciones = opcionesSet.toList();
      if (nivelActual == 0) {
        opciones.sort((a, b) {
          int pA = JerarquiaUbicacionHelper._prioridadArea(a);
          int pB = JerarquiaUbicacionHelper._prioridadArea(b);
          if (pA != pB) return pA.compareTo(pB);
          return a.compareTo(b);
        });
      } else {
        opciones.sort(JerarquiaUbicacionHelper._compararTextoNatural);
      }

      if (opciones.isEmpty) break;

      String? valorActual = _nivelesElegidos.length > nivelActual ? _nivelesElegidos[nivelActual] : null;
      if (valorActual != null && !opciones.contains(valorActual)) {
        valorActual = null;
      }

      String etiquetaNivel = nivelActual == 0
          ? '1. Área (PISO / BODEGA / DISPLAY)'
          : (nivelActual == 1 ? '2. Mueble / Ubicación' : '${nivelActual + 1}. Nivel / Cara / Entrepaño');

      int idxCopia = nivelActual;

      selectores.add(
        Padding(
          padding: EdgeInsets.only(top: idxCopia == 0 ? 0 : 6),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: idxCopia == 0 ? Colors.white10 : Colors.blueAccent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: valorActual != null ? Colors.greenAccent.withOpacity(0.8) : Colors.white24,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                dropdownColor: const Color(0xFF2C2C2C),
                value: valorActual,
                hint: Text(etiquetaNivel, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      idxCopia == 0
                          ? widget.textoRaizVacio
                          : (widget.permitirSeleccionParcial ? 'Todo ${_nivelesElegidos[idxCopia - 1]}' : 'Selecciona $etiquetaNivel...'),
                      style: TextStyle(
                        fontSize: 12,
                        color: idxCopia == 0 ? Colors.white54 : Colors.amberAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ...opciones.map((op) {
                    List<String> prefOp = [...prefijo, op];
                    int cantLotes = _contarLotesBajoPrefijo(prefOp);
                    return DropdownMenuItem<String?>(
                      value: op,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              idxCopia == 0 ? '📍 $op' : '↳ $op',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.conteoLotesPorRuta != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: cantLotes > 0 ? Colors.greenAccent.withOpacity(0.2) : Colors.white10,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$cantLotes lotes',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cantLotes > 0 ? Colors.greenAccent : Colors.white38,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
                onChanged: (val) {
                  setState(() {
                    _nivelesElegidos = _nivelesElegidos.take(idxCopia).toList();
                    if (val != null) {
                      _nivelesElegidos.add(val);
                    }
                  });
                  String? resuelta = _resolverValorParaCallback();
                  _ultimaRutaEmitida = resuelta;
                  widget.onRutaCambiada(resuelta);
                },
              ),
            ),
          ),
        ),
      );

      if (valorActual == null) break;
      bool tieneSubRamas = rutasDescompuestas.any((nr) {
        if (nr.length <= nivelActual + 1) return false;
        for (int i = 0; i <= nivelActual; i++) {
          if (nr[i].toUpperCase() != _nivelesElegidos[i].toUpperCase()) return false;
        }
        return true;
      });
      if (!tieneSubRamas) break;
      nivelActual++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: selectores,
    );
  }
}
