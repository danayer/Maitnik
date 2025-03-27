const int potPin = A0;        // Пин подключения резистора
float voltage = 0;           // Напряжение на ползунке
float angle = 0;             // Угол отклонения
const float maxVoltage = 5.0; // Максимальное напряжение
const float maxAngle = 3600.0; // Максимальный угол (10 оборотов x 360 градусов)
float zeroOffset = 0;         // Нулевое значение

void setup() {
  Serial.begin(9600);
  pinMode(potPin, INPUT);
  delay(2000);               // Задержка для стабилизации
  Serial.println("Нажмите 'Настройка' для обнуления угла.");
}

void loop() {
  int potValue = analogRead(potPin);        // Считываем данные с резистора
  voltage = potValue * (maxVoltage / 1023.0); // Конвертация в напряжение
  angle = voltage * (maxAngle / maxVoltage) - zeroOffset; // Угол в градусах

  // Печать данных:
  if (Serial.available()) {
    char command = Serial.read();          // Получение команды
    if (command == 'n') {                  // Если команда "n" (настройка)
      zeroOffset = voltage * (maxAngle / maxVoltage);
      Serial.println("Угол обнулён.");
    }
  }
  Serial.print("Угол: ");
  Serial.println(angle);
  delay(100);
}