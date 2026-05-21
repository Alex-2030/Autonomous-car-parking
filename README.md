# 🚗 Autonomous Car Parking System

Welcome to the **Autonomous Car Parking System**!

This project combines an intelligent, self-parking physical car powered by the Atmega 32A, with cross-platform remote control applications built in Flutter. This allows users to monitor and interact with the car using either an Android smartphone or a Windows PC.

---

## ✨ Key Features

- **🤖 AVR Smart Car (Hardware)**
  - Autonomous parking algorithms using sensors to detect open spaces and obstacles.
  - Embedded C/C++ logic for precise motor control and steering.
- **📱 Flutter Android App (Mobile)**
  - Clean, user-friendly interface to remotely monitor the car's status.
  - Manual override controls via Bluetooth (HC-05) to steer the car directly from your phone.
- **💻 Flutter Windows App (Desktop)**
  - A full desktop dashboard to view detailed logs and sensor data.
  - Keyboard support for manual driving.

---

## 📂 Project Folder Structure

This repository is split into three main parts:

```text
Autonomous car parking/
│
├── Flutter_Mobile_App/       # 📱 The Android smartphone application
│   ├── android/              # Android-specific build files
│   ├── lib/                  # Main Dart/Flutter code for the app
│   └── pubspec.yaml          # Flutter dependencies
│
├── Flutter_Windows_App/      # 💻 The Windows desktop application
│   ├── windows/              # Windows-specific build files
│   ├── lib/                  # Main Dart/Flutter code for the app
│   └── pubspec.yaml          # Flutter dependencies
│
└── Auto_Car_Parking.c        # 🏎️ The core Embedded C code for the AVR microcontroller
```

---

## 🛠️ Prerequisites (What to Download First)

Don't worry if you aren't super tech-savvy! Before you run the code, you'll need to download and install a few free tools.

**For the Mobile & Windows Apps:**

1.  **[Flutter SDK](https://docs.flutter.dev/get-started/install):** The core framework needed to build the apps.
2.  **[Android Studio](https://developer.android.com/studio):** Required to set up an Android emulator, build the apps, and manage the Android SDK.

**For the AVR Smart Car:**

Instead of downloading a massive IDE, you only need the lightweight command-line tools to compile and flash the code:
1.  **[AVR 8-Bit Toolchain (avr-gcc)](https://www.microchip.com/en-us/tools-resources/develop/microchip-studio/gcc-compilers):** The official compiler used to convert your C code into a format the chip understands. *(Make sure to add it to your system PATH!)*
2.  **[AVRDUDE](https://github.com/avrdudes/avrdude/releases):** A simple command-line tool used to flash (upload) the compiled code into the car's microcontroller.

---

## 🚀 How to Build and Run the Project

### 📱 1. Running and Building the Android Mobile App

**To test the app on an Emulator:**
1. Open **Android Studio**.
2. Go to **Tools > Device Manager** (or **Virtual Device Manager**) and click **Create Device**.
3. Choose a phone model (e.g., Pixel 7) and download a system image (like API 34). 
4. Once created, click the **Play** button to launch the emulator.
5. Open the `Flutter_Mobile_App` folder in Android Studio.
6. Click the **Run** button (green play icon) at the top toolbar to install and test the app on the emulator.

**To build the final APK file (to install on a real phone):**
1. Open your computer's terminal (Command Prompt or PowerShell) and navigate inside the `Flutter_Mobile_App` folder.
2. Run the command: `flutter build apk`
3. **Where to find it:** The compiled `.apk` file will be located at:
   `Flutter_Mobile_App\build\app\outputs\flutter-apk\app-release.apk`

### 💻 2. Building the Windows Desktop App

1. Open your computer's terminal and navigate inside the `Flutter_Windows_App` folder.
2. Run the command: `flutter build windows`
3. **Where to find it:** The compiled `.exe` file (and required DLLs) will be located at:
   `Flutter_Windows_App\build\windows\x64\runner\Release\`
   *(You can double-click the `.exe` file in this folder to run the app directly on your PC!)*

### 🏎️ 3. Building and Flashing the AVR Code to the Car

You will compile the C code into an `.elf` file, convert it to a `.hex` file, and then flash it.

1. Open your terminal and navigate to the main project folder containing `Auto_Car_Parking.c`.
2. **Compile the Code (.elf):** Run this command to compile the code into an `.elf` file:
   ```bash
   avr-gcc -g -Os -mmcu=atmega32a -o Auto_Car_Parking.elf Auto_Car_Parking.c
   ```
   *(Note: `-mmcu=atmega32a` is for the Atmega 32A. Adjust if using a different chip).*

3. **Convert to HEX (.hex):** Extract the `.hex` file (the raw machine code the car understands) from the `.elf` file by running:
   ```bash
   avr-objcopy -j .text -j .data -O ihex Auto_Car_Parking.elf Auto_Car_Parking.hex
   ```

4. **Flash the Code:** Connect your AVR programmer (e.g., a USBasp) to your computer and to the car's chip. Run AVRDUDE to upload the `.hex` file:
   ```bash
   avrdude -c usbasp -p m32 -U flash:w:Auto_Car_Parking.hex:i
   ```
   *(Note: `-c usbasp` specifies the programmer type, and `-p m32` specifies the Atmega32. Adjust these if your hardware is different).*
---

## Note

This repository is part of an academic embedded systems project combining AVR programming, Flutter applications, and autonomous car control.
