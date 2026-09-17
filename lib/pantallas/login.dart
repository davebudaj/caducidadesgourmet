import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'navegacion.dart'; // Llama a la navegación que acabamos de crear

class PantallaLogin extends StatefulWidget {
  const PantallaLogin({super.key});
  @override
  State<PantallaLogin> createState() => _PantallaLoginState();
}

class _PantallaLoginState extends State<PantallaLogin> {
  final TextEditingController _numeroCtrl = TextEditingController();
  bool _cargando = false;

  Future<void> _iniciarSesion() async {
    String numEmp = _numeroCtrl.text.trim();
    if (numEmp.isEmpty) return;
    
    setState(() => _cargando = true);

    // Llave Maestra
    if (numEmp == 'ADMIN777') {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const NavegacionPrincipal(esJefe: true, nombreUsuario: "Administrador Maestro", numeroEmpleado: "000")));
      return;
    }

    try {
      var doc = await FirebaseFirestore.instance.collection('colaboradores').doc(numEmp).get();
      if (doc.exists) {
        bool esJefe = doc.data()?['rol'] == 'jefe';
        String nombre = doc.data()?['nombre'] ?? 'Colaborador';
        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => NavegacionPrincipal(esJefe: esJefe, nombreUsuario: nombre, numeroEmpleado: numEmp)));
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Número de colaborador no encontrado.'), backgroundColor: Colors.redAccent));
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield_moon, size: 120, color: Colors.amber),
            const SizedBox(height: 20),
            const Text('GOURMET GUARD', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4, color: Colors.amber)),
            const SizedBox(height: 50),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: TextField(
                controller: _numeroCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2),
                decoration: InputDecoration(
                  hintText: 'NÚMERO DE EMPLEADO',
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
          ],
        ),
      ),
    );
  }
}
