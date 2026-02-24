import 'package:flutter/material.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key, required this.onEnter});

  final VoidCallback onEnter;

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  static const _dark = Color(0xFF0A0A0A);
  static const _gold = Color(0xFFD4AF37);
  static const _steel = Color(0xFF64748B);
  var _entered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _entered = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final animateIn = disableAnimations ? true : _entered;
    final duration = disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 650);
    final shortDuration = disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 500);

    return Scaffold(
      backgroundColor: _dark,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: animateIn ? Alignment.topLeft : const Alignment(-0.4, -1),
            end: animateIn ? Alignment.bottomRight : const Alignment(0.8, 1),
            colors: [_dark, const Color(0xFF101318), _dark],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 48,
              right: -40,
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                width: animateIn ? 160 : 100,
                height: animateIn ? 160 : 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _gold.withValues(alpha: animateIn ? 0.1 : 0.02),
                ),
              ),
            ),
            Positioned(
              bottom: 80,
              left: -30,
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                width: animateIn ? 120 : 80,
                height: animateIn ? 120 : 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _steel.withValues(alpha: animateIn ? 0.12 : 0.03),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    AnimatedSlide(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      offset: animateIn ? Offset.zero : const Offset(0, 0.12),
                      child: AnimatedOpacity(
                        duration: shortDuration,
                        curve: Curves.easeOut,
                        opacity: animateIn ? 1 : 0,
                        child: const Text(
                          'NStyle\nSentinel',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 64,
                            height: 0.9,
                            letterSpacing: -1.5,
                            fontWeight: FontWeight.w700,
                            color: _gold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedSlide(
                      duration: disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 750),
                      curve: Curves.easeOutCubic,
                      offset: animateIn ? Offset.zero : const Offset(0, 0.2),
                      child: AnimatedOpacity(
                        duration: duration,
                        curve: Curves.easeOut,
                        opacity: animateIn ? 1 : 0,
                        child: const Text(
                          'BY TONEY',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w600,
                            color: _steel,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    AnimatedSlide(
                      duration: disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 850),
                      curve: Curves.easeOutBack,
                      offset: animateIn ? Offset.zero : const Offset(0, 0.28),
                      child: AnimatedOpacity(
                        duration: duration,
                        curve: Curves.easeOut,
                        opacity: animateIn ? 1 : 0,
                        child: TweenAnimationBuilder<double>(
                          duration: disableAnimations
                              ? Duration.zero
                              : const Duration(milliseconds: 850),
                          curve: Curves.easeOutBack,
                          tween: Tween<double>(
                            begin: animateIn ? 1 : 0.96,
                            end: 1,
                          ),
                          builder: (context, value, child) {
                            return Transform.scale(scale: value, child: child);
                          },
                          child: ElevatedButton(
                            onPressed: widget.onEnter,
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 44),
                              backgroundColor: _gold,
                              foregroundColor: _dark,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            child: const Text(
                              'Initialize Secure System',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
