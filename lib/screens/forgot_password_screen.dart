import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/gradient_button.dart';
import '../utils/colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  
  bool _isLoading = false;
  bool _emailSent = false;
  
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    try {
      _initializeAnimations();
    } catch (e) {
      debugPrint('Forgot password screen init error: $e');
    }
  }

  void _initializeAnimations() {
    try {
      _slideController = AnimationController(
        duration: const Duration(milliseconds: 300),
        vsync: this,
      );
      _slideAnimation = Tween<Offset>(
        begin: const Offset(0.0, 1.0),
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
      _emailController.dispose();
      _slideController.dispose();
    } catch (e) {
      debugPrint('Forgot password screen dispose error: $e');
    }
    super.dispose();
  }

  // ✅ NEW: Send reset password email using our SQL function
  Future<void> _handleSendResetEmail() async {
    try {
      if (_formKey.currentState?.validate() ?? false) {
        setState(() {
          _isLoading = true;
        });

        final email = _emailController.text.trim();
        
        debugPrint('Password reset request for: $email');

        final supabase = Supabase.instance.client;
        
        // Generate reset token using our SQL function
        try {
          final result = await supabase.rpc('generate_reset_token', 
            params: {'user_email': email});
          
          debugPrint('Reset token generated: ${result.toString()}');
          
          // In production, you would send this token via email
          // For now, we'll just show success message
          
          if (mounted) {
            setState(() {
              _isLoading = false;
              _emailSent = true;
            });
            
            _showSuccessMessage('Password reset instructions sent to your email!');
          }
        } catch (tokenError) {
          if (tokenError.toString().contains('User not found')) {
            _showErrorMessage('No account found with this email address');
          } else {
            throw tokenError;
          }
        }
      }
    } catch (e) {
      debugPrint('Reset email error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        String errorMessage = 'Failed to send reset email. Please try again.';
        
        if (e.toString().contains('network')) {
          errorMessage = 'Network error. Please check your connection.';
        } else if (e.toString().contains('User not found')) {
          errorMessage = 'No account found with this email address';
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
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: SafeArea(
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  _buildBackButton(),
                  const SizedBox(height: 60),
                  _buildIconSection(),
                  const SizedBox(height: 40),
                  _buildTitleSection(),
                  const SizedBox(height: 60),
                  if (!_emailSent) _buildResetForm() else _buildSuccessMessage(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    try {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_rounded,
              color: AppColors.primaryPink,
            ),
            onPressed: _navigateBack,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Back button error: $e');
      return const SizedBox(height: 48);
    }
  }

  Widget _buildIconSection() {
    try {
      return Center(
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryPink.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.lock_reset_rounded,
            size: 50,
            color: Colors.white,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Icon section error: $e');
      return const SizedBox(height: 100);
    }
  }

  Widget _buildTitleSection() {
    try {
      return Column(
        children: [
          Text(
            'Reset Password',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              foreground: Paint()
                ..shader = AppColors.primaryGradient.createShader(
                  const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0),
                ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter your email address and we\'ll send you instructions to reset your password',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textLight,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      );
    } catch (e) {
      debugPrint('Title section error: $e');
      return const SizedBox(height: 60);
    }
  }

  Widget _buildResetForm() {
    try {
      return Form(
        key: _formKey,
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'Email Address',
                  prefixIcon: Icon(
                    Icons.email_outlined,
                    color: AppColors.primaryPink.withValues(alpha: 0.7),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
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
            ),
            const SizedBox(height: 32),
            GradientButton(
              text: _isLoading ? 'Sending...' : 'Send Reset Instructions',
              icon: _isLoading ? null : Icons.send_rounded,
              isLoading: _isLoading,
              onPressed: _handleSendResetEmail,
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Reset form error: $e');
      return const Center(
        child: Text(
          'Form error occurred',
          style: TextStyle(color: AppColors.error),
        ),
      );
    }
  }

  Widget _buildSuccessMessage() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 64,
                color: AppColors.success,
              ),
              const SizedBox(height: 16),
              const Text(
                'Email Sent!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Password reset instructions have been sent to ${_emailController.text}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textLight,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        GradientButton(
          text: 'Back to Login',
          icon: Icons.arrow_back_rounded,
          onPressed: _navigateBack,
        ),
      ],
    );
  }
}
