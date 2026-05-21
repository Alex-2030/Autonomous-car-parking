<!-- @format -->

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

1.  **[Microchip Studio](https://www.microchip.com/en-us/tools-resources/develop/microchip-studio) (formerly Atmel Studio):** The software used to compile the `.c` code into a `.hex` file and flash it to the car's microcontroller.

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
   _(You can double-click the `.exe` file in this folder to run the app directly on your PC!)_

### 🏎️ 3. Building and Flashing the AVR Code to the Car

1. Open **Microchip Studio**.
2. Create a new "GCC C Executable Project" and name it `Auto_Car_Parking`.
3. Copy the contents of the `Auto_Car_Parking.c` file from this repository and paste it over the default `main.c` file in your new Microchip Studio project.
4. **Build the Code:** Click **Build > Build Solution** from the top menu.
5. **Where to find the HEX file:** Once built successfully, the compiled `.hex` file will be automatically generated inside your Microchip Studio project folder at:
   `Auto_Car_Parking\Debug\Auto_Car_Parking.hex` (or `Release\` depending on your setup).
6. **Flash the Code:**
   - Connect your AVR programmer (e.g., USBasp) to your computer and the car.
   - In Microchip Studio, click **Tools > Device Programming**.
   - Select your programmer and the Atmega 32A chip, then click **Apply**.
   - Go to the **Memories** tab, click the `...` button to browse and select the `.hex` file you located earlier, and click **Program** to upload it to the car!
