import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/appearance.dart';
import '../../core/theme.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/gradient_avatar.dart';
import 'auth_controller.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The live preview avatar tracks whatever tag is being typed.
    _usernameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).register(
            _usernameController.text.trim(),
            _passwordController.text,
          );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Colours come from AppColors statics, which Flutter can't track;
    // this makes the screen rebuild when the palette changes.
    watchPalette(ref);
    final typedTag = _usernameController.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Создать аккаунт'),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: NightBackdrop(
        child: Stack(
          children: [
            Positioned(bottom: -80, right: -70, child: GlowOrb(color: AppColors.accent, size: 320, opacity: 0.12)),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: typedTag.isEmpty
                                  ? const BrandMark(key: ValueKey('brand'), size: 76)
                                  : GradientAvatar(
                                      key: ValueKey(typedTag[0]),
                                      username: typedTag,
                                      size: 76,
                                      showPulse: true,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            typedTag.isEmpty ? 'Выберите свой тег' : '@$typedTag',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'По этому тегу друзья найдут вас на этом узле.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
                          ),
                          const SizedBox(height: 30),
                          TextFormField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Тег',
                              hintText: 'username',
                              prefixText: '@',
                              prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                            ),
                            validator: (v) {
                              final value = v?.trim() ?? '';
                              if (value.isEmpty) return 'Введите тег';
                              if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(value)) {
                                return '3–20 символов: латиница, цифры, _';
                              }
                              return null;
                            },
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Пароль',
                              helperText: 'Минимум 8 символов',
                              helperStyle: TextStyle(color: AppColors.textMuted, fontSize: 12),
                              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  size: 20,
                                ),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            obscureText: _obscure,
                            validator: (v) => (v == null || v.length < 8) ? 'Минимум 8 символов' : null,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            ErrorBanner(message: _error!),
                          ],
                          const SizedBox(height: 28),
                          FilledButton(
                            onPressed: _submitting ? null : _submit,
                            child: _submitting
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                  )
                                : const Text('Создать аккаунт'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
