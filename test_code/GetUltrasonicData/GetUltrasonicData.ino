void setup() 
{
  Serial.begin(115200);
}

void loop()
{
  int UltrasonicVoltage = analogRead(A0);
  if(UltrasonicVoltage >= 100){
    //present
  }
  else{
    //absent
  }
  Serial.println(UltrasonicVoltage);
  delay(300);
}
