// lib/screens/voice_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../utils/colors.dart';

class VoiceSettingsScreen extends StatefulWidget {
  final String userName;
  final Function()? onSettingsChanged;

  const VoiceSettingsScreen({
    super.key,
    required this.userName,
    this.onSettingsChanged,
  });

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen>
    with TickerProviderStateMixin {
  // Essential Voice Settings Only
  double _voiceSpeed = 0.8;
  double _voiceVolume = 0.8;
  bool _voiceEnabled = true;
  bool _hapticFeedback = true;
  String _selectedLanguage = 'English (US)';

  // Loading States
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;

  // Animation Controller
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  final List<String> _languageOptions = [
    'English (US)',
    'English (UK)',
    'Spanish',
    'French',
    'German',
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadSettings();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));
    _fadeController.forward();
  }

  Future<void> _loadSettings() async {
    try {
      setState(() => _isLoading = true);
      final prefs = await SharedPreferences.getInstance();
      
      setState(() {
        _voiceSpeed = prefs.getDouble('voice_speed') ?? 0.8;
        _voiceVolume = prefs.getDouble('voice_volume') ?? 0.8;
        _voiceEnabled = prefs.getBool('voice_enabled') ?? true;
        _hapticFeedback = prefs.getBool('haptic_feedback') ?? true;
        _selectedLanguage = prefs.getString('selected_language') ?? 'English (US)';
        _isLoading = false;
      });
      
      debugPrint('✅ Voice settings loaded successfully');
    } catch (e) {
      debugPrint('❌ Load settings error: $e');
      setState(() => _isLoading = false);
      _showErrorMessage('Failed to load settings');
    }
  }

  Future<void> _saveSettings() async {
    try {
      setState(() => _isSaving = true);
      final prefs = await SharedPreferences.getInstance();
      
      await Future.wait([
        prefs.setDouble('voice_speed', _voiceSpeed),
        prefs.setDouble('voice_volume', _voiceVolume),
        prefs.setBool('voice_enabled', _voiceEnabled),
        prefs.setBool('haptic_feedback', _hapticFeedback),
        prefs.setString('selected_language', _selectedLanguage),
      ]);
      
      setState(() => _isSaving = false);
      
      if (_hapticFeedback) {
        HapticFeedback.lightImpact();
      }
      
      if (widget.onSettingsChanged != null) {
        widget.onSettingsChanged!();
      }
      
      _showSuccessMessage('Settings saved successfully!');
      debugPrint('✅ Voice settings saved successfully');
    } catch (e) {
      debugPrint('❌ Save settings error: $e');
      setState(() => _isSaving = false);
      _showErrorMessage('Failed to save settings');
    }
  }

  Future<void> _resetToDefaults() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: const Row(
          children: [
            Icon(Icons.restore, color: AppColors.warning),
            SizedBox(width: 8),
            Text('Reset Settings', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: const Text(
          'Reset all settings to default values?\n\nSpeed: 80%\nVolume: 80%',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _performReset();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _performReset() {
    setState(() {
      _voiceSpeed = 0.8;
      _voiceVolume = 0.8;
      _voiceEnabled = true;
      _hapticFeedback = true;
      _selectedLanguage = 'English (US)';
    });
    _saveSettings();
    _showSuccessMessage('Settings reset to defaults!');
  }

  Future<void> _testVoiceSettings() async {
    try {
      setState(() => _isTesting = true);
      
      if (_hapticFeedback) {
        HapticFeedback.lightImpact();
      }
      
      if (!_voiceEnabled) {
        _showSuccessMessage('Voice is disabled - enable to test');
        setState(() => _isTesting = false);
        return;
      }
      
      FlutterTts testTts = FlutterTts();
      await testTts.setSpeechRate(_voiceSpeed);
      await testTts.setVolume(_voiceVolume);
      await testTts.setLanguage(_mapLanguageToCode(_selectedLanguage));
      
      String testMessage = "Voice test at ${(_voiceSpeed * 100).toInt()}% speed and ${(_voiceVolume * 100).toInt()}% volume.";
      await testTts.speak(testMessage);
      
      _showSuccessMessage('Voice test completed');
      debugPrint('🔊 Voice test: Speed ${(_voiceSpeed * 100).toInt()}%, Volume ${(_voiceVolume * 100).toInt()}%');
      
      await testTts.stop();
      setState(() => _isTesting = false);
    } catch (e) {
      debugPrint('❌ Voice test error: $e');
      setState(() => _isTesting = false);
      _showErrorMessage('Voice test failed');
    }
  }

  String _mapLanguageToCode(String language) {
    switch (language) {
      case 'English (US)': return 'en-US';
      case 'English (UK)': return 'en-GB';
      case 'Spanish': return 'es-ES';
      case 'French': return 'fr-FR';
      case 'German': return 'de-DE';
      default: return 'en-US';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _isLoading
                      ? _buildLoadingState()
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _buildVoiceControlSection(),
                              const SizedBox(height: 16),
                              _buildAppBehaviorSection(),
                              const SizedBox(height: 16),
                              _buildTestSection(),
                              const SizedBox(height: 20),
                              _buildActionButtons(),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.primaryPink.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.primaryPink.withOpacity(0.2),
              ),
            ),
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(
                Icons.arrow_back_ios_new,
                color: AppColors.primaryPink,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voice Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  'Configure voice and app behavior',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textLight,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.settings_voice,
              color: Colors.white,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primaryPink),
          SizedBox(height: 16),
          Text(
            'Loading settings...',
            style: TextStyle(color: AppColors.textLight, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceControlSection() {
    return _buildSettingCard(
      title: 'Voice Control',
      icon: Icons.record_voice_over,
      color: AppColors.primaryPink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSlider(
            'Voice Speed',
            _voiceSpeed,
            (value) => setState(() => _voiceSpeed = value),
            Icons.speed,
            AppColors.primaryPink,
          ),
          const SizedBox(height: 16),
          _buildSlider(
            'Voice Volume',
            _voiceVolume,
            (value) => setState(() => _voiceVolume = value),
            Icons.volume_up,
            AppColors.success,
          ),
          const SizedBox(height: 16),
          _buildLanguageDropdown(),
          const SizedBox(height: 16),
          _buildSpeedPresets(),
        ],
      ),
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
    IconData icon,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${(value * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            inactiveTrackColor: color.withOpacity(0.2),
            thumbColor: color,
            overlayColor: color.withOpacity(0.1),
            trackHeight: 3,
          ),
          child: Slider(
            value: value,
            min: 0.3,
            max: 1.5,
            divisions: 12,
            onChanged: (newValue) {
              onChanged(newValue);
              if (_hapticFeedback) {
                HapticFeedback.selectionClick();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.language, color: Colors.blue, size: 16),
            SizedBox(width: 8),
            Text(
              'Language',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedLanguage,
          items: _languageOptions.map((language) {
            return DropdownMenuItem<String>(
              value: language,
              child: Text(language, style: const TextStyle(fontSize: 14)),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _selectedLanguage = value);
              if (_hapticFeedback) {
                HapticFeedback.selectionClick();
              }
            }
          },
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedPresets() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Presets',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildSpeedPreset('Slow', 0.6, '60%')),
            const SizedBox(width: 8),
            Expanded(child: _buildSpeedPreset('Normal', 0.8, '80%')),
            const SizedBox(width: 8),
            Expanded(child: _buildSpeedPreset('Fast', 1.0, '100%')),
          ],
        ),
      ],
    );
  }

  Widget _buildSpeedPreset(String label, double speed, String percentage) {
    final isSelected = (_voiceSpeed - speed).abs() < 0.1;
    return GestureDetector(
      onTap: () {
        setState(() {
          _voiceSpeed = speed;
          _voiceVolume = speed;
        });
        if (_hapticFeedback) {
          HapticFeedback.lightImpact();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryPink
              : AppColors.primaryPink.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.primaryPink.withOpacity(0.3),
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.primaryPink,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              percentage,
              style: TextStyle(
                color: isSelected ? Colors.white70 : AppColors.primaryPink.withOpacity(0.7),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBehaviorSection() {
    return _buildSettingCard(
      title: 'App Behavior',
      icon: Icons.settings_applications,
      color: Colors.orange,
      child: Column(
        children: [
          _buildSwitchTile(
            'Voice Commands',
            'Enable voice responses throughout the app',
            _voiceEnabled,
            (value) => setState(() => _voiceEnabled = value),
            Icons.mic,
          ),
          _buildSwitchTile(
            'Haptic Feedback',
            'Enable vibration for button presses',
            _hapticFeedback,
            (value) => setState(() => _hapticFeedback = value),
            Icons.vibration,
          ),
        ],
      ),
    );
  }

  Widget _buildTestSection() {
    return _buildSettingCard(
      title: 'Test Voice',
      icon: Icons.play_circle,
      color: AppColors.success,
      child: Column(
        children: [
          const Text(
            'Test your current voice settings',
            style: TextStyle(
              color: AppColors.textLight,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isTesting ? null : _testVoiceSettings,
              icon: _isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_isTesting ? 'Testing...' : 'Test Voice'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveSettings,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save),
            label: Text(_isSaving ? 'Saving...' : 'Save Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPink,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _resetToDefaults,
            icon: const Icon(Icons.restore),
            label: const Text('Reset to Defaults'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.warning,
              side: const BorderSide(color: AppColors.warning),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.orange, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textLight,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: Colors.orange,
            onChanged: (newValue) {
              onChanged(newValue);
              if (_hapticFeedback) {
                HapticFeedback.lightImpact();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  void _showSuccessMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
  }

  void _showErrorMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }
}
