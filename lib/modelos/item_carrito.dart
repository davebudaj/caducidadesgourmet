class ItemCarrito {
  final String idOriginal;
  final String sku;
  final String descripcion;
  int cantidadEnCarrito;
  final DateTime fechaCaducidad;
  final String ubicacionOrigen;
  final Map<String, dynamic> datosOriginales;
  bool seleccionadoParaMover = false;

  ItemCarrito({
    required this.idOriginal,
    required this.sku,
    required this.descripcion,
    required this.cantidadEnCarrito,
    required this.fechaCaducidad,
    required this.ubicacionOrigen,
    required this.datosOriginales,
  });
}
