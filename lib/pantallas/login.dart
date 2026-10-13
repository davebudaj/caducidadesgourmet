import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'navegacion.dart';

class PantallaLogin extends StatefulWidget {
  const PantallaLogin({super.key});
  @override
  State<PantallaLogin> createState() => _PantallaLoginState();
}

class _PantallaLoginState extends State<PantallaLogin> {
  final TextEditingController _numeroCtrl = TextEditingController();
  bool _cargando = false;
  String _zonaSeleccionada = '9';
  String? _tiendaSeleccionada;

  // Mapa de tiendas extraído del archivo "Reto Zona 9.csv" (Centro: Nombre)
  final Map<String, String> _tiendasZona9 = {
    '0012': 'L VILLAHERMOSA CRYSTAL',
    '0014': 'L TUXTLA GTZ',
    '0019': 'L TAPACHULA',
    '0021': 'L VILLAHERMOSA',
    '0075': 'L CANCUN',
    '0076': 'L MERIDA',
    '0079': 'L CHETUMAL',
    '0102': 'L CAMPECHE',
    '0134': 'L VILLAHERMOSA ALTABRISA',
    '0191': 'L TUXTLA ORIENTE',
    '0304': 'L CIUDAD DEL CARMEN',
    '0307': 'L PLAYA DEL CARMEN',
    '0458': 'L MERIDA CABO NORTE',
    '0472': 'L COMITAN',
  };

  Future<void> _iniciarSesion() async {
    String numEmp = _numeroCtrl.text.trim();
    if (numEmp.isEmpty) return;
    if (_tiendaSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, selecciona una tienda.'), backgroundColor: Colors.orange));
      return;
    }
    
    setState(() => _cargando = true);

    // Identificador único de la tienda (ej. "Z9_0075") para aislar la base de datos
    String idTiendaGlobal = "Z${_zonaSeleccionada}_$_tiendaSeleccionada";
    String nombreTiendaReal = _tiendasZona9[_tiendaSeleccionada] ?? '';

    // Llave Maestra
    if (numEmp == 'ADMIN777') {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => NavegacionPrincipal(
        esJefe: true, 
        nombreUsuario: "Administrador Maestro", 
        numeroEmpleado: "000",
        idTiendaGlobal: idTiendaGlobal,
        nombreTienda: nombreTiendaReal
      )));
      return;
    }

    try {
      // IMPORTANTE: Buscamos colaboradores DENTRO de la colección de esa tienda específica
      var doc = await FirebaseFirestore.instance.collection('tiendas').doc(idTiendaGlobal).collection('colaboradores').doc(numEmp).get();
      
      // Si no está en la tienda, buscamos en un "Directorio Global" (Opcional para el futuro)
      if (!doc.exists) {
        doc = await FirebaseFirestore.instance.collection('colaboradores_global').doc(numEmp).get();
      }

      if (doc.exists) {
        String rol = doc.data()?['rol'] ?? '';
        bool esJefe = ['jefe', 'gerente', 'director'].contains(rol);
        String nombre = doc.data()?['nombre'] ?? 'Colaborador';
        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => NavegacionPrincipal(
            esJefe: esJefe, 
            nombreUsuario: nombre, 
            numeroEmpleado: numEmp,
            idTiendaGlobal: idTiendaGlobal,
            nombreTienda: nombreTiendaReal
          )));
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Número de empleado no registrado para esta sucursal.'), backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF121212), Color(0xFF2C2C2C)], begin: Alignment.topCenter, end: Alignment.bottomCenter)
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 80),
              const Icon(Icons.shield_moon, size: 100, color: Colors.amber),
              const SizedBox(height: 10),
              const Text('GOURMET GUARD', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4, color: Colors.amber)),
              const Text('Plataforma Multitienda', style: TextStyle(color: Colors.white54, letterSpacing: 2)),
              const SizedBox(height: 40),
              
              // Selector de Zona y Tienda
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        value: _zonaSeleccionada,
                        decoration: InputDecoration(labelText: 'Zona', filled: true, fillColor: Colors.black45, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
                        dropdownColor: const Color(0xFF2C2C2C),
                        items: const [DropdownMenuItem(value: '9', child: Text('Zona 9'))],
                        onChanged: (val) => setState(() => _zonaSeleccionada = val!),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _tiendaSeleccionada,
                        decoration: InputDecoration(labelText: 'Sucursal', filled: true, fillColor: Colors.black45, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
                        dropdownColor: const Color(0xFF2C2C2C),
                        hint: const Text('Elige tu tienda...'),
                        items: _tiendasZona9.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))).toList(),
                        onChanged: (val) => setState(() => _tiendaSeleccionada = val),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: TextField(
                  controller: _numeroCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2),
                  decoration: InputDecoration(
                    hintText: '# DE EMPLEADO',
                    hintStyle: const TextStyle(fontSize: 16, letterSpacing: 0, color: Colors.white54),
                    filled: true,
                    fillColor: Colors.black45,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _iniciarSesion(),
                ),
              ),
              const SizedBox(height: 30),
              
              _cargando 
                ? const CircularProgressIndicator(color: Colors.amber)
                : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                    icon: const Icon(Icons.login, size: 24),
                    label: const Text('INGRESAR', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    onPressed: _iniciarSesion,
                  ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}
