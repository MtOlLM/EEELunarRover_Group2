const int rxPin = 0;
const unsigned long bitDelay = 1667;
const unsigned long halfBitDelay = 833;

char buffer[4];
int bufferIndex = 0;

void setup() {
  Serial.begin(9600);
  while (!Serial) { ; }
  
  pinMode(rxPin, INPUT);
  Serial.println("Custom Software Decoder Ready. Listening on Pin 0...");
}

void loop() {
  if (digitalRead(rxPin) == LOW) { 
  
    delayMicroseconds(halfBitDelay);
 
    if (digitalRead(rxPin) == LOW) {
      
      delayMicroseconds(bitDelay);
      
      char receivedChar = 0;
      
      for (int i = 0; i < 8; i++) {
        int bitVal = digitalRead(rxPin);
        if (bitVal == HIGH) {
          receivedChar |= (1 << i);
        }
        
        delayMicroseconds(bitDelay);
      }
      processIncomingChar(receivedChar);
    }
  }
}

void processIncomingChar(char inChar) {
  if (inChar == '#') {
    bufferIndex = 0;
    buffer[bufferIndex] = inChar;
    bufferIndex++;
  } 
  else if (bufferIndex > 0 && bufferIndex < 4) {
    if (inChar >= '0' && inChar <= '9') {
      buffer[bufferIndex] = inChar;
      bufferIndex++;
      
      if (bufferIndex == 4) {
        parseAge(buffer);
        bufferIndex = 0;
      }
    } else {
      bufferIndex = 0; 
    }
  }
}

void parseAge(char* data) {
  float hundreds = (data[1] - '0') * 1.0;
  float tens     = (data[2] - '0') * 0.1;
  float ones     = (data[3] - '0') * 0.01;
  float ageInBillionYears = hundreds + tens + ones;
  
  Serial.print("Rock Detected! Raw: ");
  Serial.print(data[0]); Serial.print(data[1]); Serial.print(data[2]); Serial.print(data[3]);
  Serial.print(" -> Age: ");
  Serial.print(ageInBillionYears, 2);
  Serial.println(" billion years");
}