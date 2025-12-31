import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/gradient_button.dart';
import '../utils/colors.dart';
import 'signup_screen.dart';
import 'voice_picking_screen.dart';
import 'forgot_password_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    try {
      _initializeAnimations();
    } catch (e) {
      debugPrint('Login screen init error: $e');
    }
  }

  void _initializeAnimations() {
    try {
      _fadeController = AnimationController(
        duration: const Duration(milliseconds: 1000),
        vsync: this,
      );
      _fadeAnimation = CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeInOut,
      );
      _fadeController.forward();
    } catch (e) {
      debugPrint('Animation initialization error: $e');
    }
  }

  @override
  void dispose() {
    try {
      _emailController.dispose();
      _passwordController.dispose();
      _fadeController.dispose();
    } catch (e) {
      debugPrint('Login screen dispose error: $e');
    }
    super.dispose();
  }

  // Enhanced responsive design helpers
  bool _isExtraLargeScreen(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1200;
  }

  bool _isLargeScreen(BuildContext context) {
    return MediaQuery.of(context).size.width >= 768;
  }

  bool _isMediumScreen(BuildContext context) {
    return MediaQuery.of(context).size.width >= 600;
  }

  bool _isSmallScreen(BuildContext context) {
    return MediaQuery.of(context).size.width < 400;
  }

  bool _isExtraSmallScreen(BuildContext context) {
    return MediaQuery.of(context).size.width < 350;
  }

  // Enhanced responsive measurements
  double _getResponsivePadding(BuildContext context) {
    if (_isExtraLargeScreen(context)) return 60.0;
    if (_isLargeScreen(context)) return 48.0;
    if (_isMediumScreen(context)) return 32.0;
    if (_isExtraSmallScreen(context)) return 12.0;
    if (_isSmallScreen(context)) return 16.0;
    return 24.0;
  }

  double _getMaxWidth(BuildContext context) {
    if (_isExtraLargeScreen(context)) return 500.0;
    if (_isLargeScreen(context)) return 450.0;
    if (_isMediumScreen(context)) return 400.0;
    return double.infinity;
  }

  double _getContentMaxWidth(BuildContext context) {
    if (_isExtraLargeScreen(context)) return 800.0;
    if (_isLargeScreen(context)) return 600.0;
    return double.infinity;
  }

  EdgeInsets _getResponsiveMargin(BuildContext context) {
    if (_isExtraLargeScreen(context)) {
      return const EdgeInsets.symmetric(horizontal: 100.0, vertical: 40.0);
    }
    if (_isLargeScreen(context)) {
      return const EdgeInsets.symmetric(horizontal: 60.0, vertical: 30.0);
    }
    if (_isMediumScreen(context)) {
      return const EdgeInsets.symmetric(horizontal: 40.0, vertical: 20.0);
    }
    return EdgeInsets.zero;
  }

  // 🔧 FIXED: Login functionality with proper username extraction
  Future<void> _handleLogin() async {
    try {
      if (_formKey.currentState?.validate() ?? false) {
        setState(() {
          _isLoading = true;
        });

        final email = _emailController.text.trim();
        final password = _passwordController.text.trim();
        debugPrint('Login attempt for: $email');

        if (email.isEmpty || password.isEmpty) {
          throw Exception('Email and password are required');
        }

        if (password.length < 6) {
          throw Exception('Password must be at least 6 characters');
        }

        // Real Supabase authentication
        final supabase = Supabase.instance.client;
        final response = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );

        if (response.user != null && response.session != null) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
            _showSuccessMessage('Login successful! Redirecting to Voice Picking...');
            await Future.delayed(const Duration(milliseconds: 1500));
            
            if (mounted) {
              debugPrint('Navigating to Voice Picking Screen...');
              try {
                // 🔧 FIXED: Extract actual username from user data
                final user = response.user!;
                final userName = user.userMetadata?['display_name'] ?? 
                                 user.userMetadata?['full_name'] ?? 
                                 user.userMetadata?['name'] ??
                                 user.email?.split('@').first ?? 
                                 'User';
                
                debugPrint('🔧 FIXED: Using username: $userName'); // Debug log

                await Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => VoicePickingScreen(
                      userName: userName, // ✅ PASS ACTUAL USERNAME
                    ),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      const begin = Offset(1.0, 0.0);
                      const end = Offset.zero;
                      const curve = Curves.easeInOut;
                      var tween = Tween(begin: begin, end: end).chain(
                        CurveTween(curve: curve),
                      );
                      return SlideTransition(
                        position: animation.drive(tween),
                        child: child,
                      );
                    },
                    transitionDuration: const Duration(milliseconds: 300),
                  ),
                );
                debugPrint('Navigation to Voice Picking Screen completed with userName: $userName');
              } catch (navigationError) {
                debugPrint('Navigation error: $navigationError');
                _showErrorMessage('Failed to navigate to Voice Picking screen');
              }
            }
          }
        } else {
          throw Exception('Login failed');
        }
      }
    } catch (e) {
      debugPrint('Login error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        String errorMessage = 'Login failed. Please try again.';
        if (e.toString().contains('Email and password are required')) {
          errorMessage = 'Please enter both email and password';
        } else if (e.toString().contains('Password must be at least 6 characters')) {
          errorMessage = 'Password must be at least 6 characters long';
        } else if (e.toString().contains('network')) {
          errorMessage = 'Network error. Please check your connection.';
        } else if (e.toString().contains('Invalid login credentials')) {
          errorMessage = 'Incorrect email or password';
        }
        _showErrorMessage(errorMessage);
      }
    }
  }

  void _showSuccessMessage(String message) {
    try {
      if (mounted) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Success message error: $e');
    }
  }

  void _showErrorMessage(String message) {
    try {
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error message error: $e');
    }
  }

  void _navigateToSignup() {
    try {
      if (mounted) {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const SignupScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              const begin = Offset(1.0, 0.0);
              const end = Offset.zero;
              const curve = Curves.ease;
              var tween = Tween(begin: begin, end: end).chain(
                CurveTween(curve: curve),
              );
              return SlideTransition(
                position: animation.drive(tween),
                child: child,
              );
            },
          ),
        );
      }
    } catch (e) {
      debugPrint('Navigation to signup error: $e');
      _showErrorMessage('Navigation error occurred');
    }
  }

  void _navigateToForgotPassword() {
    try {
      if (mounted) {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const ForgotPasswordScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              const begin = Offset(0.0, 1.0);
              const end = Offset.zero;
              const curve = Curves.ease;
              var tween = Tween(begin: begin, end: end).chain(
                CurveTween(curve: curve),
              );
              return SlideTransition(
                position: animation.drive(tween),
                child: child,
              );
            },
          ),
        );
      }
    } catch (e) {
      debugPrint('Navigation to forgot password error: $e');
      _showErrorMessage('Navigation error occurred');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final padding = _getResponsivePadding(context);
    final maxWidth = _getMaxWidth(context);
    final contentMaxWidth = _getContentMaxWidth(context);
    final margin = _getResponsiveMargin(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: contentMaxWidth,
                ),
                margin: margin,
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(padding),
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: maxWidth,
                      minHeight: screenHeight -
                          MediaQuery.of(context).padding.top -
                          MediaQuery.of(context).padding.bottom -
                          (padding * 2) -
                          margin.vertical,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Dynamic top spacing
                          SizedBox(
                            height: _isExtraLargeScreen(context)
                                ? 60
                                : _isLargeScreen(context)
                                    ? 50
                                    : _isMediumScreen(context)
                                        ? 40
                                        : _isSmallScreen(context)
                                            ? 20
                                            : 40,
                          ),
                          // Logo/Icon Section
                          _buildLogoSection(context),
                          // Dynamic spacing
                          SizedBox(
                            height: _isExtraLargeScreen(context)
                                ? 50
                                : _isLargeScreen(context)
                                    ? 40
                                    : _isMediumScreen(context)
                                        ? 35
                                        : _isSmallScreen(context)
                                            ? 20
                                            : 30,
                          ),
                          // Title Section
                          _buildTitleSection(context),
                          // Dynamic spacing
                          SizedBox(
                            height: _isExtraLargeScreen(context)
                                ? 60
                                : _isLargeScreen(context)
                                    ? 50
                                    : _isMediumScreen(context)
                                        ? 45
                                        : _isSmallScreen(context)
                                            ? 30
                                            : 40,
                          ),
                          // Login Form
                          _buildLoginForm(context),
                          // Bottom spacing
                          const Spacer(),
                          SizedBox(
                            height: _isExtraLargeScreen(context)
                                ? 40
                                : _isLargeScreen(context)
                                    ? 35
                                    : _isMediumScreen(context)
                                        ? 30
                                        : _isSmallScreen(context)
                                            ? 20
                                            : 25,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection(BuildContext context) {
    try {
      final logoSize = _isExtraLargeScreen(context)
          ? 160.0
          : _isLargeScreen(context)
              ? 140.0
              : _isMediumScreen(context)
                  ? 120.0
                  : _isSmallScreen(context)
                      ? 80.0
                      : 100.0;

      final iconSize = _isExtraLargeScreen(context)
          ? 80.0
          : _isLargeScreen(context)
              ? 70.0
              : _isMediumScreen(context)
                  ? 60.0
                  : _isSmallScreen(context)
                      ? 40.0
                      : 50.0;

      final shadowBlur = _isExtraLargeScreen(context)
          ? 30.0
          : _isLargeScreen(context)
              ? 25.0
              : _isMediumScreen(context)
                  ? 20.0
                  : _isSmallScreen(context)
                      ? 12.0
                      : 15.0;

      return Center(
        child: Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryPink.withOpacity(0.3),
                blurRadius: shadowBlur,
                offset: Offset(
                    0,
                    _isLargeScreen(context) ? 12 : (_isSmallScreen(context) ? 6 : 10)
                ),
              ),
            ],
          ),
          child: Icon(
            Icons.headset_mic_rounded,
            size: iconSize,
            color: Colors.white,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Logo section error: $e');
      return SizedBox(
          height: _isLargeScreen(context) ? 140 : (_isSmallScreen(context) ? 80 : 100)
      );
    }
  }

  Widget _buildTitleSection(BuildContext context) {
    try {
      final titleFontSize = _isExtraLargeScreen(context)
          ? 42.0
          : _isLargeScreen(context)
              ? 38.0
              : _isMediumScreen(context)
                  ? 32.0
                  : _isSmallScreen(context)
                      ? 24.0
                      : 28.0;

      final subtitleFontSize = _isExtraLargeScreen(context)
          ? 20.0
          : _isLargeScreen(context)
              ? 18.0
              : _isMediumScreen(context)
                  ? 16.0
                  : _isSmallScreen(context)
                      ? 14.0
                      : 15.0;

      return Column(
        children: [
          Text(
            'Voice Picking',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: titleFontSize,
              fontWeight: FontWeight.bold,
              foreground: Paint()
                ..shader = AppColors.primaryGradient.createShader(
                  const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0),
                ),
            ),
          ),
          SizedBox(
            height: _isExtraLargeScreen(context)
                ? 16
                : _isLargeScreen(context)
                    ? 12
                    : _isSmallScreen(context)
                        ? 6
                        : 8,
          ),
          Text(
            'Fast & Efficient Warehouse Operations',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: subtitleFontSize,
              color: AppColors.textLight,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      );
    } catch (e) {
      debugPrint('Title section error: $e');
      return SizedBox(
          height: _isLargeScreen(context) ? 60 : (_isSmallScreen(context) ? 40 : 60)
      );
    }
  }

  Widget _buildLoginForm(BuildContext context) {
    try {
      final fieldSpacing = _isExtraLargeScreen(context)
          ? 28.0
          : _isLargeScreen(context)
              ? 24.0
              : _isMediumScreen(context)
                  ? 20.0
                  : _isSmallScreen(context)
                      ? 16.0
                      : 18.0;

      return Form(
        key: _formKey,
        child: Column(
          children: [
            // Email Field
            _buildEmailField(context),
            SizedBox(height: fieldSpacing),
            // Password Field
            _buildPasswordField(context),
            SizedBox(height: fieldSpacing * 0.75),
            // Forgot Password
            _buildForgotPasswordButton(context),
            SizedBox(height: fieldSpacing * 1.5),
            // Login Button
            _buildLoginButton(context),
            SizedBox(height: fieldSpacing * 1.2),
            // Sign Up Link
            _buildSignupLink(context),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Login form error: $e');
      return const Center(
        child: Text(
          'Form error occurred',
          style: TextStyle(color: AppColors.error),
        ),
      );
    }
  }

  Widget _buildEmailField(BuildContext context) {
    try {
      final borderRadius = _isExtraLargeScreen(context)
          ? 20.0
          : _isLargeScreen(context)
              ? 18.0
              : _isMediumScreen(context)
                  ? 16.0
                  : _isSmallScreen(context)
                      ? 12.0
                      : 14.0;

      final fontSize = _isExtraLargeScreen(context)
          ? 20.0
          : _isLargeScreen(context)
              ? 18.0
              : _isMediumScreen(context)
                  ? 16.0
                  : _isSmallScreen(context)
                      ? 14.0
                      : 15.0;

      final iconSize = _isExtraLargeScreen(context)
          ? 30.0
          : _isLargeScreen(context)
              ? 28.0
              : _isMediumScreen(context)
                  ? 24.0
                  : _isSmallScreen(context)
                      ? 20.0
                      : 22.0;

      final contentPadding = EdgeInsets.symmetric(
        horizontal: _isExtraLargeScreen(context)
            ? 28
            : _isLargeScreen(context)
                ? 24
                : _isMediumScreen(context)
                    ? 20
                    : _isSmallScreen(context)
                        ? 16
                        : 18,
        vertical: _isExtraLargeScreen(context)
            ? 22
            : _isLargeScreen(context)
                ? 18
                : _isMediumScreen(context)
                    ? 16
                    : _isSmallScreen(context)
                        ? 12
                        : 14,
      );

      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: _isLargeScreen(context) ? 12 : (_isSmallScreen(context) ? 6 : 10),
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(fontSize: fontSize),
          decoration: InputDecoration(
            hintText: 'Email Address',
            hintStyle: TextStyle(fontSize: fontSize),
            prefixIcon: Icon(
              Icons.email_outlined,
              color: AppColors.primaryPink.withOpacity(0.7),
              size: iconSize,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: BorderSide.none,
            ),
            contentPadding: contentPadding,
            filled: true,
            fillColor: Colors.white,
          ),
          validator: (value) {
            try {
              if (value?.isEmpty ?? true) {
                return 'Please enter your email';
              }
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value!)) {
                return 'Please enter a valid email';
              }
              return null;
            } catch (e) {
              debugPrint('Email validation error: $e');
              return 'Email validation error';
            }
          },
        ),
      );
    } catch (e) {
      debugPrint('Email field error: $e');
      return SizedBox(
          height: _isLargeScreen(context) ? 60 : (_isSmallScreen(context) ? 48 : 56)
      );
    }
  }

  Widget _buildPasswordField(BuildContext context) {
    try {
      final borderRadius = _isExtraLargeScreen(context)
          ? 20.0
          : _isLargeScreen(context)
              ? 18.0
              : _isMediumScreen(context)
                  ? 16.0
                  : _isSmallScreen(context)
                      ? 12.0
                      : 14.0;

      final fontSize = _isExtraLargeScreen(context)
          ? 20.0
          : _isLargeScreen(context)
              ? 18.0
              : _isMediumScreen(context)
                  ? 16.0
                  : _isSmallScreen(context)
                      ? 14.0
                      : 15.0;

      final iconSize = _isExtraLargeScreen(context)
          ? 30.0
          : _isLargeScreen(context)
              ? 28.0
              : _isMediumScreen(context)
                  ? 24.0
                  : _isSmallScreen(context)
                      ? 20.0
                      : 22.0;

      final contentPadding = EdgeInsets.symmetric(
        horizontal: _isExtraLargeScreen(context)
            ? 28
            : _isLargeScreen(context)
                ? 24
                : _isMediumScreen(context)
                    ? 20
                    : _isSmallScreen(context)
                        ? 16
                        : 18,
        vertical: _isExtraLargeScreen(context)
            ? 22
            : _isLargeScreen(context)
                ? 18
                : _isMediumScreen(context)
                    ? 16
                    : _isSmallScreen(context)
                        ? 12
                        : 14,
      );

      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: _isLargeScreen(context) ? 12 : (_isSmallScreen(context) ? 6 : 10),
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: TextStyle(fontSize: fontSize),
          decoration: InputDecoration(
            hintText: 'Password',
            hintStyle: TextStyle(fontSize: fontSize),
            prefixIcon: Icon(
              Icons.lock_outlined,
              color: AppColors.primaryPink.withOpacity(0.7),
              size: iconSize,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppColors.primaryPink.withOpacity(0.7),
                size: iconSize,
              ),
              onPressed: () {
                try {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                } catch (e) {
                  debugPrint('Password visibility error: $e');
                }
              },
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: BorderSide.none,
            ),
            contentPadding: contentPadding,
            filled: true,
            fillColor: Colors.white,
          ),
          validator: (value) {
            try {
              if (value?.isEmpty ?? true) {
                return 'Please enter your password';
              }
              if (value!.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            } catch (e) {
              debugPrint('Password validation error: $e');
              return 'Password validation error';
            }
          },
        ),
      );
    } catch (e) {
      debugPrint('Password field error: $e');
      return SizedBox(
          height: _isLargeScreen(context) ? 60 : (_isSmallScreen(context) ? 48 : 56)
      );
    }
  }

  Widget _buildForgotPasswordButton(BuildContext context) {
    try {
      final fontSize = _isExtraLargeScreen(context)
          ? 18.0
          : _isLargeScreen(context)
              ? 16.0
              : _isMediumScreen(context)
                  ? 14.0
                  : _isSmallScreen(context)
                      ? 13.0
                      : 14.0;

      return Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _navigateToForgotPassword,
          child: Text(
            'Forgot Password?',
            style: TextStyle(
              color: AppColors.primaryPink,
              fontWeight: FontWeight.w500,
              fontSize: fontSize,
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Forgot password button error: $e');
      return const SizedBox.shrink();
    }
  }

  Widget _buildLoginButton(BuildContext context) {
    final buttonHeight = _isExtraLargeScreen(context)
        ? 72.0
        : _isLargeScreen(context)
            ? 64.0
            : _isMediumScreen(context)
                ? 56.0
                : _isSmallScreen(context)
                    ? 48.0
                    : 52.0;

    final fontSize = _isExtraLargeScreen(context)
        ? 20.0
        : _isLargeScreen(context)
            ? 18.0
            : _isMediumScreen(context)
                ? 16.0
                : _isSmallScreen(context)
                    ? 14.0
                    : 15.0;

    final borderRadius = _isExtraLargeScreen(context)
        ? 20.0
        : _isLargeScreen(context)
            ? 18.0
            : _isMediumScreen(context)
                ? 16.0
                : _isSmallScreen(context)
                    ? 12.0
                    : 14.0;

    final iconSize = _isExtraLargeScreen(context)
        ? 26.0
        : _isLargeScreen(context)
            ? 24.0
            : _isMediumScreen(context)
                ? 20.0
                : _isSmallScreen(context)
                    ? 18.0
                    : 19.0;

    return SizedBox(
      height: buttonHeight,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: _isLoading
                ? LinearGradient(
                    colors: [
                      AppColors.primaryPink.withOpacity(0.6),
                      AppColors.lightPink.withOpacity(0.6),
                    ],
                  )
                : AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryPink.withOpacity(0.3),
                blurRadius: _isLargeScreen(context) ? 15 : (_isSmallScreen(context) ? 8 : 12),
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: _isLoading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: iconSize,
                        height: iconSize,
                        child: const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Signing In...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.login_rounded,
                        color: Colors.white,
                        size: iconSize,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Sign In',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignupLink(BuildContext context) {
    try {
      final fontSize = _isExtraLargeScreen(context)
          ? 18.0
          : _isLargeScreen(context)
              ? 16.0
              : _isMediumScreen(context)
                  ? 14.0
                  : _isSmallScreen(context)
                      ? 13.0
                      : 14.0;

      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Don't have an account? ",
            style: TextStyle(
              color: AppColors.textLight,
              fontSize: fontSize,
            ),
          ),
          TextButton(
            onPressed: _navigateToSignup,
            child: Text(
              'Sign Up',
              style: TextStyle(
                color: AppColors.primaryPink,
                fontWeight: FontWeight.w600,
                fontSize: fontSize,
              ),
            ),
          ),
        ],
      );
    } catch (e) {
      debugPrint('Signup link error: $e');
      return const SizedBox.shrink();
    }
  }
}
