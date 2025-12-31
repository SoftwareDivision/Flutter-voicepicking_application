# 🎤 Voice Picking & Warehouse Management System

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![SQLite](https://img.shields.io/badge/SQLite-07405E?style=for-the-badge&logo=sqlite&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)

**A professional voice-controlled warehouse management application built with Flutter**

[Features](#-features) • [Installation](#-installation) • [Usage](#-usage) • [Screenshots](#-screenshots) • [Contributing](#-contributing)

</div>

---

## 📋 Overview

The **Voice Picking & Warehouse Management System** is a cutting-edge Flutter application designed to revolutionize warehouse operations through voice commands and intelligent automation. This system combines speech recognition, text-to-speech capabilities, and comprehensive warehouse management features to create an efficient, hands-free working environment.

## ✨ Features

### 🎯 Core Voice Features
- **🎤 Speech Recognition** - Advanced voice command processing
- **🔊 Text-to-Speech** - Audio feedback and instructions
- **🎛️ Voice Settings** - Customizable voice parameters and preferences
- **📱 Hands-Free Operation** - Complete voice-controlled workflow

### 📦 Warehouse Management System (WMS)
- **📊 Dashboard Analytics** - Real-time warehouse insights and metrics
- **📋 Inventory Management** - Complete stock tracking and control
- **📝 Picklist Management** - Efficient order picking workflows
- **📈 Reports & Analysis** - Comprehensive reporting system
- **⚠️ Stock Monitoring** - Low stock and out-of-stock alerts
- **🏪 Storage Management** - Warehouse layout and storage optimization
- **✅ Completed Picks** - Pick history and completion tracking

### 🔐 User Management
- **👤 User Authentication** - Secure login and registration
- **🔑 Password Recovery** - Forgot password functionality
- **👥 Profile Management** - User profile customization
- **🔒 Secure Data Storage** - Encrypted user data protection

### 📱 Additional Features
- **📊 PDF & Excel Reports** - Export capabilities for data analysis
- **📷 Barcode Scanner** - Quick item identification and tracking
- **💾 Offline Support** - Local SQLite database for offline operations
- **☁️ Cloud Sync** - Supabase integration for data synchronization
- **📤 Share Functionality** - Easy report and data sharing

## 🛠️ Technology Stack

| Category | Technology |
|----------|------------|
| **Framework** | Flutter 3.8.1+ |
| **Language** | Dart |
| **Database** | SQLite (Local) + Supabase (Cloud) |
| **Voice** | Speech-to-Text 7.3.0, Flutter TTS 4.2.3 |
| **Scanning** | Flutter Barcode Scanner Plus |
| **Reports** | PDF, Excel, CSV generation |
| **State Management** | Built-in Flutter state management |

## 📱 Installation

### Prerequisites
- Flutter SDK 3.8.1 or higher
- Dart SDK
- Android Studio / VS Code
- Android device or emulator

### Setup Instructions

1. **Clone the repository**
   ```bash
   git clone https://github.com/manii1-sh/voicepicking-and-warehouse-system-app.git
   cd voicepicking-and-warehouse-system-app
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure permissions**
   - Ensure microphone permissions are granted for voice features
   - Camera permissions for barcode scanning

4. **Run the application**
   ```bash
   flutter run
   ```

## 🚀 Usage

### Getting Started
1. **Launch the app** and create an account or login
2. **Grant permissions** for microphone and camera access
3. **Configure voice settings** according to your preferences
4. **Start using voice commands** for warehouse operations

### Voice Commands Examples
- *"Start picking"* - Begin a new picking session
- *"Scan item"* - Activate barcode scanner
- *"Complete pick"* - Mark current pick as completed
- *"Show inventory"* - Display inventory management screen
- *"Generate report"* - Create warehouse reports

### Navigation Flow
```
Login → Dashboard → Voice Picking / WMS Features → Reports & Analytics
```

## 📸 Screenshots

*Screenshots will be added here showcasing the main features of the application*

## 🏗️ Project Structure

```
lib/
├── controllers/     # Business logic controllers
├── models/         # Data models and entities
├── screens/        # UI screens and pages
│   ├── wms/       # Warehouse management screens
│   └── ...        # Authentication and core screens
├── services/       # API and database services
├── utils/         # Utility functions and helpers
├── widgets/       # Reusable UI components
└── main.dart      # Application entry point
```

## 🔧 Configuration

### Voice Settings
- Adjust speech recognition sensitivity
- Configure TTS voice parameters
- Set language preferences
- Customize command responses

### Database Setup
The app uses SQLite for local storage and Supabase for cloud synchronization. Database tables are automatically created on first run.

## 📊 Performance Features

- **Offline Capability** - Works without internet connection
- **Fast Response Time** - Optimized voice recognition processing
- **Efficient Storage** - Compressed data storage and caching
- **Battery Optimization** - Power-efficient voice processing

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👨‍💻 Author

**Manii Sharma**
- GitHub: [@manii1-sh](https://github.com/manii1-sh)

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- Speech recognition and TTS package contributors
- Supabase for cloud database services
- Open source community for various packages used

---

<div align="center">

**⭐ Star this repository if you found it helpful!**

Made with ❤️ using Flutter

</div>