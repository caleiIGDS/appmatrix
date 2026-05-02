// ═══════════════════════════════════════════════════════════════
//  LED MATRIX 8×8 — Controlador visual para ESP32
//  Arquitectura: un solo archivo con 5 clases
//    1. MyApp               → raíz de la app, define el tema global
//    2. LedMatrixScreen     → pantalla principal (StatefulWidget)
//    3. ColorWheelSheet     → bottom sheet con el círculo cromático
//    4. _ColorWheelPainter  → CustomPainter que dibuja el círculo HSV
//    5. _BrightnessSlider   → slider de brillo reutilizable
//    6. _ActionButton       → botón animado con efecto de escala
// ═══════════════════════════════════════════════════════════════

import 'dart:math'; // Para sin(), cos(), atan2(), pi — usados en el círculo cromático
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para HapticFeedback (vibración al tocar botones)
import 'package:flutter_libserialport/flutter_libserialport.dart';


SerialPort? port;

bool conectar(String nombrePuerto) {
  port = SerialPort(nombrePuerto);

  if (!port!.openWrite()) {
    print("No se pudo abrir el puerto");
    return false;
  }

  print("Conectado a $nombrePuerto");
  return true;
}
void main() {
  runApp(const MyApp());
}


// ─── Constantes de versión ──────────────────────────────────────
// Cambialas acá y se actualizan automáticamente en el drawer y el dialog
const String kAppVersion = '1.2.0';
const String kAppBuild   = 'build 42';

// ════════════════════════════════════════════════════════════════
//  1. MyApp — Raíz de la aplicación
//     Define el tema oscuro global y monta la pantalla principal
// ════════════════════════════════════════════════════════════════
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const LedMatrixScreen(),
      debugShowCheckedModeBanner: false, // Oculta el banner "DEBUG" en la esquina
      theme: ThemeData.dark().copyWith(
        // Color de fondo de todos los Scaffold (pantallas)
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        // Color de fondo específico del Drawer (panel lateral)
        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFF0F0F1A),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  2. LedMatrixScreen — Pantalla principal
//     StatefulWidget porque el estado (pixels, color, etc.) cambia
//     con TickerProviderStateMixin para poder usar AnimationController
// ════════════════════════════════════════════════════════════════
class LedMatrixScreen extends StatefulWidget {
  const LedMatrixScreen({super.key});

  @override
  State<LedMatrixScreen> createState() => _LedMatrixScreenState();
}

class _LedMatrixScreenState extends State<LedMatrixScreen>
    with TickerProviderStateMixin {

  // ── Estado del canvas ────────────────────────────────────────
  // Lista de 64 colores (8×8). Índice 0 = esquina superior izquierda,
  // índice 63 = esquina inferior derecha.
  List<Color> pixels = List.generate(64, (_) => Colors.black);

  // Color actualmente seleccionado para pintar
  Color selectedColor = const Color(0xFFFF3131); // Rojo por defecto

  // true → la paleta expandida está visible
  bool showPalette = false;

  // true → el modo borrador está activo (pinta negro en lugar del color)
  bool isEraser = false;

  // Controlador para la animación de apertura/cierre de la paleta
  late AnimationController _paletteController;

  // Key del Scaffold necesaria para abrir el Drawer programáticamente
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // ── Paleta rápida (8 colores siempre visibles) ───────────────
  final List<Color> quickColors = [
    const Color(0xFFFF3131), // Rojo
    const Color(0xFF00FF88), // Verde neón
    const Color(0xFF00AAFF), // Azul cielo
    const Color(0xFFFFD700), // Amarillo dorado
    const Color(0xFFFF00FF), // Magenta
    const Color(0xFFFF6B00), // Naranja
    Colors.white,
    Colors.black,
  ];

  // ── Paleta completa (48 colores agrupados por familia) ───────
  final List<Color> fullPalette = [
    // Rojos y rosas
    const Color(0xFFFF0000), const Color(0xFFFF3131), const Color(0xFFFF6B6B),
    const Color(0xFFFF9999), const Color(0xFF8B0000), const Color(0xFFDC143C),
    // Naranjas
    const Color(0xFFFF4500), const Color(0xFFFF6B00), const Color(0xFFFF8C00),
    const Color(0xFFFFAA33), const Color(0xFFFFCC66), const Color(0xFFFFF0AA),
    // Amarillos
    const Color(0xFFFFD700), const Color(0xFFFFFF00), const Color(0xFFFFFF66),
    const Color(0xFFEEEE00), const Color(0xFFCCCC00), const Color(0xFF888800),
    // Verdes
    const Color(0xFF00FF00), const Color(0xFF00FF88), const Color(0xFF00FFAA),
    const Color(0xFF00CC00), const Color(0xFF008800), const Color(0xFF004400),
    // Cyanos
    const Color(0xFF00FFFF), const Color(0xFF00EEFF), const Color(0xFF00CCFF),
    const Color(0xFF0099CC), const Color(0xFF006699), const Color(0xFF003344),
    // Azules
    const Color(0xFF0000FF), const Color(0xFF3333FF), const Color(0xFF00AAFF),
    const Color(0xFF5599FF), const Color(0xFF0044CC), const Color(0xFF001166),
    // Violetas y magentas
    const Color(0xFF8800FF), const Color(0xFFAA00FF), const Color(0xFFCC44FF),
    const Color(0xFFFF00FF), const Color(0xFFFF44FF), const Color(0xFFFF99FF),
    // Blancos y grises
    const Color(0xFFFFFFFF), const Color(0xFFCCCCCC), const Color(0xFF999999),
    const Color(0xFF666666), const Color(0xFF333333), const Color(0xFF111111),
  ];

  // ── Ciclo de vida ────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Inicializa el controlador de animación para la paleta
    // duration: cuánto tarda en abrirse/cerrarse
    _paletteController = AnimationController(
      vsync: this, // 'this' funciona porque usamos TickerProviderStateMixin
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    // Siempre liberar los AnimationController para evitar memory leaks
    _paletteController.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────

  // Muestra/oculta la paleta completa y anima el ícono de flecha
  void togglePalette() {
    setState(() => showPalette = !showPalette);
    showPalette ? _paletteController.forward() : _paletteController.reverse();
  }

  // Convierte un Color de Flutter a lista [R, G, B] (0-255)
  // Ej: Colors.red → [255, 0, 0]
  List<int> colorToRGB(Color c) => [c.red, c.green, c.blue];

  // Devuelve la matriz completa como lista de listas [[R,G,B], [R,G,B], ...]
  // Este es el formato que se envía al ESP32
  List<List<int>> getMatrixRGB() => pixels.map(colorToRGB).toList();

  // Imprime la matriz en consola (debug) + vibración media
  void printMatrix() {
    debugPrint(getMatrixRGB().toString());
    HapticFeedback.mediumImpact();
  }

  // Pone todos los pixels en negro + vibración leve
  void clearMatrix() {
    setState(() => pixels = List.generate(64, (_) => Colors.black));
    HapticFeedback.lightImpact();
  }

  // Pinta un pixel individual.
  // Si el borrador está activo, pinta negro. Si no, usa selectedColor.
  // Solo llama setState si el color realmente cambia (optimización)
  void paintPixel(int index) {
    final color = isEraser ? Colors.black : selectedColor;
    if (pixels[index] != color) setState(() => pixels[index] = color);
  }

  // Abre el bottom sheet del círculo cromático
  void _openColorWheel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,      // Permite que el sheet sea tan alto como necesite
      backgroundColor: Colors.transparent, // El sheet maneja su propio fondo
      builder: (_) => ColorWheelSheet(
        // Si el borrador estaba activo, empezamos el selector en rojo
        initialColor: isEraser ? const Color(0xFFFF3131) : selectedColor,
        onColorSelected: (c) {
          setState(() {
            selectedColor = c;
            isEraser = false; // Desactiva el borrador al elegir un color
          });
        },
      ),
    );
  }

  // ── Build principal ──────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,                    // Necesario para _scaffoldKey.currentState?.openDrawer()
      backgroundColor: const Color(0xFF0A0A0F),
      drawer: _buildDrawer(),               // Panel lateral izquierdo
      body: SafeArea(
        // SafeArea respeta el notch y la barra de estado del sistema
        child: Column(
          children: [
            _buildHeader(),                 // Barra superior con menú y color activo
            const SizedBox(height: 8),
            _buildGrid(),                   // Grilla 8×8 de pixels ← YA NO TIENE Expanded
            const SizedBox(height: 12),
            _buildQuickColors(),            // Fila de colores rápidos + borrador
            const SizedBox(height: 8),
            // AnimatedSize anima el cambio de altura cuando aparece/desaparece la paleta
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: showPalette ? _buildFullPalette() : const SizedBox.shrink(),
            ),
            const SizedBox(height: 10),
            _buildBottomBar(),              // Botones CLEAR y SEND TO ESP32
            const SizedBox(height: 12),
          ],
        ),
      ),
      // FAB (Floating Action Button) en la esquina inferior derecha
      floatingActionButton: _buildColorWheelFAB(),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  DRAWER — Panel lateral con menú y versión
  // ════════════════════════════════════════════════════════════
  Widget _buildDrawer() {
    return Drawer(
      // El color de fondo viene del drawerTheme definido en MyApp
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabecera del drawer ──────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ícono de la app con borde verde neón
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00FF88).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF00FF88).withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.grid_on_rounded,
                      color: Color(0xFF00FF88),
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Nombre de la app
                  const Text(
                    'LED MATRIX',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Versión — usa las constantes kAppVersion y kAppBuild
                  Text(
                    'v$kAppVersion  ·  $kAppBuild',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: Colors.white30,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),

            // Línea divisoria sutil
            Divider(color: Colors.white.withOpacity(0.07), height: 1),
            const SizedBox(height: 8),

            // ── Items del menú ───────────────────────────────
            // Por ahora los onTap están vacíos — conectar con la lógica real
            _drawerItem(Icons.tune_rounded,        'Ajustes de conexión',   () {}),
            _drawerItem(Icons.wifi_rounded,         'Escanear ESP32',        () {}),
            _drawerItem(Icons.brightness_6_rounded, 'Brillo global',         () {}),
            _drawerItem(Icons.speed_rounded,        'Velocidad de refresco', () {}),
            _drawerItem(Icons.palette_outlined,     'Tema de la app',        () {}),

            // Spacer empuja los items de abajo al fondo del drawer
            const Spacer(),
            Divider(color: Colors.white.withOpacity(0.07), height: 1),

            // ── Items del footer ─────────────────────────────
            _drawerItem(Icons.help_outline_rounded, 'Acerca de', () {
              Navigator.pop(context); // Cierra el drawer antes de abrir el dialog
              _showAboutDialog();
            }),
            _drawerItem(Icons.bug_report_outlined, 'Reportar un bug', () {}),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Helper que construye una fila del drawer (ícono + texto + tap)
  Widget _drawerItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.white10, // Efecto ripple sutil
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: Colors.white38, size: 18),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.white70,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Dialog modal con información de la versión
  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        title: const Text(
          'LED MATRIX',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            letterSpacing: 4,
            color: Colors.white,
          ),
        ),
        content: Text(
          'Versión $kAppVersion ($kAppBuild)\n\n'
          'Controlador visual para matrices LED 8×8 via ESP32.\n\n'
          '© 2025 — MIT License',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: Colors.white54,
            height: 1.8, // Interlineado
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'CERRAR',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                letterSpacing: 2,
                color: Color(0xFF00FF88),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  HEADER — Barra superior
  //  Contiene: botón de menú | título | indicador de color activo
  // ════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 4),
      child: Row(
        children: [
          // Botón hamburguesa → abre el Drawer
          IconButton(
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: const Icon(Icons.menu_rounded, color: Colors.white70, size: 24),
            splashRadius: 22,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          const SizedBox(width: 8),

          // Título y subtítulo
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LED MATRIX',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 6,
                ),
              ),
              Text(
                '8 × 8 — 64 PIXELS',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: Colors.white24,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
          const Spacer(),

          // Cuadradito que muestra el color activo (o el ícono del borrador)
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isEraser ? Colors.black : selectedColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isEraser
                    ? Colors.white24
                    : selectedColor.withOpacity(0.6),
                width: 2,
              ),
              // Glow del color activo (no se muestra en modo borrador)
              boxShadow: isEraser
                  ? null
                  : [
                      BoxShadow(
                        color: selectedColor.withOpacity(0.5),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
            ),
            child: isEraser
                ? const Icon(Icons.auto_fix_high, color: Colors.white38, size: 18)
                : null,
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  GRID 8×8 — Área de pintura principal
  //
  //  FIX del bug de proporción:
  //  Antes usábamos Expanded + AspectRatio. El problema es que
  //  Expanded le daba toda la altura disponible al container, y
  //  AspectRatio no podía recortarla correctamente en pantallas altas.
  //
  //  Solución: LayoutBuilder lee el ANCHO real disponible (constraints.maxWidth)
  //  y fuerza width == height con SizedBox. Así el cuadro siempre
  //  es cuadrado sin importar la proporción de la pantalla.
  // ════════════════════════════════════════════════════════════
  Widget _buildGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // constraints.maxWidth = ancho disponible después del padding
          // Usamos ese valor para ancho Y alto → siempre cuadrado
          final double size = constraints.maxWidth;

          return SizedBox(
            width: size,
            height: size, // ← clave: mismo valor que width
            child: Container(
              // Panel oscuro que contiene la grilla
              decoration: BoxDecoration(
                color: const Color(0xFF111118),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(10),

              child: GridView.builder(
                // NeverScrollableScrollPhysics porque el scroll lo maneja la Column
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 64, // 8 columnas × 8 filas
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,   // 8 columnas
                  mainAxisSpacing: 4,  // Espacio vertical entre celdas
                  crossAxisSpacing: 4, // Espacio horizontal entre celdas
                ),
                itemBuilder: (context, index) {
                  final bool isLit = pixels[index] != Colors.black;
                  return GestureDetector(
                    onTap: () => paintPixel(index),          // Toque simple
                    onPanStart: (_) => paintPixel(index),    // Inicio de arrastre
                    onPanUpdate: (_) => paintPixel(index),   // Movimiento del arrastre
                    child: AnimatedContainer(
                      // Anima el cambio de color suavemente en 80ms
                      duration: const Duration(milliseconds: 80),
                      decoration: BoxDecoration(
                        color: pixels[index],
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          // Borde sutil: más visible si el LED está encendido
                          color: isLit
                              ? pixels[index].withOpacity(0.3)
                              : Colors.white.withOpacity(0.05),
                          width: 0.5,
                        ),
                        // Glow solo cuando el pixel está encendido (≠ negro)
                        boxShadow: isLit
                            ? [
                                BoxShadow(
                                  color: pixels[index].withOpacity(0.7),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  QUICK COLORS — Fila de colores rápidos
  //  [ Borrador ] [ color1 color2 ... color8 ] [ ▾ paleta ]
  // ════════════════════════════════════════════════════════════
  Widget _buildQuickColors() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // ── Botón borrador ───────────────────────────────
          GestureDetector(
            onTap: () => setState(() => isEraser = !isEraser),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                // Fondo más brillante cuando está activo
                color: isEraser
                    ? Colors.white.withOpacity(0.15)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isEraser ? Colors.white38 : Colors.white12,
                  width: 1.5,
                ),
              ),
              child: const Icon(Icons.auto_fix_high,
                  color: Colors.white70, size: 18),
            ),
          ),
          const SizedBox(width: 10),

          // ── Swatches de colores rápidos ──────────────────
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: quickColors.map((color) {
                final bool isSelected = !isEraser && selectedColor == color;
                return GestureDetector(
                  onTap: () => setState(() {
                    selectedColor = color;
                    isEraser = false; // Desactiva el borrador
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    // El swatch seleccionado es levemente más grande
                    width: isSelected ? 34 : 28,
                    height: isSelected ? 34 : 28,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.white12,
                        width: isSelected ? 2.5 : 1,
                      ),
                      // Glow solo en el color seleccionado (y no en negro)
                      boxShadow: isSelected && color != Colors.black
                          ? [
                              BoxShadow(
                                color: color.withOpacity(0.6),
                                blurRadius: 10,
                                spreadRadius: 1,
                              )
                            ]
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(width: 10),

          // ── Botón expandir paleta ────────────────────────
          GestureDetector(
            onTap: togglePalette,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: showPalette
                    ? Colors.white.withOpacity(0.12)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: showPalette ? Colors.white38 : Colors.white12,
                  width: 1.5,
                ),
              ),
              // La flecha rota 180° cuando la paleta está abierta
              child: AnimatedRotation(
                turns: showPalette ? 0.5 : 0, // 0.5 turns = 180°
                duration: const Duration(milliseconds: 300),
                child: const Icon(Icons.expand_more,
                    color: Colors.white70, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  FULL PALETTE — Grilla de 48 colores expandible
  //  Solo se muestra cuando showPalette == true
  //  AnimatedSize en el build() anima su aparición/desaparición
  // ════════════════════════════════════════════════════════════
  Widget _buildFullPalette() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF111118),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        padding: const EdgeInsets.all(10),
        child: GridView.builder(
          shrinkWrap: true, // Se adapta al contenido, no ocupa toda la pantalla
          physics: const NeverScrollableScrollPhysics(),
          itemCount: fullPalette.length, // 48 colores
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 12, // 12 columnas → 4 filas de 12
            mainAxisSpacing: 5,
            crossAxisSpacing: 5,
          ),
          itemBuilder: (context, index) {
            final Color color = fullPalette[index];
            final bool isSelected = !isEraser && selectedColor == color;
            return GestureDetector(
              onTap: () => setState(() {
                selectedColor = color;
                isEraser = false;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    // Borde blanco solo en el seleccionado
                    color: isSelected ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: isSelected && color != Colors.black
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.7),
                            blurRadius: 6,
                          )
                        ]
                      : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  BOTTOM BAR — Botones de acción
  //  [ CLEAR ] [ ─────── SEND TO ESP32 ─────── ]
  // ════════════════════════════════════════════════════════════
  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Botón secundario: limpia la matriz
          Expanded(
            child: _ActionButton(
              label: 'CLEAR',
              icon: Icons.delete_outline,
              onTap: clearMatrix,
              color: Colors.white24,
            ),
          ),
          const SizedBox(width: 12),

          // Botón primario (flex: 2 → doble de ancho): envía al ESP32
          // Su color cambia dinámicamente con el color seleccionado
          Expanded(
            flex: 2,
            child: _ActionButton(
              label: 'SEND TO ESP32',
              icon: Icons.send_rounded,
              onTap: printMatrix,
              // Si el color activo es negro, usa verde neón para que sea visible
              color: selectedColor == Colors.black
                  ? const Color(0xFF00FF88)
                  : selectedColor,
              isPrimary: true,
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  COLOR WHEEL FAB — Botón flotante para abrir el círculo cromático
  //  Tiene un SweepGradient arcoíris con un hueco oscuro en el centro
  // ════════════════════════════════════════════════════════════
  Widget _buildColorWheelFAB() {
    return GestureDetector(
      onTap: _openColorWheel,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Gradiente circular que recorre todos los tonos del espectro
          gradient: const SweepGradient(
            colors: [
              Color(0xFFFF0000), // Rojo
              Color(0xFFFFFF00), // Amarillo
              Color(0xFF00FF00), // Verde
              Color(0xFF00FFFF), // Cyan
              Color(0xFF0000FF), // Azul
              Color(0xFFFF00FF), // Magenta
              Color(0xFFFF0000), // Rojo otra vez para cerrar el círculo
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        // Círculo interior oscuro para crear el efecto de "anillo"
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF0A0A0F), // Mismo color que el fondo de la app
          ),
          child: const Icon(
            Icons.colorize_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  3. ColorWheelSheet — Bottom sheet del círculo cromático
//     Usa el modelo de color HSV (Hue, Saturation, Value):
//       H (Hue)        = tono, 0°–360°, el ángulo en el círculo
//       S (Saturation) = saturación, 0–1, la distancia al centro
//       V (Value)      = brillo, 0–1, controlado por el slider
// ════════════════════════════════════════════════════════════════
class ColorWheelSheet extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorSelected;

  const ColorWheelSheet({
    super.key,
    required this.initialColor,
    required this.onColorSelected,
  });

  @override
  State<ColorWheelSheet> createState() => _ColorWheelSheetState();
}

class _ColorWheelSheetState extends State<ColorWheelSheet> {
  late HSVColor _hsv; // Estado interno en formato HSV
  final double _wheelSize = 260; // Diámetro del círculo en pixels lógicos

  @override
  void initState() {
    super.initState();
    // Convertimos el Color inicial (RGB) a HSV para poder manipularlo
    _hsv = HSVColor.fromColor(widget.initialColor);
  }

  // Getter que convierte el estado HSV actual de vuelta a Color (RGB)
  Color get _currentColor => _hsv.toColor();

  // Se llama cuando el usuario arrastra el dedo sobre el círculo
  void _onWheelPan(Offset localPos) {
    final center = Offset(_wheelSize / 2, _wheelSize / 2);
    final dx = localPos.dx - center.dx; // Distancia horizontal al centro
    final dy = localPos.dy - center.dy; // Distancia vertical al centro
    final radius = _wheelSize / 2;
    final dist = sqrt(dx * dx + dy * dy); // Distancia euclidiana al centro

    // Si el toque está fuera del círculo, ignorar
    if (dist > radius) return;

    // atan2 devuelve el ángulo en radianes (-π a π), lo convertimos a grados (0–360)
    final double angle = (atan2(dy, dx) * 180 / pi + 360) % 360;
    // La saturación es proporcional a la distancia al centro (0 = blanco, 1 = color puro)
    final double sat = (dist / radius).clamp(0.0, 1.0);

    setState(() {
      // Actualizamos H y S, mantenemos V (brillo) sin cambios
      _hsv = HSVColor.fromAHSV(1.0, angle, sat, _hsv.value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min, // El sheet solo ocupa lo necesario
        children: [
          // ── Handle visual (barrita gris arriba) ─────────
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // ── Fila: título + preview del color actual ──────
          Row(
            children: [
              const Text(
                'CÍRCULO CROMÁTICO',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white38,
                  letterSpacing: 3,
                ),
              ),
              const Spacer(),
              // Cuadradito que muestra el color en tiempo real
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _currentColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _currentColor.withOpacity(0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _currentColor.withOpacity(0.5),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Círculo cromático interactivo ────────────────
          // GestureDetector captura el arrastre y el toque
          Center(
            child: GestureDetector(
              onPanStart:  (d) => _onWheelPan(d.localPosition),
              onPanUpdate: (d) => _onWheelPan(d.localPosition),
              onTapDown:   (d) => _onWheelPan(d.localPosition),
              child: SizedBox(
                width: _wheelSize,
                height: _wheelSize,
                // CustomPaint delega el dibujo a _ColorWheelPainter
                child: CustomPaint(
                  painter: _ColorWheelPainter(
                    hue:        _hsv.hue,
                    saturation: _hsv.saturation,
                    value:      _hsv.value,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Slider de brillo (V en HSV) ──────────────────
          Row(
            children: [
              const Text(
                'BRILLO',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: Colors.white30,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BrightnessSlider(
                  value: _hsv.value,
                  // El color del track refleja el tono actual al 100% de brillo
                  color: HSVColor.fromAHSV(1.0, _hsv.hue, _hsv.saturation, 1.0)
                      .toColor(),
                  onChanged: (v) => setState(() {
                    _hsv = HSVColor.fromAHSV(1.0, _hsv.hue, _hsv.saturation, v);
                  }),
                ),
              ),
              const SizedBox(width: 12),
              // Porcentaje numérico del brillo
              Text(
                '${(_hsv.value * 100).round()}%',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: Colors.white38,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Display del código HEX ───────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'HEX  ',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.white24,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  // .value es el ARGB completo, .substring(2) quita los 2 chars del alpha
                  '#${_currentColor.value.toRadixString(16).substring(2).toUpperCase()}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _currentColor,
                    letterSpacing: 3,
                    shadows: [
                      Shadow(
                        color: _currentColor.withOpacity(0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Botón de confirmación ────────────────────────
          GestureDetector(
            onTap: () {
              widget.onColorSelected(_currentColor); // Devuelve el color al padre
              Navigator.pop(context);                // Cierra el sheet
            },
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: _currentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _currentColor.withOpacity(0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _currentColor.withOpacity(0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_rounded, color: _currentColor, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    'SELECCIONAR COLOR',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: _currentColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  4. _ColorWheelPainter — Dibuja el círculo cromático en el canvas
//
//  Se pinta en 4 capas apiladas:
//    1. SweepGradient  → los colores del arcoíris (el "tono")
//    2. RadialGradient → blanco desde el centro (reduce "saturación")
//    3. Color negro    → oscurece todo (reduce "brillo" / value)
//    4. Borde          → contorno sutil
//    5. Dot selector   → punto blanco con el color actual en el centro
// ════════════════════════════════════════════════════════════════
class _ColorWheelPainter extends CustomPainter {
  final double hue;        // 0–360°
  final double saturation; // 0–1
  final double value;      // 0–1

  _ColorWheelPainter({
    required this.hue,
    required this.saturation,
    required this.value,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2;

    // ── Capa 1: Tono (Hue) ──────────────────────────────
    // SweepGradient pinta los colores alrededor del círculo
    final Paint sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: const [
          Color(0xFFFF0000), // 0°   Rojo
          Color(0xFFFFFF00), // 60°  Amarillo
          Color(0xFF00FF00), // 120° Verde
          Color(0xFF00FFFF), // 180° Cyan
          Color(0xFF0000FF), // 240° Azul
          Color(0xFFFF00FF), // 300° Magenta
          Color(0xFFFF0000), // 360° Rojo (cierra el ciclo)
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sweepPaint);

    // ── Capa 2: Saturación ───────────────────────────────
    // Blanco en el centro que se desvanece hacia los bordes.
    // Mezcla con la capa de tono para aclarar los colores centrales.
    final Paint whitePaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, Colors.white.withOpacity(0.0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, whitePaint);

    // ── Capa 3: Brillo (Value) ───────────────────────────
    // Negro semitransparente. Cuando value=1 → opacidad 0 (no oscurece).
    // Cuando value=0 → opacidad 1 (todo negro).
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = Colors.black.withOpacity(1.0 - value),
    );

    // ── Capa 4: Borde del círculo ────────────────────────
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color     = Colors.white.withOpacity(0.08)
        ..style     = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ── Capa 5: Punto selector ───────────────────────────
    // Posición calculada a partir de hue (ángulo) y saturation (radio)
    final double angle   = hue * pi / 180; // Convertir grados a radianes
    final double dotDist = saturation * radius;
    final Offset dotPos  = Offset(
      center.dx + dotDist * cos(angle), // x = centro + r·cos(θ)
      center.dy + dotDist * sin(angle), // y = centro + r·sin(θ)
    );

    // Sombra negra (capa de abajo)
    canvas.drawCircle(dotPos, 13, Paint()..color = Colors.black.withOpacity(0.4));
    // Anillo blanco
    canvas.drawCircle(dotPos, 11, Paint()..color = Colors.white);
    // Relleno con el color actual
    canvas.drawCircle(
      dotPos,
      9,
      Paint()..color = HSVColor.fromAHSV(1.0, hue, saturation, value).toColor(),
    );
  }

  // Solo redibujar si alguno de los valores HSV cambió
  @override
  bool shouldRepaint(_ColorWheelPainter old) =>
      old.hue != hue || old.saturation != saturation || old.value != value;
}

// ════════════════════════════════════════════════════════════════
//  5. _BrightnessSlider — Slider de brillo con estilo personalizado
//     Recibe el valor actual (0–1), el color del track, y un callback
// ════════════════════════════════════════════════════════════════
class _BrightnessSlider extends StatelessWidget {
  final double value;                  // Posición actual del slider (0–1)
  final Color color;                   // Color del track activo
  final ValueChanged<double> onChanged; // Callback al mover el slider

  const _BrightnessSlider({
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 8,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        activeTrackColor:   color,                    // Track izquierdo = color del tono
        inactiveTrackColor: Colors.white10,            // Track derecho = gris oscuro
        thumbColor:         Colors.white,              // Botón deslizable = blanco
        overlayColor:       color.withOpacity(0.2),    // Halo al presionar
      ),
      child: Slider(value: value, onChanged: onChanged),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  6. _ActionButton — Botón animado con efecto de escala al presionar
//     Dos variantes: primario (con color y glow) y secundario (gris)
// ════════════════════════════════════════════════════════════════
class _ActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final bool isPrimary; // false = variante secundaria (gris)

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.color,
    this.isPrimary = false,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // Controlador para la animación de escala
    // lowerBound: 0.95 → se encoge al 95% al presionar
    // upperBound: 1.00 → tamaño normal
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0, // Empieza en tamaño normal
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) => _ctrl.reverse(), // Al presionar → encoge (0.95)
      onTapUp:     (_) { _ctrl.forward(); widget.onTap(); }, // Al soltar → vuelve (1.0) + acción
      onTapCancel: () => _ctrl.forward(), // Si el tap se cancela → vuelve normal
      child: ScaleTransition(
        scale: _ctrl, // Aplica la escala del controlador al widget
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            // Primario: fondo con el color activo; secundario: gris oscuro
            color: widget.isPrimary
                ? widget.color.withOpacity(0.15)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isPrimary
                  ? widget.color.withOpacity(0.6)
                  : Colors.white12,
              width: 1.5,
            ),
            // Glow solo en el botón primario
            boxShadow: widget.isPrimary
                ? [
                    BoxShadow(
                      color: widget.color.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: widget.isPrimary ? widget.color : Colors.white38,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: widget.isPrimary ? widget.color : Colors.white38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}