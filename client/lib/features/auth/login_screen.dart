/// Signing in to the node the app is connected to.
///
/// Two ways in. Accounts used before appear as tiles and need no password —
/// the node issued a month-long refresh token for exactly this, and tapping a
/// tile trades it for a fresh session. Below them, a tile opens the password
/// form, which is also what the screen shows outright when nothing is saved
/// or when a stored token has aged out.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/appearance.dart';
import '../../core/theme.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/gradient_avatar.dart';
import '../connect/node_controller.dart';
import 'auth_controller.dart';
import 'saved_account.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  /// The form replaces the list rather than sitting under it: together they
  /// don't fit above a phone keyboard.
  bool _enteringPassword = false;

  /// Prefilled when a saved sign-in fails, so the user doesn't retype a tag
  /// the app already knows.
  String? _prefilledUsername;
  String? _error;

  @override
  Widget build(BuildContext context) {
    // Colours come from AppColors statics, which Flutter can't track;
    // this makes the screen rebuild when the palette changes.
    watchPalette(ref);
    final host = ref.watch(nodeControllerProvider).valueOrNull?.host;
    final accounts = ref.watch(savedAccountsProvider);

    final showForm = _enteringPassword || (accounts.valueOrNull?.isEmpty ?? false);

    return Scaffold(
      body: NightBackdrop(
        child: Stack(
          children: [
            Positioned(top: -80, left: -70, child: GlowOrb(color: AppColors.primary, size: 320)),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const BrandMark(size: 72),
                        const SizedBox(height: 24),
                        Text(
                          showForm ? 'С возвращением' : 'Кто вы?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.6,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (host != null) ...[
                          const SizedBox(height: 8),
                          _NodeChip(host: host),
                        ],
                        const SizedBox(height: 32),
                        if (_error != null) ...[
                          ErrorBanner(message: _error!),
                          const SizedBox(height: 18),
                        ],
                        if (showForm)
                          _PasswordForm(
                            initialUsername: _prefilledUsername,
                            onCancel: (accounts.valueOrNull?.isNotEmpty ?? false)
                                ? () => setState(() {
                                      _enteringPassword = false;
                                      _error = null;
                                    })
                                : null,
                            onError: (message) => setState(() => _error = message),
                          )
                        else
                          _SavedAccountList(
                            accounts: accounts,
                            onUseAnother: () => setState(() {
                              _enteringPassword = true;
                              _prefilledUsername = null;
                              _error = null;
                            }),
                            onNeedsPassword: (account, message) => setState(() {
                              _enteringPassword = true;
                              _prefilledUsername = account.username;
                              _error = message;
                            }),
                          ),
                      ],
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

class _SavedAccountList extends StatelessWidget {
  final AsyncValue<List<SavedAccount>> accounts;
  final VoidCallback onUseAnother;
  final void Function(SavedAccount account, String message) onNeedsPassword;

  const _SavedAccountList({
    required this.accounts,
    required this.onUseAnother,
    required this.onNeedsPassword,
  });

  @override
  Widget build(BuildContext context) {
    return accounts.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _AddAccountTile(onTap: onUseAnother),
      data: (list) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final account in list) ...[
            _SavedAccountTile(account: account, onNeedsPassword: onNeedsPassword),
            const SizedBox(height: 10),
          ],
          _AddAccountTile(onTap: onUseAnother),
        ],
      ),
    );
  }
}

class _SavedAccountTile extends ConsumerStatefulWidget {
  final SavedAccount account;
  final void Function(SavedAccount account, String message) onNeedsPassword;

  const _SavedAccountTile({required this.account, required this.onNeedsPassword});

  @override
  ConsumerState<_SavedAccountTile> createState() => _SavedAccountTileState();
}

class _SavedAccountTileState extends ConsumerState<_SavedAccountTile> {
  bool _busy = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).signInWithSaved(widget.account);
    } catch (e) {
      // An expired token is the expected end of a saved session, not a fault:
      // hand the user to the password form with their tag already filled in.
      widget.onNeedsPassword(widget.account, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmForget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Убрать аккаунт?'),
        content: Text(
          '@${widget.account.username} исчезнет из списка на этом устройстве. '
          'Сам аккаунт и переписка останутся на узле — войти можно будет по паролю.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Убрать', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).forgetAccount(widget.account);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceOutline),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _busy ? null : _signIn,
          onLongPress: _confirmForget,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                GradientAvatar(
                  username: widget.account.username,
                  size: 44,
                  userId: widget.account.userId,
                  hasAvatar: widget.account.hasAvatar,
                  avatarUpdatedAt: widget.account.avatarUpdatedAt,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '@${widget.account.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (_busy)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                else
                  IconButton(
                    onPressed: _confirmForget,
                    tooltip: 'Убрать аккаунт',
                    icon: Icon(Icons.close_rounded, size: 19, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddAccountTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddAccountTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceOutline),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surfaceHigh,
                    border: Border.all(color: AppColors.surfaceOutline),
                  ),
                  child: Icon(Icons.add_rounded, color: AppColors.primary, size: 23),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Другой аккаунт',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Вход по тегу и паролю',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordForm extends ConsumerStatefulWidget {
  final String? initialUsername;

  /// Null when there are no saved accounts to go back to.
  final VoidCallback? onCancel;
  final void Function(String message) onError;

  const _PasswordForm({
    required this.initialUsername,
    required this.onCancel,
    required this.onError,
  });

  @override
  ConsumerState<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends ConsumerState<_PasswordForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController =
      TextEditingController(text: widget.initialUsername ?? '');
  final _passwordController = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ref.read(authControllerProvider.notifier).login(
            _usernameController.text.trim(),
            _passwordController.text,
          );
    } catch (e) {
      widget.onError(e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'Ваш тег',
              hintText: 'username',
              prefixText: '@',
              prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите тег' : null,
            textInputAction: TextInputAction.next,
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: 'Пароль',
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
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  )
                : const Text('Войти'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _submitting ? null : () => context.push('/register'),
            child: Text.rich(
              TextSpan(
                text: 'Нет аккаунта? ',
                children: [
                  TextSpan(
                    text: 'Создать',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          if (widget.onCancel != null)
            TextButton(
              onPressed: _submitting ? null : widget.onCancel,
              child: const Text('К списку аккаунтов'),
            ),
        ],
      ),
    );
  }
}

class _NodeChip extends StatelessWidget {
  final String host;

  const _NodeChip({required this.host});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: AppColors.surfaceOutline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
            ),
            const SizedBox(width: 9),
            Text(
              host,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
