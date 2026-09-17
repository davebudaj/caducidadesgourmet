import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';

class PantallaGraficas extends StatefulWidget {
  final Function(String) onFiltroSeleccionado;
  const PantallaGraficas({super.key, required this.onFiltroSeleccionado});

  @override
  State<PantallaGraficas> createState() => _PantallaGraficasState();
}

class _PantallaGraficasState extends State<PantallaGraficas> {
  int _indiceTocado = -1; 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Salud e Impacto Financiero', style: TextStyle(fontWeight: FontWeight.bold))),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('inventario_activo').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.amber));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Sin datos financieros.'));

          double totalRiesgo = 0, valorSano = 0, valorProximo = 0, valorCritico = 0, valorCaducado = 0;
          Map<String, double> riesgoPorProveedor = {};
          DateTime hoy = DateTime.now();

          for (var doc in snapshot.data!.docs) {
            var data = doc.data() as Map<String, dynamic>;
            Timestamp? ts = data['fechaCaducidad'];
            if (ts == null) continue;
            
            DateTime cad = ts.toDate();
            int dias = cad.difference(hoy).inDays;
            int cant = data['cantidad'] ?? 0;
            double precio = double.tryParse(data['precioVenta'].toString()) ?? 0.0;
            double valor = cant * precio;

            if (dias < 0) { valorCaducado += valor; } 
            else if (dias <= 14) { valorCritico += valor; totalRiesgo += valor; } 
            else if (dias <= 30) { valorProximo += valor; totalRiesgo += valor; } 
            else { valorSano += valor; }

            if (dias <= 30) {
              String prov = data['nombreProveedor'] ?? 'DESCONOCIDO';
              riesgoPorProveedor[prov] = (riesgoPorProveedor[prov] ?? 0) + valor;
            }
          }

          var proveedoresOrdenados = riesgoPorProveedor.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          List<PieChartSectionData> rebanadas = [];
          List<String> idFiltro = [];
          double totalInventario = valorSano + valorProximo + valorCritico + valorCaducado;
          int idx = 0;

          void agregarRebanada(double valor, Color color, String titulo, String id) {
            if (valor > 0) {
              final esTocado = _indiceTocado == idx;
              final porcentaje = ((valor / totalInventario) * 100).toStringAsFixed(1);
              rebanadas.add(PieChartSectionData(
                value: valor, color: color,
                title: esTocado ? '$porcentaje%' : titulo,
                radius: esTocado ? 70 : 55, 
                titleStyle: TextStyle(fontSize: esTocado ? 16 : 10, fontWeight: FontWeight.bold, color: color == Colors.redAccent ? Colors.white : Colors.black)
              ));
              idFiltro.add(id);
              idx++;
            }
          }

          agregarRebanada(valorSano, Colors.greenAccent, 'Sano\n>30d', 'sano');
          agregarRebanada(valorProximo, Colors.yellow, 'Próximo\n15-30d', 'proximo');
          agregarRebanada(valorCritico, Colors.orangeAccent, 'Crítico\n<15d', 'critico');
          agregarRebanada(valorCaducado, Colors.redAccent, 'Caducado\nYa!', 'caducado');

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                SizedBox(
                  height: 180,
                  child: rebanadas.isEmpty ? const Center(child: Text("No hay valor registrado")) : PieChart(
                    PieChartData(
                      sectionsSpace: 4, centerSpaceRadius: 35, sections: rebanadas,
                      pieTouchData: PieTouchData(
                        touchCallback: (FlTouchEvent event, pieTouchResponse) {
                          if (!event.isInterestedForInteractions || pieTouchResponse == null || pieTouchResponse.touchedSection == null) {
                            if (_indiceTocado != -1) setState(() => _indiceTocado = -1);
                            return;
                          }
                          int nId = pieTouchResponse.touchedSection!.touchedSectionIndex;
                          if (nId != _indiceTocado) setState(() => _indiceTocado = nId);
                          if (event is FlTapUpEvent && nId >= 0 && nId < idFiltro.length) {
                            widget.onFiltroSeleccionado(idFiltro[nId]);
                            setState(() => _indiceTocado = -1); 
                          }
                        }
                      )
                    )
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.redAccent, Colors.orangeAccent]), borderRadius: BorderRadius.circular(15)),
                  child: Column(
                    children: [
                      const Text('Riesgo Total de Merma (≤ 30 días)', style: TextStyle(color: Colors.white, fontSize: 14)),
                      const SizedBox(height: 5),
                      Text('MXN ${totalRiesgo.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Align(alignment: Alignment.centerLeft, child: Text('Top Proveedores en Riesgo', style: TextStyle(fontSize: 16, color: Colors.amber, fontWeight: FontWeight.bold))),
                Expanded(
                  child: proveedoresOrdenados.isEmpty ? const Center(child: Text('¡Excelente! Sin riesgo a 30 días.', style: TextStyle(color: Colors.greenAccent))) : ListView.builder(
                    itemCount: proveedoresOrdenados.length,
                    itemBuilder: (context, index) {
                      var item = proveedoresOrdenados[index];
                      double porcentaje = totalRiesgo > 0 ? item.value / totalRiesgo : 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Expanded(child: Text(item.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), overflow: TextOverflow.ellipsis)),
                              Text('MXN ${item.value.toStringAsFixed(2)}', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                            ]),
                            const SizedBox(height: 5),
                            LinearProgressIndicator(value: porcentaje, backgroundColor: Colors.white10, color: Colors.amber, minHeight: 8, borderRadius: BorderRadius.circular(5))
                          ],
                        ),
                      );
                    },
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}
