import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/gradient_button.dart';
import '../utils/colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreeToTerms = false;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    try {
      _initializeAnimations();
    } catch (e) {
      debugPrint('Signup screen init error: $e');
    }
  }

  void _initializeAnimations() {
    try {
      _slideController = AnimationController(
        duration: const Duration(milliseconds: 300),
        vsync: this,
      );
      _slideAnimation = Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _slideController,
          curve: Curves.easeInOut,
        ),
      );
      _slideController.forward();
    } catch (e) {
      debugPrint('Animation initialization error: $e');
    }
  }

  @override
  void dispose() {
    try {
      _nameController.dispose();
      _emailController.dispose();
      _passwordController.dispose();
      _confirmPasswordController.dispose();
      _slideController.dispose();
    } catch (e) {
      debugPrint('Signup screen dispose error: $e');
    }
    super.dispose();
  }

  // Responsive design helpers
  bool _isLargeScreen(BuildContext context) {
    return MediaQuery.of(context).size.width >= 600;
  }

  bool _isSmallScreen(BuildContext context) {
    return MediaQuery.of(context).size.width < 400;
  }

  bool _isVerySmallScreen(BuildContext context) {
    return MediaQuery.of(context).size.width < 350;
  }

  double _getResponsivePadding(BuildContext context) {
    if (_isLargeScreen(context)) return 40.0;
    if (_isVerySmallScreen(context)) return 12.0;
    if (_isSmallScreen(context)) return 16.0;
    return 24.0;
  }

  double _getMaxWidth(BuildContext context) {
    if (_isLargeScreen(context)) return 450.0;
    return double.infinity;
  }

  Future<void> _handleSignup() async {
    try {
      if (_formKey.currentState?.validate() ?? false) {
        if (!_agreeToTerms) {
          _showErrorMessage('Please agree to Terms & Conditions');
          return;
        }

        setState(() {
          _isLoading = true;
        });

        final name = _nameController.text.trim();
        final email = _emailController.text.trim();
        final password = _passwordController.text.trim();

        // Real Supabase authentication
        final supabase = Supabase.instance.client;
        final response = await supabase.auth.signUp(
          email: email,
          password: password,
        );

        if (response.user != null) {
          // Store user profile
          try {
            await supabase.from('user_profiles').insert({
              'id': response.user!.id,
              'name': name,
              'email': email,
              'created_at': DateTime.now().toIso8601String(),
            });
          } catch (profileError) {
            debugPrint('Profile creation error: $profileError');
          }

          if (mounted) {
            setState(() {
              _isLoading = false;
            });

            _showSuccessMessage('Account created successfully! Welcome to Voice Picking!');
            await Future.delayed(const Duration(seconds: 1));

            if (mounted) {
              Navigator.of(context).pop();
            }
          }
        } else {
          throw Exception('Signup failed');
        }
      }
    } catch (e) {
      debugPrint('Signup error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showErrorMessage('Signup failed. Please try again.');
      }
    }
  }

  void _showSuccessMessage(String message) {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 3),
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

  void _navigateBack() {
    try {
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Navigation back error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final padding = _getResponsivePadding(context);
    final maxWidth = _getMaxWidth(context);
    final isLarge = _isLargeScreen(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: SafeArea(
          child: SlideTransition(
            position: _slideAnimation,
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(padding),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: maxWidth,
                    minHeight: screenHeight - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom - (padding * 2),
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Flexible top spacing
                        SizedBox(height: isLarge ? 20 : (_isSmallScreen(context) ? 10 : 20)),
                        
                        // Back Button
                        _buildBackButton(context),
                        
                        // Flexible spacing
                        SizedBox(height: isLarge ? 30 : (_isSmallScreen(context) ? 20 : 40)),
                        
                        // Title Section
                        _buildTitleSection(context),
                        
                        // Flexible spacing
                        SizedBox(height: isLarge ? 30 : (_isSmallScreen(context) ? 20 : 40)),
                        
                        // Signup Form
                        _buildSignupForm(context),
                        
                        // Bottom spacing
                        const Spacer(),
                        SizedBox(height: isLarge ? 20 : (_isSmallScreen(context) ? 10 : 20)),
                      ],
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

  Widget _buildBackButton(BuildContext context) {
    try {
      final isSmall = _isSmallScreen(context);
      final isLarge = _isLargeScreen(context);
      final buttonSize = isLarge ? 52.0 : (isSmall ? 40.0 : 48.0);
      final iconSize = isLarge ? 26.0 : (isSmall ? 18.0 : 22.0);

      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: buttonSize,
          height: buttonSize,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(isLarge ? 14 : (isSmall ? 10 : 12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: isLarge ? 10 : (isSmall ? 6 : 8),
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_rounded,
              color: AppColors.primaryPink,
              size: iconSize,
            ),
            onPressed: _navigateBack,
            padding: EdgeInsets.zero,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Back button error: $e');
      return SizedBox(height: _isLargeScreen(context) ? 52 : (_isSmallScreen(context) ? 40 : 48));
    }
  }

  Widget _buildTitleSection(BuildContext context) {
    try {
      final isSmall = _isSmallScreen(context);
      final isLarge = _isLargeScreen(context);
      final titleFontSize = isLarge ? 32.0 : (isSmall ? 22.0 : 28.0);
      final subtitleFontSize = isLarge ? 18.0 : (isSmall ? 14.0 : 16.0);

      return Column(
        children: [
          Text(
            'Create Account',
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
          SizedBox(height: isLarge ? 10 : (isSmall ? 6 : 8)),
          Text(
            'Join the voice picking revolution',
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
      return SizedBox(height: _isLargeScreen(context) ? 60 : (_isSmallScreen(context) ? 40 : 60));
    }
  }

  Widget _buildSignupForm(BuildContext context) {
    try {
      final isSmall = _isSmallScreen(context);
      final isLarge = _isLargeScreen(context);
      final fieldSpacing = isLarge ? 20.0 : (isSmall ? 12.0 : 20.0);

      return Form(
        key: _formKey,
        child: Column(
          children: [
            // Name Field
            _buildTextField(
              context: context,
              controller: _nameController,
              hintText: 'Full Name',
              icon: Icons.person_outlined,
              validator: (value) {
                if (value?.isEmpty ?? true) {
                  return 'Please enter your full name';
                }
                return null;
              },
            ),
            SizedBox(height: fieldSpacing),

            // Email Field
            _buildTextField(
              context: context,
              controller: _emailController,
              hintText: 'Email Address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value?.isEmpty ?? true) {
                  return 'Please enter your email';
                }
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value!)) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),
            SizedBox(height: fieldSpacing),

            // Password Field
            _buildTextField(
              context: context,
              controller: _passwordController,
              hintText: 'Password',
              icon: Icons.lock_outlined,
              obscureText: _obscurePassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppColors.primaryPink.withOpacity(0.7),
                  size: isLarge ? 28 : (isSmall ? 20 : 24),
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              validator: (value) {
                if (value?.isEmpty ?? true) {
                  return 'Please enter your password';
                }
                if (value!.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            SizedBox(height: fieldSpacing),

            // Confirm Password Field
            _buildTextField(
              context: context,
              controller: _confirmPasswordController,
              hintText: 'Confirm Password',
              icon: Icons.lock_outlined,
              obscureText: _obscureConfirmPassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppColors.primaryPink.withOpacity(0.7),
                  size: isLarge ? 28 : (isSmall ? 20 : 24),
                ),
                onPressed: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
              validator: (value) {
                if (value?.isEmpty ?? true) {
                  return 'Please confirm your password';
                }
                if (value != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            SizedBox(height: isLarge ? 28 : (isSmall ? 16 : 24)),

            // Terms Checkbox
            _buildTermsCheckbox(context),
            SizedBox(height: isLarge ? 36 : (isSmall ? 20 : 32)),

            // Signup Button
            _buildSignupButton(context),
            SizedBox(height: isLarge ? 28 : (isSmall ? 16 : 24)),

            // Login Link
            _buildLoginLink(context),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Signup form error: $e');
      return const Center(
        child: Text('Form error occurred', style: TextStyle(color: AppColors.error)),
      );
    }
  }

  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    final isSmall = _isSmallScreen(context);
    final isLarge = _isLargeScreen(context);
    final borderRadius = isLarge ? 18.0 : (isSmall ? 12.0 : 16.0);
    final contentPadding = EdgeInsets.symmetric(
      horizontal: isLarge ? 24 : (isSmall ? 16 : 20),
      vertical: isLarge ? 18 : (isSmall ? 12 : 16),
    );
    final fontSize = isLarge ? 18.0 : (isSmall ? 14.0 : 16.0);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: isLarge ? 12 : (isSmall ? 6 : 10),
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: TextStyle(fontSize: fontSize),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(fontSize: fontSize),
          prefixIcon: Icon(
            icon,
            color: AppColors.primaryPink.withOpacity(0.7),
            size: isLarge ? 28 : (isSmall ? 20 : 24),
          ),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            borderSide: BorderSide.none,
          ),
          contentPadding: contentPadding,
          filled: true,
          fillColor: Colors.white,
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildTermsCheckbox(BuildContext context) {
    final isSmall = _isSmallScreen(context);
    final isLarge = _isLargeScreen(context);
    final fontSize = isLarge ? 16.0 : (isSmall ? 12.0 : 14.0);

    return Row(
      children: [
        Transform.scale(
          scale: isLarge ? 1.2 : (isSmall ? 0.9 : 1.0),
          child: Checkbox(
            value: _agreeToTerms,
            onChanged: (value) {
              setState(() {
                _agreeToTerms = value ?? false;
              });
            },
            activeColor: AppColors.primaryPink,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(color: AppColors.textLight, fontSize: fontSize),
              children: [
                const TextSpan(text: 'I agree to the '),
                TextSpan(
                  text: 'Terms & Conditions',
                  style: TextStyle(
                    color: AppColors.primaryPink,
                    fontWeight: FontWeight.w500,
                    fontSize: fontSize,
                  ),
                ),
                const TextSpan(text: ' and '),
                TextSpan(
                  text: 'Privacy Policy',
                  style: TextStyle(
                    color: AppColors.primaryPink,
                    fontWeight: FontWeight.w500,
                    fontSize: fontSize,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignupButton(BuildContext context) {
    final isSmall = _isSmallScreen(context);
    final isLarge = _isLargeScreen(context);
    final buttonHeight = isLarge ? 64.0 : (isSmall ? 48.0 : 56.0);
    final fontSize = isLarge ? 18.0 : (isSmall ? 14.0 : 16.0);

    return SizedBox(
      height: buttonHeight,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleSignup,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isLarge ? 18 : (isSmall ? 12 : 16)),
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
            borderRadius: BorderRadius.circular(isLarge ? 18 : (isSmall ? 12 : 16)),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryPink.withOpacity(0.3),
                blurRadius: isLarge ? 15 : (isSmall ? 8 : 12),
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
                        width: isLarge ? 24 : (isSmall ? 16 : 20),
                        height: isLarge ? 24 : (isSmall ? 16 : 20),
                        child: const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Creating Account...',
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
                        Icons.person_add_rounded,
                        color: Colors.white,
                        size: isLarge ? 24 : (isSmall ? 18 : 20),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Create Account',
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

  Widget _buildLoginLink(BuildContext context) {
    try {
      final isSmall = _isSmallScreen(context);
      final isLarge = _isLargeScreen(context);
      final fontSize = isLarge ? 16.0 : (isSmall ? 13.0 : 14.0);

      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Already have an account? ',
            style: TextStyle(
              color: AppColors.textLight,
              fontSize: fontSize,
            ),
          ),
          TextButton(
            onPressed: _navigateBack,
            child: Text(
              'Sign In',
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
      debugPrint('Login link error: $e');
      return const SizedBox.shrink();
    }
  }
}
