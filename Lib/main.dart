import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'dart:convert';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Tienda tienda = Tienda();

  @override
  void initState() {
    super.initState();
    _loadTienda();
  }

  _loadTienda() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      tienda = Tienda.fromPrefs(prefs);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: tienda.nombre,
      theme: ThemeData(primarySwatch: _toMaterialColor(tienda.color)),
      home: HomePage(tienda: tienda, onTiendaChanged: _loadTienda),
      debugShowCheckedModeBanner: false,
      locale: Locale('es', 'AR'),
    );
  }

  MaterialColor _toMaterialColor(Color color) {
    return MaterialColor(color.value, {50:color,100:color,200:color,300:color,400:color,500:color,600:color,700:color,800:color,900:color});
  }
}

class Tienda {
  String nombre = "Mi Tienda";
  String direccion = "";
  String moneda = "ARS";
  String simbolo = "\$";
  Color color = Colors.blue;
  String? logoPath;
  double lat = -34.6037; // Buenos Aires por defecto
  double lng = -58.3816;

  Tienda();

  Tienda.fromPrefs(SharedPreferences prefs){
    nombre = prefs.getString('nombre')?? "Mi Tienda";
    direccion = prefs.getString('direccion')?? "";
    moneda = prefs.getString('moneda')?? "ARS";
    simbolo = prefs.getString('simbolo')?? "\$";
    color = Color(prefs.getInt('color')?? Colors.blue.value);
    logoPath = prefs.getString('logoPath');
    lat = prefs.getDouble('lat')?? -34.6037;
    lng = prefs.getDouble('lng')?? -58.3816;
  }
}

class Producto {
  int? id;
  String nombre;
  String descripcion;
  String tipoVenta; // "unidad", "peso", "liquido"
  String unidad; // "kg", "g", "l", "ml", etc
  double stock;
  List<String> imagenes; // hasta 4
  Map<String, double> precios; // {"1":1000, "2":1750, "media_docena":5000}
  int categoriaId;

  Producto({this.id, required this.nombre, required this.descripcion, required this.tipoVenta, required this.unidad, required this.stock, required this.imagenes, required this.precios, required this.categoriaId});

  Map<String, dynamic> toMap() {
    return {
      'id': id, 'nombre': nombre, 'descripcion': descripcion, 'tipoVenta': tipoVenta,
      'unidad': unidad, 'stock': stock, 'imagenes': jsonEncode(imagenes),
      'precios': jsonEncode(precios), 'categoriaId': categoriaId
    };
  }
  
  factory Producto.fromMap(Map map) {
    return Producto(
      id: map['id'], nombre: map['nombre'], descripcion: map['descripcion'],
      tipoVenta: map['tipoVenta'], unidad: map['unidad'], stock: map['stock'],
      imagenes: List<String>.from(jsonDecode(map['imagenes'])),
      precios: Map<String, double>.from(jsonDecode(map['precios'])),
      categoriaId: map['categoriaId']
    );
  }
}

class DBHelper {
  static Database? _db;
  static Future<Database> get database async {
    if (_db!= null) return _db!;
    _db = await initDB();
    return _db!;
  }
  static initDB() async {
    String path = join(await getDatabasesPath(), 'pos.db');
    return await openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute('CREATE TABLE productos(id INTEGER PRIMARY KEY AUTOINCREMENT, nombre TEXT, descripcion TEXT, tipoVenta TEXT, unidad TEXT, stock REAL, imagenes TEXT, precios TEXT, categoriaId INTEGER)');
      await db.execute('CREATE TABLE ventas(id INTEGER PRIMARY KEY AUTOINCREMENT, fecha TEXT, total REAL, items TEXT, cambioInicial REAL)');
      await db.execute('CREATE TABLE categorias(id INTEGER PRIMARY KEY AUTOINCREMENT, nombre TEXT)');
    });
  }
}

// LISTA DE UNIDADES DISPONIBLES
const Map<String, List<String>> unidadesPorTipo = {
  "unidad": ["unidad", "pack", "caja", "docena"],
  "peso": ["kg", "g", "lb", "oz"],
  "liquido": ["l", "ml", "galon"]
};

class HomePage extends StatefulWidget {
  final Tienda tienda; final Function onTiendaChanged;
  HomePage({required this.tienda, required this.onTiendaChanged});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      VentasPage(tienda: widget.tienda),
      ProductosPage(tienda: widget.tienda),
      CajaPage(tienda: widget.tienda),
      ReportesPage(),
      AjustesPage(tienda: widget.tienda, onTiendaChanged: widget.onTiendaChanged),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.tienda.nombre)),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: widget.tienda.color,
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.point_of_sale), label: 'Vender'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'Productos'),
          BottomNavigationBarItem(icon: Icon(Icons.cash_register), label: 'Caja'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Reportes'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Ajustes'),
        ],
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }class ItemCarrito {
  Producto producto;
  String precioKey;
  double cantidad;
  ItemCarrito({required this.producto, required this.precioKey, required this.cantidad});
  double get precio => producto.precios[precioKey]?? 0;
  double get total => precio * cantidad;
}

// PAGINA VENTAS + CARRITO
class VentasPage extends StatefulWidget {
  final Tienda tienda;
  VentasPage({required this.tienda});
  @override
  State<VentasPage> createState() => _VentasPageState();
}
class _VentasPageState extends State<VentasPage> {
  List<Producto> productos = [];
  List<ItemCarrito> carrito = [];
  double cambioInicial = 0;

  _cargar() async {
    final db = await DBHelper.database;
    final res = await db.query('productos');
    setState(() => productos = res.map((e) => Producto.fromMap(e)).toList());
  }
  @override
  void initState(){super.initState(); _cargar();}

  _vender() async {
    double total = carrito.fold(0.0,(a,b)=>a+b.total);
    final db = await DBHelper.database;
    await db.insert('ventas', {
      'fecha': DateTime.now().toIso8601String(),
      'total': total,
      'items': jsonEncode(carrito.map((e)=>{'id':e.producto.id,'cant':e.cantidad,'precioKey':e.precioKey}).toList()),
      'cambioInicial': cambioInicial
    });
    // Descontar stock
    for(var item in carrito){
      await db.update('productos', {'stock': item.producto.stock - item.cantidad}, where: 'id =?', whereArgs: [item.producto.id]);
    }
    _mostrarOpcionesTicket(total);
    setState(()=>carrito.clear());
    _cargar();
  }

  _mostrarOpcionesTicket(double total) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('Venta Realizada'),
      content: Text('Total: ${widget.tienda.simbolo}${total.toStringAsFixed(2)}'),
      actions: [
        TextButton(onPressed: ()=>_imprimirTermica(total), child: Text('Imprimir Térmica')),
        TextButton(onPressed: ()=>_compartirPDF(total), child: Text('Compartir WhatsApp')),
      ],
    ));
  }

  _imprimirTermica(double total) {
    // Aquí iría la lógica de blue_thermal_printer
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Conectando a impresora térmica...')));
  }

  _compartirPDF(double total) async {
    // Aquí generamos PDF y lo compartimos
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Generando PDF para WhatsApp...')));
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(flex: 2, child: ListView.builder(itemCount: productos.length, itemBuilder: (_,i){
        Producto p = productos[i];
        return ListTile(
          title: Text(p.nombre),
          subtitle: Text('Stock: ${p.stock} ${p.unidad}'),
          onTap: (){
            showDialog(context: context, builder: (_) => AlertDialog(
              title: Text(p.nombre),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
               ...p.precios.entries.map((e) => ListTile(
                  title: Text('${e.key}: ${widget.tienda.simbolo}${e.value}'),
                  onTap: (){
                    setState(()=>carrito.add(ItemCarrito(producto: p, precioKey: e.key, cantidad: 1)));
                    Navigator.pop(context);
                  },
                ))
              ]),
            ));
          },
        );
      })),
      Expanded(flex: 1, child: Column(children: [
        Text('CARRITO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        Expanded(child: ListView.builder(itemCount: carrito.length, itemBuilder: (_,i){
          var item = carrito[i];
          return ListTile(
            title: Text('${item.cantidad} ${item.producto.unidad} ${item.producto.nombre}'),
            subtitle: Text('${item.precioKey}'),
            trailing: Text('${widget.tienda.simbolo}${item.total.toStringAsFixed(2)}'),
          );
        })),
        Text('TOTAL: ${widget.tienda.simbolo}${carrito.fold(0.0,(a,b)=>a+b.total).toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold)),
        ElevatedButton(onPressed: carrito.isEmpty? null : _vender, child: Text('COBRAR'))
      ]))
    ]);
  }
}

// PAGINA PRODUCTOS CON 4 FOTOS
class ProductosPage extends StatefulWidget {
  final Tienda tienda;
  ProductosPage({required this.tienda});
  @override
  State<ProductosPage> createState() => _ProductosPageState();
}
class _ProductosPageState extends State<ProductosPage> {
  List<Producto> productos = [];
  _cargar() async {
    final db = await DBHelper.database;
    final res = await db.query('productos');
    setState(() => productos = res.map((e) => Producto.fromMap(e)).toList());
  }
  @override
  void initState(){super.initState(); _cargar();}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(itemCount: productos.length, itemBuilder: (_,i){
        return Card(child: ListTile(title: Text(productos[i].nombre), subtitle: Text('Stock: ${productos[i].stock}')));
      }),
      floatingActionButton: FloatingActionButton(onPressed: (){}, child: Icon(Icons.add)),
    );
  }
}

// PAGINA CAJA
class CajaPage extends StatelessWidget {
  final Tienda tienda;
  CajaPage({required this.tienda});
  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Control de Caja\nCambio Inicial y Ventas del día'));
  }
}

// PAGINA REPORTES
class ReportesPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Historial de Ventas\nBotón para guardar en Google Drive'));
  }
}

// PAGINA AJUSTES
class AjustesPage extends StatefulWidget {
  final Tienda tienda; final Function onTiendaChanged;
  AjustesPage({required this.tienda, required this.onTiendaChanged});
  @override
  State<AjustesPage> createState() => _AjustesPageState();
}
class _AjustesPageState extends State<AjustesPage> {
  late TextEditingController nombreCtrl, dirCtrl, monedaCtrl, simboloCtrl;
  @override
  void initState(){
    super.initState();
    nombreCtrl = TextEditingController(text: widget.tienda.nombre);
    dirCtrl = TextEditingController(text: widget.tienda.direccion);
    monedaCtrl = TextEditingController(text: widget.tienda.moneda);
    simboloCtrl = TextEditingController(text: widget.tienda.simbolo);
  }

  _guardar() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('nombre', nombreCtrl.text);
    await prefs.setString('direccion', dirCtrl.text);
    await prefs.setString('moneda', monedaCtrl.text);
    await prefs.setString('simbolo', simboloCtrl.text);
    widget.onTiendaChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: EdgeInsets.all(16), children: [
      TextField(controller: nombreCtrl, decoration: InputDecoration(labelText: 'Nombre Tienda')),
      TextField(controller: dirCtrl, decoration: InputDecoration(labelText: 'Dirección')),
      TextField(controller: monedaCtrl, decoration: InputDecoration(labelText: 'Moneda: ARS')),
      TextField(controller: simboloCtrl, decoration: InputDecoration(labelText: 'Símbolo: $')),
      SizedBox(height: 20),
      Text('Ubicación en Google Maps'),
      Container(height: 200, child: GoogleMap(initialCameraPosition: CameraPosition(target: LatLng(widget.tienda.lat, widget.tienda.lng), zoom: 14))),
      ElevatedButton(onPressed: _guardar, child: Text('Guardar Datos Tienda'))
    ]);
  }
}
}
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

// AGREGAR ESTO DENTRO DE _ProductosPageState
class _ProductosPageState extends State<ProductosPage> {
  List<Producto> productos = [];
  final ImagePicker _picker = ImagePicker();

  _cargar() async {
    final db = await DBHelper.database;
    final res = await db.query('productos');
    setState(() => productos = res.map((e) => Producto.fromMap(e)).toList());
  }
  @override
  void initState(){super.initState(); _cargar();}

  _agregarProducto() async {
    TextEditingController nombre = TextEditingController();
    TextEditingController desc = TextEditingController();
    TextEditingController stock = TextEditingController();
    String tipoVenta = "unidad";
    String unidad = "unidad";
    List<String> imagenes = [];
    Map<String, TextEditingController> preciosCtrl = {"1":TextEditingController(), "2":TextEditingController()};

    showDialog(context: context, builder: (_) => StatefulBuilder(builder: (context, setStateDialog){
      return AlertDialog(
        title: Text('Nuevo Producto'),
        content: SingleChildScrollView(child: Column(children: [
          TextField(controller: nombre, decoration: InputDecoration(labelText: 'Nombre')),
          TextField(controller: desc, decoration: InputDecoration(labelText: 'Descripción')),
          DropdownButton(value: tipoVenta, items: ["unidad","peso","liquido"].map((e)=>DropdownMenuItem(value:e, child:Text(e))).toList(), onChanged: (v){setStateDialog(()=>tipoVenta=v!);}),
          DropdownButton(value: unidad, items: unidadesPorTipo[tipoVenta]!.map((e)=>DropdownMenuItem(value:e, child:Text(e))).toList(), onChanged: (v){setStateDialog(()=>unidad=v!);}),
          TextField(controller: stock, decoration: InputDecoration(labelText: 'Stock'), keyboardType: TextInputType.number),
         ...preciosCtrl.entries.map((e)=>TextField(controller: e.value, decoration: InputDecoration(labelText: 'Precio ${e.key}'), keyboardType: TextInputType.number)),
          ElevatedButton(onPressed: () async {
            final XFile? img = await _picker.pickImage(source: ImageSource.gallery);
            if(img!=null && imagenes.length<4) setStateDialog(()=>imagenes.add(img.path));
          }, child: Text('Agregar Foto ${imagenes.length}/4')),
        ])),
        actions: [
          TextButton(onPressed: () async {
            final db = await DBHelper.database;
            Map<String,double> precios = {};
            preciosCtrl.forEach((k,v){if(v.text.isNotEmpty) precios[k]=double.parse(v.text);});
            await db.insert('productos', Producto(nombre: nombre.text, descripcion: desc.text, tipoVenta: tipoVenta, unidad: unidad, stock: double.parse(stock.text), imagenes: imagenes, precios: precios, categoriaId: 0).toMap());
            Navigator.pop(context); _cargar();
          }, child: Text('Guardar'))
        ],
      );
    }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(itemCount: productos.length, itemBuilder: (_,i){
        Producto p = productos[i];
        return Card(child: ListTile(
          leading: p.imagenes.isNotEmpty? Image.file(File(p.imagenes[0]), width: 50, height: 50, fit: BoxFit.cover) : Icon(Icons.image),
          title: Text(p.nombre),
          subtitle: Text('Stock: ${p.stock} ${p.unidad}'),
        ));
      }),
      floatingActionButton: FloatingActionButton(onPressed: _agregarProducto, child: Icon(Icons.add)),
    );
  }
}

// AGREGAR ESTO DENTRO DE _VentasPageState
BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

_imprimirTermica(double total) async {
  List<BluetoothDevice> devices = await bluetooth.getBondedDevices();
  if(devices.isEmpty) return;

  await bluetooth.connect(devices[0].address!);
  bluetooth.printCustom(widget.tienda.nombre, 2, 1);
  bluetooth.printCustom(widget.tienda.direccion, 1, 1);
  bluetooth.printNewLine();
  for(var item in carrito){
    bluetooth.printLeftRight("${item.cantidad}x ${item.producto.nombre}", "${widget.tienda.simbolo}${item.total.toStringAsFixed(2)}", 0);
  }
  bluetooth.printNewLine();
  bluetooth.printLeftRight("TOTAL:", "${widget.tienda.simbolo}${total.toStringAsFixed(2)}", 1);
  bluetooth.printNewLine();
  bluetooth.printCustom("Gracias por su compra!", 1, 1);
  bluetooth.paperCut();
  bluetooth.disconnect();
}

_compartirPDF(double total) async {
  final pdf = pw.Document();
  pdf.addPage(pw.Page(build: (pw.Context context) {
    return pw.Column(children: [
      pw.Text(widget.tienda.nombre, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.Text(widget.tienda.direccion),
      pw.Divider(),
    ...carrito.map((item) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text("${item.cantidad}x ${item.producto.nombre}"),
        pw.Text("${widget.tienda.simbolo}${item.total.toStringAsFixed(2)}")
      ])),
      pw.Divider(),
      pw.Text("TOTAL: ${widget.tienda.simbolo}${total.toStringAsFixed(2)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
    ]);
  }));
  final bytes = await pdf.save();
  await Printing.sharePdf(bytes: bytes, filename: 'ticket_${DateTime.now().millisecondsSinceEpoch}.pdf');
}

// AGREGAR ESTO DENTRO DE ReportesPage
class _ReportesPageState extends State<ReportesPage> {
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: [drive.DriveApi.driveFileScope]);

  _subirADrive() async {
    final db = await DBHelper.database;
    final ventas = await db.query('ventas');
    String data = jsonEncode(ventas);
    final file = File('/mnt/data/backup.json');
    await file.writeAsString(data);

    final account = await _googleSignIn.signIn();
    final auth = await account!.authentication;
    final client = GoogleAuthClient(auth.accessToken!);
    final driveApi = drive.DriveApi(client);
    await driveApi.files.create(drive.File(name: 'backup_pos.json'), uploadMedia: drive.Media(file.openRead(), file.lengthSync()));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup subido a Google Drive')));
  }

  @override
  Widget build(BuildContext context) {
    return Center(child: ElevatedButton(onPressed: _subirADrive, child: Text('Guardar Ventas en Google Drive')));
  }
}

class GoogleAuthClient extends http.BaseClient {
  final String _accessToken;
  final http.Client _client = http.Client();
  GoogleAuthClient(this._accessToken);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _client.send(request);
  }
}
