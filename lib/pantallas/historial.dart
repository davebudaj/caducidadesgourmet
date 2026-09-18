import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PantallaHistorial extends StatefulWidget {
  const PantallaHistorial({super.key});
  @override
  State<PantallaHistorial> createState() => _PantallaHistorialState();
}

class _PantallaHistorialState extends State<PantallaHistorial> {
  DateTime? _fechaSeleccionada;
  String? _grupoSeleccionado;

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

          var grupos = snapshot.data!.docs
              .map((doc) => (doc.data() as Map<String, dynamic>)['nombreGpoArticulos']?.toString() ?? 'SIN GRUPO')
              .toSet().toList()..sort();

          var docsFiltrados = snapshot.data!.docs.where((doc) {
            var d = doc.data() as Map<String, dynamic>;
            bool coincideGrupo = true;
            bool coincideFecha = true;

            if (_grupoSeleccionado != null) {
              String gpo = d['nombreGpoArticulos']?.toString() ?? 'SIN GRUPO';
              coincideGrupo = gpo == _grupoSeleccionado;
            }

            if (_fechaSeleccionada != null) {
              Timestamp? ts = d['fechaTratamiento'];
              if (ts != null) {
                DateTime dt = ts.toDate();
                coincideFecha = dt.year == _fechaSeleccionada!.year && dt.month == _fechaSeleccionada!.month && dt.day == _fechaSeleccionada!.day;
              } else { coincideFecha = false; }
            }
            return coincideGrupo && coincideFecha;
          }).toList();

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12), color: Colors.black,
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 5)),
                        icon: const Icon(Icons.calendar_today, size: 14),
                        label: Text(_fechaSeleccionada == null ? 'Filtrar Fecha' : '${_fechaSeleccionada!.day}/${_fechaSeleccionada!.month}/${_fechaSeleccionada!.year}', style: const TextStyle(fontSize: 11)),
                        onPressed: () async {
                          DateTime? picked = await showDatePicker(context: context, initialDate: _fechaSeleccionada ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
                          if (picked != null) setState(() => _fechaSeleccionada = picked);
                        },
                      ),
                    ),
                    if (_fechaSeleccionada != null) IconButton(icon: const Icon(Icons.clear, color: Colors.redAccent, size: 18), onPressed: () => setState(() => _fechaSeleccionada = null)),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: Container(
                        height: 40, padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            isExpanded: true, dropdownColor: const Color(0xFF2C2C2C),
                            value: _grupoSeleccionado, hint: const Text('Grupo Art.', style: TextStyle(fontSize: 12, color: Colors.white54)),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Todos', style: TextStyle(fontSize: 12, color: Colors.greenAccent))),
                              ...grupos.map((g) => DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)))
                            ],
                            onChanged: (v) => setState(() => _grupoSeleccionado = v),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: docsFiltrados.isEmpty
                    ? const Center(child: Text('No hay registros con estos filtros.', style: TextStyle(color: Colors.white54)))
                    : ListView.builder(
                        itemCount: docsFiltrados.length,
                        itemBuilder: (context, index) {
                          var d = docsFiltrados[index].data() as Map<String, dynamic>;
                          DateTime? fecha = (d['fechaTratamiento'] as Timestamp?)?.toDate();
                          String grupo = d['nombreGpoArticulos'] ?? 'SIN GRUPO';
                          String proveedor = d['nombreProveedor'] ?? 'ND';
                          
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
                                    Text('Grupo: $grupo', style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                    Text('Prov: $proveedor', style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text('Retirado: ${d['cantidadTratada']} pzas • ${d['motivo']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                    const SizedBox(height: 2),
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
