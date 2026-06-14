#include <Arduino.h>
#include <cmath>

#define USE_WIFI_NINA false
#define USE_WIFI101 true

#include <WiFiWebServer.h>

#include "DFRobot_BMM350.h"

// ================= WIFI SETTINGS =================

const char ssid[] = "Martin";
const char pass[] = "Password";

const int groupNumber = 0;

DFRobot_BMM350_I2C bmm350(&Wire, I2C_ADDRESS);

// ================= MOTOR PINS =================
// Do NOT use pins 5, 7, or 10 with the WiFi shield.

#define LEFT_DIR 2
#define LEFT_PWM 3

#define RIGHT_DIR 4
#define RIGHT_PWM 6

const int MOTOR_SPEED = 255;
const int ROTATE_SPEED = 125;

// ================= Magnetism =================
float GeomagneticFieldStrength;
const float Magneticsensitivity = 3;

// ================= Ultrasound =================
int UltrasonicThreshold = 100;

// ================= Radio Age =================
const int RadioPin = 0;

char buffer[4];
int bufferIndex = 0;
String currentAge = "---";

// ================= IR =================
const int IRPin = 8;
const int IRDetectionThreshold = 2;
String IRPresence = "ABSENT";
unsigned long lastIRWindowStart = 0;
const unsigned long IR_WINDOW_DURATION = 300;
int irPulseCount = 0;
int lastIRPinStatus = LOW;

// ================= WEB SERVER =================
WiFiWebServer server(80);

// ================= MOTOR FUNCTIONS =================
void roverStop()
{
  analogWrite(LEFT_PWM, 0);
  analogWrite(RIGHT_PWM, 0);

  digitalWrite(LEFT_DIR, LOW);
  digitalWrite(RIGHT_DIR, LOW);
}

void setLeftMotor(bool forward, int speed)
{
  digitalWrite(LEFT_DIR, forward ? HIGH : LOW);
  analogWrite(LEFT_PWM, speed);
}

void setRightMotor(bool forward, int speed)
{
  digitalWrite(RIGHT_DIR, forward ? LOW : HIGH);
  analogWrite(RIGHT_PWM, speed);
}

void handleForward()
{
  setLeftMotor(true, MOTOR_SPEED);
  setRightMotor(true, MOTOR_SPEED);
  server.send(200, "text/plain", "FORWARD");
}

void handleBackward()
{
  setLeftMotor(false, MOTOR_SPEED);
  setRightMotor(false, MOTOR_SPEED);
  server.send(200, "text/plain", "BACKWARD");
}

void handleLeft()
{
  setLeftMotor(false, ROTATE_SPEED);
  setRightMotor(true, ROTATE_SPEED);
  server.send(200, "text/plain", "LEFT");
}

void handleRight()
{
  setLeftMotor(true, ROTATE_SPEED);
  setRightMotor(false, ROTATE_SPEED);
  server.send(200, "text/plain", "RIGHT");
}

void handleStop()
{
  roverStop();
  server.send(200, "text/plain", "STOPPED");
}

void handleForwardLeft()
{
  setLeftMotor(true, ROTATE_SPEED);
  setRightMotor(true, MOTOR_SPEED);
  server.send(200, "text/plain", "FORWARD LEFT");
}

void handleForwardRight()
{
  setLeftMotor(true, MOTOR_SPEED);
  setRightMotor(true, ROTATE_SPEED);
  server.send(200, "text/plain", "FORWARD RIGHT");
}
// ================= WEB HANDLERS =================

void handleRoot()
{
  char rootPage[] PROGMEM= R"rawliteral(
<html>
<head>
<style>
body {font-family: Arial; text-align:center; margin-top:40px;}
button {padding:20px; margin:10px; font-size:20px; width:160px;}
</style>
</head>
<body>
<h1>Rover Control</h1>

<button onmousedown='sendCommand("/forward")' onmouseup='sendCommand("/stop")'>FORWARD</button><br>
<button onmousedown='sendCommand("/left")' onmouseup='sendCommand("/stop")'>LEFT</button>
<button onmousedown='sendCommand("/right")' onmouseup='sendCommand("/stop")'>RIGHT</button><br>
<button onmousedown='sendCommand("/backward")' onmouseup='sendCommand("/stop")'>BACKWARD</button><br><br>

<button onmousedown='sendCommand("/forwardLeft")' onmouseup='sendCommand("/stop")'>DIAGONAL LEFT</button>
<button onmousedown='sendCommand("/forwardRight")' onmouseup='sendCommand("/stop")'>DIAGONAL RIGHT</button><br><br>


<button onclick="location.href='/dashboard'">Dashboard</button>

<script>
function sendCommand(command)
{
  var xhttp = new XMLHttpRequest();
  xhttp.onreadystatechange = function()
  {
    if (this.readyState == 4 && this.status == 200)
    {
      document.getElementById('state').innerHTML = this.responseText;
    }
  };
  xhttp.open('GET', command, true);
  xhttp.send();
}
</script>
</body>
</html>
)rawliteral";
  server.send(200, "text/html", rootPage);
}

void handleDashboard()
{
  String page = R"rawliteral(
<html>
<body onload="setInterval(up, 500); up()">
  <h1>Rover Sensor Dashboard</h1>
  <p><b>Magnetism:</b> Geo: <span id="m-g">--</span> | Dir: <span id="m-d">--</span> | Raw: <span id="m-r">--</span> | <a href="#" onclick="fetch('/calibrateMag')">Calibrate</a></p>
  <p><b>Ultrasound:</b> Raw: <span id="u-r">--</span> | Signal: <span id="u-p">ABSENT</span></p>
  <p><b>Infrared:</b> Pulse: <span id="i-p">ABSENT</span> | Rate: <span id="i-r">--</span> p/s | 312_prob: <span id="prob_312">--</span> | 547_prob: <span id="prob_547">--</span>|<a href="#" onclick="mIR()">Measure</a></p>
  <p><b>Radio Age:</b> <span id="a-v">--</span></p>
  <p><a href="/">Back to Motor Control</a></p>

  <script>
    let active = true, $ = id => document.getElementById(id);
    function up() {
      if (active) fetch("/sensorData").then(r => r.json()).then(d => {
        $("m-d").innerText = d.magDirection; $("m-r").innerText = d.magRaw;
        $("m-g").innerText = d.magGeo; $("u-r").innerText = d.ultraRaw;
        $("u-p").innerText = d.ultraPresence; $("i-p").innerText = d.irDetection;
        $("a-v").innerText = d.age;
      });
    }
    function mIR() {
      active = false;
      fetch("/irRate").then(r => r.json()).then(d => { $("i-r").innerText = d.irRate; $("prob_312").innerText = d.prob_312;$("prob_547").innerText = d.prob_547; active = true; });
    }
  </script>
</body>
</html>
)rawliteral";
  server.send(200, "text/html", page);
}

void handleNotFound()
{
  server.send(404, "text/plain", "Not found");
}

// ================= Magnetometer Initialization =================
void setupMagneticSensor()
{
  while (bmm350.begin()) {
    Serial.println("bmm350 init failed, Please try again!");
    delay(1000);
  }

  Serial.println("bmm350 init success!");

  bmm350.setOperationMode(eBmm350NormalMode);
  bmm350.setPresetMode(BMM350_PRESETMODE_HIGHACCURACY, BMM350_DATA_RATE_25HZ);
  bmm350.setMeasurementXYZ();
}

// ================= Dashboard Data =================

void MagCalibration()
{
  setupMagneticSensor();
  GeomagneticFieldStrength = bmm350.getGeomagneticData().float_z;
  server.send(200,"text/plain","Calibration Complete");
}

double IR_312_probability(double r){
  double prob;
  prob = std::log(547.0/312.0);
  prob *= r;
  prob -= 235.0;
  prob = std::exp(prob);
  prob += 1.0;
  prob = 1.0/prob;
  prob *= 100.0;
  prob = (std::round)(100.0 * prob) / 100.0;
  return prob;
}

void IRMeasurement()
{
  double PulseCnt = 0;
  int StartTime, EndTime, duration;
  double rate;
  int SampleCnt = 0;
  int currentPinStatus, lastPinStatus;
  
  StartTime = millis();
  lastPinStatus = digitalRead(IRPin);
  while(SampleCnt < 10e5){
    currentPinStatus = digitalRead(IRPin);
    if (currentPinStatus == HIGH && lastPinStatus == LOW) {
      PulseCnt++;
    }
    lastPinStatus = currentPinStatus;
    SampleCnt++;
  }
  EndTime = millis();
  duration = EndTime - StartTime;
  rate = PulseCnt / duration * 1000;

  double prob_312, prob_547;
  prob_312 = IR_312_probability(rate);
  prob_547 = 100.0 - prob_312;
  String irData = "{";
  irData += "\"irRate\":\"" + String(rate) + "\",";
  irData += "\"prob_312\":\"" + String(prob_312) + "%\",";
  irData += "\"prob_547\":\"" + String(prob_547) + "%\"";
  irData += "}";
  server.send(200, "application/json", irData);
}

void GeneralDataRequest()
{
  sBmm350MagData_t magData = bmm350.getGeomagneticData();
  float fieldstrength = magData.float_z;
  String magDirection;
  if (fieldstrength < GeomagneticFieldStrength - Magneticsensitivity) {
    magDirection = "UP";
  }
  else if (fieldstrength > GeomagneticFieldStrength + Magneticsensitivity) {
    magDirection = "DOWN";
  }
  else {
    magDirection = "WEAK";
  }

  int UltrasonicVoltage = analogRead(A0);
  String ultrasoundState;
  if (UltrasonicVoltage >= UltrasonicThreshold) {
    ultrasoundState = "PRESENT";
  } else {
    ultrasoundState = "ABSENT";
  }

  String data = "{";
  data += "\"magDirection\":\"" + magDirection + "\",";
  data += "\"magRaw\":\"" + String(fieldstrength) + " μT\",";
  data += "\"magGeo\":\"" + String(GeomagneticFieldStrength) + " μT\",";
  data += "\"ultraRaw\":\"" + String(UltrasonicVoltage) + "\",";
  data += "\"ultraPresence\":\"" + ultrasoundState + "\",";
  data += "\"irDetection\":\"" + IRPresence + "\",";
  data += "\"age\":\"" + currentAge+ "\"";
  data += "}";
  server.send(200, "application/json", data);
}

// ================= Background update =================
void IRUpdate(){
  int currentPinStatus = digitalRead(IRPin);
  if (currentPinStatus == HIGH && lastIRPinStatus == LOW) {
    irPulseCount++;
  }
  lastIRPinStatus = currentPinStatus;
  if (millis() - lastIRWindowStart >= IR_WINDOW_DURATION) {
    if (irPulseCount > IRDetectionThreshold) {
      IRPresence = "PRESENT";
    } else {
      IRPresence = "ABSENT";
    }
    irPulseCount = 0;
    lastIRWindowStart = millis();
  }

}


void AgeUpdate() {
  while (Serial1.available() > 0) {
    char receivedChar = Serial1.read();
    if (receivedChar == '#') {
      bufferIndex = 0;
      buffer[bufferIndex] = receivedChar;
      bufferIndex++;
    } 
    else if (bufferIndex > 0 && bufferIndex < 4) {
      if (receivedChar >= '0' && receivedChar <= '9') {
        buffer[bufferIndex] = receivedChar;
        bufferIndex++;
        if (bufferIndex == 4) {
          bufferIndex = 0;
          currentAge = String(buffer[1]) + "." + String(buffer[2]) + String(buffer[3]) + " billion years";
        }
      } else {
        bufferIndex = 0;
      }
    }
  }
}


// ================= SETUP =================

void setup(){
  pinMode(LEFT_DIR, OUTPUT);
  pinMode(LEFT_PWM, OUTPUT);

  pinMode(RIGHT_DIR, OUTPUT);
  pinMode(RIGHT_PWM, OUTPUT);

  roverStop();

  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, LOW);

  pinMode(RadioPin, INPUT);

  pinMode(IRPin, INPUT);

  Serial.begin(9600);
  Serial1.begin(600);

  while (!Serial && millis() < 10000);

  Serial.println("Starting Rover Web Server");

  if (WiFi.status() == WL_NO_SHIELD)
  {
    Serial.println("WiFi shield not present");

    while (true);
  }

  if (groupNumber)
  {
    WiFi.config(IPAddress(192, 168, 0, groupNumber + 1));
  }

  Serial.print("Connecting to WPA SSID: ");
  Serial.println(ssid);

  while (WiFi.begin(ssid, pass) != WL_CONNECTED)
  {
    delay(500);
    Serial.print(".");
  }

  Serial.println();
  Serial.println("Connected to WiFi");

  setupMagneticSensor();
  GeomagneticFieldStrength = bmm350.getGeomagneticData().float_z;

  server.on("/", handleRoot);
  server.on("/dashboard", handleDashboard);


  server.on("/forward", handleForward);
  server.on("/backward", handleBackward);
  server.on("/left", handleLeft);
  server.on("/right", handleRight);
  server.on("/stop", handleStop);
  server.on("/forwardLeft", handleForwardLeft);
  server.on("/forwardRight", handleForwardRight);

  server.on("/calibrateMag", MagCalibration);
  server.on("/sensorData", GeneralDataRequest);
  server.on("/irRate", IRMeasurement);

  server.onNotFound(handleNotFound);

  server.begin();

  Serial.print("HTTP server started @ ");
  Serial.println(static_cast<IPAddress>(WiFi.localIP()));
}

// ================= LOOP =================

void loop()
{
  server.handleClient();
  IRUpdate();
  AgeUpdate();
}