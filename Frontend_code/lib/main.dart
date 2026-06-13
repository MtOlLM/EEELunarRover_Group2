import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DPadScreen(),
    );
  }
}

class DPadScreen extends StatefulWidget {
  const DPadScreen({super.key});

  @override
  State<DPadScreen> createState() => _DPadScreenState();
}

class _DPadScreenState extends State<DPadScreen> {
  String _lastSentInput = "None";
  DPadDirection? _activeDirection; 

  final Set<LogicalKeyboardKey> _pressedKeys = {};

  // =========================================================================
  // STATE VARIABLES (Saves incoming data from your Arduino JSON endpoints)
  // =========================================================================
  String _ultraPresence = "ABSENT";
  String _ultraRaw = "0";

  String _magGeoField = "0.0 μT";
  String _magField = "0.0 μT";
  String _magDirection = "WEAK";

  String _irPresence = "ABSENT";
  double _irPulseRate = 0.0; 
  
  // IR Probability fields mapped from Arduino logic
  String _prob312 = "0.0%";
  String _prob547 = "0.0%";

  String _rockAge = "---";
  String _detectedRockType = "No Rock Detected";
  bool _isDataConfirmed = false;

  // =========================================================================
  // ROVER CONNECTION CONFIG & OPTIMIZATION LOCKS
  // =========================================================================
  final String _roverBaseUrl = 'http://172.20.10.10'; 
  final FocusNode _keyboardFocusNode = FocusNode();
  
  // Persistent client architecture
  final http.Client _httpClient = http.Client();
  
  Timer? _pollingTimer; 
  bool _isIrMeasuring = false;
  bool _isSendingCommand = false;
  String _lastSentCommandPath = "";

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  // Runs a background poll every 500ms matching your Arduino refresh rate
  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_isIrMeasuring) {
        _requestSensorData();
      }
    });
  }

  // Maps incoming Arduino values safely to Flutter state fields
  void _processSensorUpdate(Map<String, dynamic> sensor) {
    setState(() {
      // 1. Ultrasound Mappings
      if (sensor.containsKey("ultraPresence")) _ultraPresence = sensor["ultraPresence"] ?? "ABSENT";
      if (sensor.containsKey("ultraRaw")) _ultraRaw = sensor["ultraRaw"]?.toString() ?? "0";

      // 2. Magnetic Mappings
      if (sensor.containsKey("magDirection")) _magDirection = sensor["magDirection"] ?? "WEAK";
      if (sensor.containsKey("magRaw")) _magField = sensor["magRaw"]?.toString() ?? "0.0 μT";
      if (sensor.containsKey("magGeo")) _magGeoField = sensor["magGeo"]?.toString() ?? "0.0 μT";

      // 3. Infrared Mappings
      if (sensor.containsKey("irDetection")) _irPresence = sensor["irDetection"] ?? "ABSENT";
      if (sensor.containsKey("irRate")) {
        _irPulseRate = double.tryParse(sensor["irRate"].toString()) ?? 0.0;
      }
      
      // Captured probability elements calculated by your Arduino
      if (sensor.containsKey("prob_312")) {
        _prob312 = sensor["prob_312"]?.toString() ?? "0.0%";
      }
      if (sensor.containsKey("prob_547")) {
        _prob547 = sensor["prob_547"]?.toString() ?? "0.0%";
      }

      // 4. Radio Age Mappings
      if (sensor.containsKey("age")) _rockAge = sensor["age"] ?? "---";

      _isDataConfirmed = (_irPresence == "PRESENT");

      // =====================================================================
      // MATERIAL IDENTIFICATION MATRIX
      // =====================================================================
      String rock = "Unknown Material";
      String mgLower = _magDirection.trim().toLowerCase();

      if (_ultraPresence == "ABSENT" && mgLower == "weak") {
        rock = "No Rock Detected";
      } else {
        if (_ultraPresence == "PRESENT" && mgLower == "down") {
          rock = "Basaltoid";
        } else if (_ultraPresence == "ABSENT" && mgLower == "down") {
          rock = "Gravion";
        } else if (_ultraPresence == "PRESENT" && mgLower == "up") {
          rock = "Regolix";
        } else if (_ultraPresence == "ABSENT" && mgLower == "up") {
          rock = "Lunarite";
        }
      }

      _detectedRockType = rock;
    });
  }

  // =========================================================================
  // DEBOUNCED HTTP MOTOR COMMANDS (WITH 200MS ANTI-HANG TIMEOUT FALLBACK)
  // =========================================================================
  Future<void> _sendMotorCommand(String command, [DPadDirection? direction]) async {
    String path = command.startsWith('/') ? command : '/$command';
    
    // Drop redundant duplicate instructions to stop network floods
    if (path == _lastSentCommandPath && _isSendingCommand) {
      return; 
    }

    // Update operational state instantly for immediate UI rendering responsiveness
    setState(() {
      _lastSentInput = path;
      _activeDirection = direction; 
    });

    _lastSentCommandPath = path;
    _isSendingCommand = true;

    try {
      final response = await _httpClient.get(
        Uri.parse('$_roverBaseUrl$path'),
        headers: {
          "Connection": "close", // Tell hardware to drop transactional socket link cleanly
          "Cache-Control": "no-cache"
        },
      ).timeout(
        const Duration(milliseconds: 200), // Hard cutoff: stops "Future not completed" hang
        onTimeout: () {
          debugPrint("Motor command timed out! Arduino is likely blocked in a hardware loop.");
          _isSendingCommand = false; // Reset lock locally so the next keypress works
          return http.Response('Timeout', 408); // Simulate a clean error code response
        },
      );

      if (response.statusCode != 200 && response.statusCode != 408) {
        debugPrint("Rover returned error status: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Network tracking frame drop error: $e");
    } finally {
      _isSendingCommand = false;
    }
  }
Future<void> _requestSensorData() async {
    if (_activeDirection != null || _isSendingCommand) return;

    try {
      final response = await _httpClient.get(
        Uri.parse('$_roverBaseUrl/sensorData'),
        headers: {"Connection": "close"},
      ).timeout(
        const Duration(milliseconds: 400), // Bumped slightly for debugging visibility
        onTimeout: () {
          debugPrint("❌ NETWORK TIMEOUT: Arduino took too long to reply to Flutter.");
          return http.Response('Timeout', 408);
        },
      );

      if (response.statusCode == 200) {
        debugPrint("📡 RAW RECEIVED JSON: ${response.body}"); // <-- CHECK YOUR CONSOLE FOR THIS
        
        try {
          final Map<String, dynamic> sensor = jsonDecode(response.body);
          debugPrint("✅ JSON parsed successfully into Map.");
          _processSensorUpdate(sensor);
        } catch (jsonError) {
          debugPrint("❌ JSON PARSING FAILED: This means your Arduino JSON structure is broken. Error: $jsonError");
        }
      } else {
        debugPrint("⚠️ Server responded with status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ Connection error requesting sensor data: $e");
    }
  }

  Future<void> _calibrateMagnetometer() async {
    setState(() {
      _lastSentInput = "/calibrateMag";
    });
    try {
      final response = await _httpClient.get(
        Uri.parse('$_roverBaseUrl/calibrateMag'),
        headers: {"Connection": "close"},
      ).timeout(
        const Duration(seconds: 2),
        onTimeout: () => http.Response('Timeout', 408),
      );
      if (response.statusCode == 200) {
        debugPrint("Magnetometer calibration baseline set.");
        _requestSensorData();
      }
    } catch (e) {
      debugPrint("Network error executing calibration: $e");
    }
  }

  Future<void> _requestIrRate() async {
    setState(() {
      _lastSentInput = "/irRate";
      _isIrMeasuring = true; 
    });
    try {
      final response = await _httpClient.get(
        Uri.parse('$_roverBaseUrl/irRate'),
        headers: {"Connection": "close"},
      ).timeout(
        const Duration(seconds: 4), // IR sampling logic takes longer on Arduino
        onTimeout: () {
          setState(() { _isIrMeasuring = false; });
          return http.Response('Timeout', 408);
        },
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> irData = jsonDecode(response.body);
        _processSensorUpdate(irData);
      }
    } catch (e) {
      debugPrint("Network error executing IR rate request: $e");
    } finally {
      setState(() {
        _isIrMeasuring = false;
      });
    }
  }

  void _checkKeyboardCombinations() {
    final bool containsW = _pressedKeys.contains(LogicalKeyboardKey.keyW);
    final bool containsA = _pressedKeys.contains(LogicalKeyboardKey.keyA);
    final bool containsS = _pressedKeys.contains(LogicalKeyboardKey.keyS);
    final bool containsD = _pressedKeys.contains(LogicalKeyboardKey.keyD);

    String targetCommand = "/stop";
    DPadDirection? targetDirection;

    if (containsW && containsA) {
      targetCommand = "/forwardLeft";
      targetDirection = DPadDirection.forwardLeft;
    } else if (containsW && containsD) {
      targetCommand = "/forwardRight";
      targetDirection = DPadDirection.forwardRight;
    } else if (containsW) {
      targetCommand = "/forward";
      targetDirection = DPadDirection.forward;
    } else if (containsS) {
      targetCommand = "/backward";
      targetDirection = DPadDirection.backward;
    } else if (containsA) {
      targetCommand = "/left";
      targetDirection = DPadDirection.left;
    } else if (containsD) {
      targetCommand = "/right";
      targetDirection = DPadDirection.right;
    }

    _sendMotorCommand(targetCommand, targetDirection);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      _pressedKeys.add(event.logicalKey);
      _checkKeyboardCombinations();
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(event.logicalKey);
      _checkKeyboardCombinations();
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_keyboardFocusNode);
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      
      appBar: AppBar(
        title: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _detectedRockType.toUpperCase(),
              style: const TextStyle(
                color: Colors.greenAccent, 
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "STATUS: ${_isDataConfirmed ? 'VERIFIED' : 'UNVERIFIED'}",
              style: TextStyle(
                color: _isDataConfirmed ? Colors.green : Colors.redAccent,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF161622),
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: Colors.white10, width: 1)),
      ),
      
      body: KeyboardListener(
        focusNode: _keyboardFocusNode,
        onKeyEvent: _handleKeyEvent,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161622),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Center(
                    child: Text(
                      "AGE: $_rockAge",
                      style: const TextStyle(
                        color: Colors.orangeAccent, 
                        fontSize: 15, 
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // D-PAD WIDGET INTERFACE
                Center(
                  child: CustomDPad(
                    size: 170,
                    buttonColor: const Color(0xFF1E1E2C),
                    iconColor: const Color(0xFF00E5FF),
                    activeDirection: _activeDirection,
                    onDirectionHoldStart: (direction) {
                      String command = "/stop";
                      switch(direction) {
                        case DPadDirection.forward: command = "/forward"; break;
                        case DPadDirection.backward: command = "/backward"; break;
                        case DPadDirection.left: command = "/left"; break;
                        case DPadDirection.right: command = "/right"; break;
                        case DPadDirection.forwardLeft: command = "/forwardLeft"; break;
                        case DPadDirection.forwardRight: command = "/forwardRight"; break;
                      }
                      _sendMotorCommand(command, direction);
                    },
                    onDirectionHoldEnd: () {
                      _sendMotorCommand("/stop", null);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    "PROPULSION COMM: $_lastSentInput",
                    style: const TextStyle(color: Colors.amber, fontSize: 10, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 16),

                // HARDWARE ACTION CONTROL ROW
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.compass_calibration, size: 12),
                        label: const Text("CALIBRATE MAG", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.withValues(alpha: 0.08),
                          foregroundColor: Colors.amberAccent,
                          side: const BorderSide(color: Colors.amber, width: 1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _calibrateMagnetometer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: _isIrMeasuring 
                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.pinkAccent))
                          : const Icon(Icons.radar, size: 12),
                        label: Text(_isIrMeasuring ? "MEASURING..." : "REQUEST IR", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.pink.withValues(alpha: 0.08),
                          foregroundColor: Colors.pinkAccent,
                          side: const BorderSide(color: Colors.pink, width: 1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _isIrMeasuring ? null : _requestIrRate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ULTRASOUND DATA READOUT
                _buildDiagnosticCard(
                  title: "ULTRASOUND TELEMETRY",
                  titleColor: Colors.cyanAccent,
                  children: [
                    _buildTelemetryLine("PRESENCE", _ultraPresence, _ultraPresence == "PRESENT" ? Colors.greenAccent : Colors.redAccent),
                    _buildTelemetryLine("RAW ANALOG VALUE", _ultraRaw, Colors.white),
                  ],
                ),
                const SizedBox(height: 16),

                // MAGNETOMETER DATA READOUT
                _buildDiagnosticCard(
                  title: "MAGNETIC INTERFACE",
                  titleColor: Colors.amberAccent,
                  children: [
                    _buildTelemetryLine("GEOMAGNETIC FIELD STRENGTH", _magGeoField, Colors.white70),
                    _buildTelemetryLine("MAGNETIC FIELD STRENGTH", _magField, Colors.white),
                    _buildTelemetryLine("POLARITY DIRECTION", _magDirection.toUpperCase(), 
                       _magDirection == "WEAK" ? Colors.white38 : Colors.amberAccent),
                  ],
                ),
                const SizedBox(height: 16),

                // INFRARED DATA & PROBABILITY CALCULATION READOUT
                _buildDiagnosticCard(
                  title: "INFRARED ANALYSIS & SIGNAL STATE PROBABILITY",
                  titleColor: Colors.pinkAccent,
                  children: [
                    _buildTelemetryLine("PRESENCE", _irPresence, _irPresence == "PRESENT" ? Colors.greenAccent : Colors.redAccent),
                    _buildTelemetryLine("PULSE RATE", "${_irPulseRate.toStringAsFixed(2)} p/s", Colors.white),
                    const Divider(color: Colors.white10, height: 20),
                    const Text(
                      "INFRARED FREQUENCY DISTRIBUTION:", 
                      style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _buildTelemetryLine("312 Hz Signal Confidence", _prob312, Colors.pinkAccent),
                    _buildTelemetryLine("547 Hz Signal Confidence", _prob547, Colors.cyanAccent),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiagnosticCard({required String title, required Color titleColor, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161622),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: titleColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTelemetryLine(String metricName, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(metricName, style: const TextStyle(color: Colors.white60, fontSize: 13)),
          Text(
            value,
            style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _keyboardFocusNode.dispose();
    _httpClient.close(); 
    super.dispose();
  }
}

enum DPadDirection {
  forward,
  backward,
  left,
  right,
  forwardLeft,
  forwardRight,
}

class CustomDPad extends StatelessWidget {
  final Function(DPadDirection direction) onDirectionHoldStart;
  final VoidCallback onDirectionHoldEnd;
  final double size;
  final Color buttonColor;
  final Color iconColor;
  final DPadDirection? activeDirection;

  const CustomDPad({
    super.key,
    required this.onDirectionHoldStart,
    required this.onDirectionHoldEnd,
    this.size = 240.0,
    this.buttonColor = Colors.grey,
    this.iconColor = Colors.white,
    this.activeDirection,
  });

  @override
  Widget build(BuildContext context) {
    double buttonSize = size / 3;
    return SizedBox(
      width: size,
      height: size,
      child: GridView.count(
        crossAxisCount: 3,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          _buildPadButton(
            icon: Icons.north_west,
            direction: DPadDirection.forwardLeft,
            size: buttonSize,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(12)),
          ),
          _buildPadButton(
            icon: Icons.arrow_upward,
            direction: DPadDirection.forward,
            size: buttonSize,
          ),
          _buildPadButton(
            icon: Icons.north_east,
            direction: DPadDirection.forwardRight,
            size: buttonSize,
            borderRadius: const BorderRadius.only(topRight: Radius.circular(12)),
          ),
          _buildPadButton(
            icon: Icons.arrow_back,
            direction: DPadDirection.left,
            size: buttonSize,
          ),
          const SizedBox.shrink(),
          _buildPadButton(
            icon: Icons.arrow_forward,
            direction: DPadDirection.right,
            size: buttonSize,
          ),
          const SizedBox.shrink(), 
          _buildPadButton(
            icon: Icons.arrow_downward,
            direction: DPadDirection.backward,
            size: buttonSize,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox.shrink(), 
        ],
      ),
    );
  }

  Widget _buildPadButton({
    required IconData icon,
    required DPadDirection direction,
    required double size,
    BorderRadius? borderRadius,
  }) {
    final bool isActive = activeDirection == direction;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTapDown: (_) => onDirectionHoldStart(direction),
        onTapUp: (_) => onDirectionHoldEnd(),
        onTapCancel: () => onDirectionHoldEnd(),
        customBorder: RoundedRectangleBorder(
          borderRadius: borderRadius ?? BorderRadius.circular(4),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 60), 
          decoration: BoxDecoration(
            color: isActive ? Colors.white : buttonColor,
            borderRadius: borderRadius ?? BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? Colors.white : Colors.black26, 
              width: 1,
            ),
          ),
          child: Center(
            child: Icon(
              icon,
              color: isActive ? const Color(0xFF0F0F13) : iconColor,
              size: size * (isActive ? 0.50 : 0.45), 
            ),
          ),
        ),
      ),
    );
  }
}