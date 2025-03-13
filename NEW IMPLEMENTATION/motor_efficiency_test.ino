#include "HX711.h"
#include <Wire.h>

// Pin definitions
#define MOTOR_PWM_PIN 25
#define MOTOR_DIR_PIN 26
#define LOADCELL_DOUT_PIN 4
#define LOADCELL_SCK_PIN 5
#define RPM_SENSOR_PIN 18
#define CURRENT_SENSOR_PIN 34
#define VOLTAGE_SENSOR_PIN 35

// Constants
#define TORQUE_ARM_LENGTH 0.05 // Distance from motor axis to load cell in meters
#define MOTOR_VOLTAGE 12.0     // Nominal motor voltage
#define PULSES_PER_REVOLUTION 12 // Adjust based on your RPM sensor

// Variables
volatile unsigned long pulseCount = 0;
unsigned long lastTime = 0;
float rpm = 0;
float torque = 0;
float current = 0;
float voltage = 0;
float mechanicalPower = 0;
float electricalPower = 0;
float efficiency = 0;

HX711 scale;

void IRAM_ATTR countPulse() {
  pulseCount++;
}

void setup() {
  Serial.begin(115200);
  
  // Initialize motor control pins
  pinMode(MOTOR_PWM_PIN, OUTPUT);
  pinMode(MOTOR_DIR_PIN, OUTPUT);
  digitalWrite(MOTOR_DIR_PIN, HIGH); // Set direction
  
  // Initialize RPM sensor
  pinMode(RPM_SENSOR_PIN, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(RPM_SENSOR_PIN), countPulse, RISING);
  
  // Initialize load cell
  scale.begin(LOADCELL_DOUT_PIN, LOADCELL_SCK_PIN);
  scale.set_scale(420.0); // Replace with your calibration value
  scale.tare();
  
  Serial.println("Motor Efficiency Test Ready");
  Serial.println("PWM,RPM,Torque(Nm),Current(A),Voltage(V),MechPower(W),ElecPower(W),Efficiency(%)");
}

void loop() {
  // Test motor at different PWM values
  for (int pwm = 50; pwm <= 255; pwm += 25) {
    analogWrite(MOTOR_PWM_PIN, pwm);
    delay(3000); // Allow motor to reach steady state
    
    // Measure RPM
    pulseCount = 0;
    lastTime = millis();
    delay(1000);
    rpm = (pulseCount * 60.0) / PULSES_PER_REVOLUTION;
    
    // Measure torque from load cell
    float force = scale.get_units();
    torque = force * TORQUE_ARM_LENGTH;
    
    // Measure electrical values
    current = analogReadMilliVolts(CURRENT_SENSOR_PIN) / 185.0; // Adjust based on your sensor
    voltage = analogReadMilliVolts(VOLTAGE_SENSOR_PIN) * (MOTOR_VOLTAGE / 4096.0); // Adjust based on your divider
    
    // Calculate power and efficiency
    mechanicalPower = torque * (rpm * 2.0 * PI / 60.0); // T * ω
    electricalPower = voltage * current;
    efficiency = (electricalPower > 0) ? (mechanicalPower / electricalPower) * 100.0 : 0;
    
    // Output data
    Serial.print(pwm); Serial.print(",");
    Serial.print(rpm); Serial.print(",");
    Serial.print(torque); Serial.print(",");
    Serial.print(current); Serial.print(",");
    Serial.print(voltage); Serial.print(",");
    Serial.print(mechanicalPower); Serial.print(",");
    Serial.print(electricalPower); Serial.print(",");
    Serial.println(efficiency);
  }
  
  analogWrite(MOTOR_PWM_PIN, 0); // Stop motor
  Serial.println("Test complete");
  
  while(1) {} // Stop after one full test
}