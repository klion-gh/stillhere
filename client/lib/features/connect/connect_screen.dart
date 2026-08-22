/// Choosing a node: tiles for the ones paired before, each with a live round
/// trip, above a tile that opens the address-and-password form. The form is what
/// the screen shows outright on first run, when there is nothing to choose
/// between.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/appearance.dart';
import '../../core/theme.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/gradient_avatar.dart';
import 'node_controller.dart';
import 'node_ping.dart';
import 'saved_node.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  /// The add form replaces the list rather than sitting under it: on a phone
  /// the two together don't fit above the keyboard.
  bool _addingServer = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    // Colours come from AppColors statics, which Flutter can't track;
    // this makes the screen rebuild when the palette changes.
    watchPalette(ref);
    final saved = ref.watch(savedNodesProvider);

    // Nothing saved yet means there's nothing to choose between, so the first
    // run goes straight to the form.
    final showForm = _addingServer || (saved.valueOrNull?.isEmpty ?? false);

    return Scaffold(
      body: NightBackdrop(
        child: Stack(
          children: [
            Positioned(top: -60, right: -80, child: GlowOrb(color: AppColors.primary, size: 340)),
            Positioned(bottom: -100, left: -60, child: GlowOrb(color: AppColors.accent, size: 300, opacity: 0.1)),
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
                        const BrandMark(),
                        const SizedBox(height: 28),
                        Text(
                          'StillHere',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          showForm
                              ? 'Подключитесь к своему узлу.\nАдрес и пароль даст тот, кто его развернул.'
                              : 'Выберите узел или добавьте новый.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.5),
                        ),
                        const SizedBox(height: 32),
                        if (_error != null) ...[
                          ErrorBanner(message: _error!),
                          const SizedBox(height: 18),
                        ],
                        if (showForm)
                          _AddServerForm(
                            // Only offer a way back when there's a list to go
                            // back to.
                            onCancel: (saved.valueOrNull?.isNotEmpty ?? false)
                                ? () => setState(() {
                                      _addingServer = false;
                                      _error = null;
                                    })
                                : null,
                            onError: (message) => setState(() => _error = message),
                          )
                        else
                          _SavedServerList(
                            saved: saved,
                            onAdd: () => setState(() {
                              _addingServer = true;
                              _error = null;
                            }),
                            onError: (message) => setState(() => _error = message),
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

class _SavedServerList extends ConsumerWidget {
  final AsyncValue<List<SavedNode>> saved;
  final VoidCallback onAdd;
  final void Function(String message) onError;

  const _SavedServerList({required this.saved, required this.onAdd, required this.onError});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return saved.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_AddServerTile(onTap: onAdd)],
      ),
      data: (nodes) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final node in nodes) ...[
            _SavedServerTile(node: node, onError: onError),
            const SizedBox(height: 10),
          ],
          _AddServerTile(onTap: onAdd),
        ],
      ),
    );
  }
}

class _SavedServerTile extends ConsumerStatefulWidget {
  final SavedNode node;
  final void Function(String message) onError;

  const _SavedServerTile({required this.node, required this.onError});

  @override
  ConsumerState<_SavedServerTile> createState() => _SavedServerTileState();
}

class _SavedServerTileState extends ConsumerState<_SavedServerTile> {
  bool _connecting = false;

  Future<void> _connect() async {
    setState(() => _connecting = true);
    try {
      await ref.read(nodeControllerProvider.notifier).connectToSaved(widget.node);
    } catch (e) {
      widget.onError(e.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _confirmForget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Убрать узел?'),
        content: Text(
          '${widget.node.host} исчезнет из списка. Чтобы вернуться, понадобятся адрес и пароль узла.',
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
      await ref.read(nodeControllerProvider.notifier).forgetSaved(widget.node.host);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ping = ref.watch(nodePingProvider(widget.node));

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
          onTap: _connecting ? null : _connect,
          onLongPress: _confirmForget,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.brandGradient,
                  ),
                  child: const Icon(Icons.dns_rounded, color: Colors.white, size: 21),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.node.host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      _PingLabel(ping: ping),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (_connecting)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                else
                  IconButton(
                    onPressed: _confirmForget,
                    tooltip: 'Убрать узел',
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

/// Round trip to the node, or why there isn't one.
class _PingLabel extends StatelessWidget {
  final AsyncValue<NodePing> ping;

  const _PingLabel({required this.ping});

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (ping) {
      AsyncData(:final value) when value.reachable => (
          '${value.millis} мс',
          // Thresholds chosen for how a call will feel, not for looks: under
          // 150 ms is comfortable, past 400 ms audio starts to collide.
          value.millis! < 150
              ? AppColors.success
              : (value.millis! < 400 ? AppColors.textSecondary : AppColors.danger),
        ),
      AsyncData() => ('нет связи', AppColors.danger),
      AsyncError() => ('нет связи', AppColors.danger),
      _ => ('проверяем…', AppColors.textMuted),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }
}

class _AddServerTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddServerTile({required this.onTap});

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
                        'Добавить сервер',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Адрес и пароль узла',
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

class _AddServerForm extends ConsumerStatefulWidget {
  /// Null on first run, when there's no list to return to.
  final VoidCallback? onCancel;
  final void Function(String message) onError;

  const _AddServerForm({required this.onCancel, required this.onError});

  @override
  ConsumerState<_AddServerForm> createState() => _AddServerFormState();
}

class _AddServerFormState extends ConsumerState<_AddServerForm> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;

  @override
  void dispose() {
    _hostController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ref.read(nodeControllerProvider.notifier).pair(
            _hostController.text.trim(),
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
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: 'Адрес сервера',
              hintText: 'chat.example.com или 203.0.113.42',
              prefixIcon: Icon(Icons.dns_rounded, size: 20),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите адрес' : null,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: 'Пароль узла',
              prefixIcon: const Icon(Icons.key_rounded, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            obscureText: _obscure,
            validator: (v) => (v == null || v.isEmpty) ? 'Введите пароль узла' : null,
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
                : const Text('Подключиться'),
          ),
          if (widget.onCancel != null) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: _submitting ? null : widget.onCancel,
              child: const Text('К списку серверов'),
            ),
          ],
        ],
      ),
    );
  }
}
