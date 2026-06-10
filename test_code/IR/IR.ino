const int IRPin = 1;
bool IRFlag = false;
bool PulseFlag = false;
double PulseCnt = 0;
int StartTime, EndTime, duration;
double rate;
int SampleCnt = 0;
void setup() {
  Serial.begin(9600);
  while (!Serial) { ; }
  
  pinMode(IRPin, INPUT);
  Serial.println("Listening on Pin 1...");

  IRFlag = true;
  StartTime = millis();
}

void loop() {
  if(IRFlag){
    SampleCnt++;
    if (digitalRead(IRPin) == HIGH && !PulseFlag) { 
      PulseCnt++;
      PulseFlag = true;
    }
    if(digitalRead(IRPin) == LOW && PulseFlag){
      PulseFlag = false;
    }
  }
  if(SampleCnt >= 1000000){
    IRFlag = false;
    SampleCnt = 0;
    EndTime = millis();
    duration = EndTime - StartTime;
    rate = PulseCnt / duration *1000;
    Serial.print("rate: ");
    Serial.println(rate);
    Serial.print("Duration: ");
    Serial.println(duration);
  }
}
