import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/colors.dart';

class GradientButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final double? width;
  final double height;
  final double borderRadius;
  final bool isLoading;
  final IconData? icon;
  final TextStyle? textStyle;

  const GradientButton({
    super.key,
    required this.text,
    this.onPressed,
    this.width,
    this.height = 56.0,
    this.borderRadius = 28.0,
    this.isLoading = false,
    this.icon,
    this.textStyle,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    try {
      _animationController = AnimationController(
        duration: const Duration(milliseconds: 150),
        vsync: this,
      );
      _scaleAnimation = Tween<double>(
        begin: 1.0,
        end: 0.95,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ));
    } catch (e) {
      debugPrint('GradientButton animation init error: $e');
    }
  }

  @override
  void dispose() {
    try {
      _animationController.dispose();
    } catch (e) {
      debugPrint('GradientButton dispose error: $e');
    }
    super.dispose();
  }

  Future<void> _handleTap() async {
    try {
      if (widget.onPressed != null && !widget.isLoading) {
        // ✅ FIXED: Proper button press animation
        HapticFeedback.lightImpact();
        await _animationController.forward();
        await _animationController.reverse();
        
        // ✅ FIXED: Execute callback after animation
        widget.onPressed!();
      }
    } catch (e) {
      debugPrint('Button tap error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.width ?? double.infinity,
              height: widget.height,
              decoration: BoxDecoration(
                gradient: widget.onPressed != null && !widget.isLoading
                    ? AppColors.buttonGradient
                    : LinearGradient(
                        colors: [
                          Colors.grey.shade400,
                          Colors.grey.shade500,
                        ],
                      ),
                borderRadius: BorderRadius.circular(widget.borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: widget.onPressed != null
                        ? AppColors.primaryPink.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.isLoading ? null : _handleTap,
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  child: Container(
                    alignment: Alignment.center,
                    child: widget.isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.icon != null) ...[
                                Icon(
                                  widget.icon,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                              ],
                              Text(
                                widget.text,
                                style: widget.textStyle ??
                                    const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('GradientButton build error: $e');
      // ✅ Fallback UI in case of error
      return Container(
        width: widget.width ?? double.infinity,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        child: const Center(
          child: Text(
            'Button Error',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }
}
