import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class InteractiveBentoCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final Color color;
  final double? height;

  const InteractiveBentoCard({
    super.key,
    required this.child,
    required this.onTap,
    required this.color,
    this.height,
  });

  @override
  State<InteractiveBentoCard> createState() => _InteractiveBentoCardState();
}

class _InteractiveBentoCardState extends State<InteractiveBentoCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: widget.child,
        ),
      ),
    );
  }
}
