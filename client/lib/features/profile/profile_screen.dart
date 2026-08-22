/// Editing your own profile: picture, tag, password.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/appearance.dart';
import '../../core/theme.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/gradient_avatar.dart';
import '../auth/auth_controller.dart';
import 'profile_controller.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _busyAvatar = false;
  String? _avatarError;

  Future<void> _pickAvatar() async {
    const typeGroup = XTypeGroup(
      label: 'Изображения',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
    );

    setState(() => _avatarError = null);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;

    setState(() => _busyAvatar = true);
    try {
      final bytes = await file.readAsBytes();
      await ref.read(profileControllerProvider).uploadAvatar(bytes);
    } catch (e) {
      setState(() => _avatarError = e.toString());
    } finally {
      if (mounted) setState(() => _busyAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    setState(() {
      _busyAvatar = true;
      _avatarError = null;
    });
    try {
      await ref.read(profileControllerProvider).removeAvatar();
    } catch (e) {
      setState(() => _avatarError = e.toString());
    } finally {
      if (mounted) setState(() => _busyAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    watchPalette(ref);
    final user = ref.watch(authControllerProvider).valueOrNull?.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      extendBodyBehindAppBar: true,
      body: NightBackdrop(
        child: SafeArea(
          child: user == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    Center(
                      child: Column(
                        children: [
                          Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              GradientAvatar(
                                username: user.username,
                                size: 116,
                                showPulse: true,
                                userId: user.id,
                                hasAvatar: user.hasAvatar,
                                avatarUpdatedAt: user.avatarUpdatedAt,
                              ),
                              Material(
                                color: AppColors.primary,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _busyAvatar ? null : _pickAvatar,
                                  child: Padding(
                                    padding: const EdgeInsets.all(9),
                                    child: _busyAvatar
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.photo_camera_rounded,
                                            size: 16, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '@${user.username}',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (user.hasAvatar) ...[
                            const SizedBox(height: 4),
                            TextButton(
                              onPressed: _busyAvatar ? null : _removeAvatar,
                              child: const Text('Убрать фото'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_avatarError != null) ...[
                      const SizedBox(height: 12),
                      ErrorBanner(message: _avatarError!),
                    ],
                    const SizedBox(height: 28),
                    const _SectionTitle('Тег'),
                    const SizedBox(height: 12),
                    _UsernameCard(currentUsername: user.username),
                    const SizedBox(height: 28),
                    const _SectionTitle('Пароль'),
                    const SizedBox(height: 12),
                    const _PasswordCard(),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: AppColors.textMuted,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceOutline),
      ),
      child: child,
    );
  }
}

class _UsernameCard extends ConsumerStatefulWidget {
  final String currentUsername;

  const _UsernameCard({required this.currentUsername});

  @override
  ConsumerState<_UsernameCard> createState() => _UsernameCardState();
}

class _UsernameCardState extends ConsumerState<_UsernameCard> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.currentUsername);
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final next = _controller.text.trim();
    if (next == widget.currentUsername) return;

    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      await ref.read(profileControllerProvider).changeUsername(next);
      if (mounted) setState(() => _success = 'Тег обновлён');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Ваш тег',
                prefixText: '@',
                prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
              ),
              autocorrect: false,
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Введите тег';
                if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(value)) {
                  return '3–20 символов: латиница, цифры, _';
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            Text(
              'По этому тегу вас находят. После смены старый тег освободится.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              ErrorBanner(message: _error!),
            ],
            if (_success != null) ...[
              const SizedBox(height: 10),
              Text(_success!, style: const TextStyle(color: AppColors.success, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Text('Сохранить тег'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordCard extends ConsumerStatefulWidget {
  const _PasswordCard();

  @override
  ConsumerState<_PasswordCard> createState() => _PasswordCardState();
}

class _PasswordCardState extends ConsumerState<_PasswordCard> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      await ref.read(profileControllerProvider).changePassword(_current.text, _next.text);
      if (!mounted) return;
      _current.clear();
      _next.clear();
      _repeat.clear();
      setState(() => _success = 'Пароль изменён');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _current,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Текущий пароль',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'Введите текущий пароль' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _next,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Новый пароль',
                prefixIcon: Icon(Icons.lock_reset_rounded, size: 20),
              ),
              validator: (v) => (v == null || v.length < 8) ? 'Минимум 8 символов' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _repeat,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Повторите новый пароль',
                prefixIcon: Icon(Icons.check_rounded, size: 20),
              ),
              validator: (v) => v != _next.text ? 'Пароли не совпадают' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              ErrorBanner(message: _error!),
            ],
            if (_success != null) ...[
              const SizedBox(height: 10),
              Text(_success!, style: const TextStyle(color: AppColors.success, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Text('Изменить пароль'),
            ),
          ],
        ),
      ),
    );
  }
}
