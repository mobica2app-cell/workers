import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;

class AiAssistantPage extends StatefulWidget {
  final bool embedded;
  final bool isMaximized;
  final VoidCallback? onMinimize;
  final VoidCallback? onToggleMaximize;

  const AiAssistantPage({
    super.key,
    this.embedded = false,
    this.isMaximized = false,
    this.onMinimize,
    this.onToggleMaximize,
  });

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? quickPrompt]) async {
    final question = (quickPrompt ?? _controller.text).trim();
    if (question.isEmpty || _busy) return;
    final username = html.window.localStorage['remembered_username'] ?? '';
    final password = html.window.localStorage['remembered_password'] ?? '';
    if (username.isEmpty || password.isEmpty) {
      _addMessage(const _ChatMessage(
        text: 'Login credentials were not found. Please sign in again.',
        isUser: false,
      ));
      return;
    }

    setState(() {
      _messages.add(_ChatMessage(text: question, isUser: true));
      _controller.clear();
      _busy = true;
    });
    _scrollToBottom();

    try {
      final result = await Supabase.instance.client.functions.invoke(
        'mood-ai',
        body: {'username': username, 'password': password, 'question': question},
      );
      final data = result.data;
      if (result.status < 200 || result.status >= 300) {
        throw Exception(data is Map ? (data['error'] ?? 'Request failed') : 'Request failed');
      }
      final answer = data is Map ? (data['answer'] ?? '').toString() : '';
      _addMessage(_ChatMessage(
        text: answer.isEmpty ? 'No answer was returned.' : answer,
        isUser: false,
      ));
    } catch (e) {
      _addMessage(_ChatMessage(
        text: 'Could not contact MOOD AI. Please try again.\n\nDetails: $e',
        isUser: false,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addMessage(_ChatMessage message) {
    if (!mounted) return;
    setState(() => _messages.add(message));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Colors.white : const Color(0xFF0F172A);
    final surface = dark ? const Color(0xFF171C28) : Colors.white;
    final border = dark ? Colors.white12 : const Color(0xFFE2E8F0);
    final primary = const Color(0xFFDC2626);

    final content = Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          color: dark ? const Color(0xFF111827) : const Color(0xFFFEF2F2),
          child: Row(children: [
            Icon(Icons.lock_outline_rounded, size: 14, color: primary),
            const SizedBox(width: 7),
            Expanded(child: Text(
              'Read-only business assistant · SAP orders',
              style: TextStyle(color: fg.withOpacity(.8), fontSize: 11.5),
            )),
            if (_messages.isNotEmpty)
              Tooltip(
                message: 'Clear conversation',
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: _busy ? null : () => setState(() => _messages.clear()),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(Icons.delete_outline_rounded, size: 17, color: fg.withOpacity(.65)),
                  ),
                ),
              ),
          ]),
        ),
        if (_messages.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('What would you like to know?', style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Ask a question about current or completed orders.', style: TextStyle(color: fg.withOpacity(.65), fontSize: 12)),
              const SizedBox(height: 12),
              Wrap(spacing: 7, runSpacing: 7, children: [
                _suggestion('Summarize current orders'),
                _suggestion('Find delayed orders'),
                _suggestion('Compare main and done orders'),
                _suggestion('لخص الطلبات الحالية'),
              ]),
            ]),
          ),
        Expanded(
          child: _messages.isEmpty
              ? Center(child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 58, height: 58,
                decoration: BoxDecoration(color: primary.withOpacity(.10), borderRadius: BorderRadius.circular(20)),
                child: Icon(Icons.auto_awesome_rounded, size: 29, color: primary),
              ),
              const SizedBox(height: 10),
              Text('MOOD AI is ready', style: TextStyle(color: fg.withOpacity(.7), fontWeight: FontWeight.w600)),
            ]),
          ))
              : ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            itemCount: _messages.length + (_busy ? 1 : 0),
            itemBuilder: (context, index) {
              if (_busy && index == _messages.length) {
                return Align(alignment: Alignment.centerLeft, child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: surface, border: Border.all(color: border), borderRadius: BorderRadius.circular(16)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: primary)),
                    const SizedBox(width: 9),
                    Text('Thinking…', style: TextStyle(color: fg.withOpacity(.7), fontSize: 12)),
                  ]),
                ));
              }
              final m = _messages[index];
              return Align(
                alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 720),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  decoration: BoxDecoration(
                    color: m.isUser ? primary : surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(17),
                      topRight: const Radius.circular(17),
                      bottomLeft: Radius.circular(m.isUser ? 17 : 5),
                      bottomRight: Radius.circular(m.isUser ? 5 : 17),
                    ),
                    border: m.isUser ? null : Border.all(color: border),
                    boxShadow: m.isUser ? [] : [BoxShadow(color: Colors.black.withOpacity(dark ? .08 : .025), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: SelectableText(m.text, style: TextStyle(color: m.isUser ? Colors.white : fg, height: 1.45, fontSize: 13)),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
          decoration: BoxDecoration(color: surface, border: Border(top: BorderSide(color: border))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    _send();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: TextStyle(color: fg, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Ask MOOD AI…',
                    hintStyle: TextStyle(color: fg.withOpacity(.45), fontSize: 13),
                    filled: true,
                    fillColor: dark ? const Color(0xFF0F1420) : const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: primary, width: 1.4)),
                  ),
                )),
            ),
            const SizedBox(width: 8),
            SizedBox(height: 46, width: 46, child: FilledButton(
              onPressed: _busy ? null : () => _send(),
              style: FilledButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: const Icon(Icons.arrow_upward_rounded, size: 21),
            )),
          ]),
        ),
      ],
    );

    if (!widget.embedded) {
      return Scaffold(
        appBar: AppBar(title: const Row(children: [Icon(Icons.auto_awesome, color: Color(0xFFDC2626)), SizedBox(width: 10), Text('MOOD AI')])),
        body: content,
      );
    }

    return Material(
      color: surface,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(20),
      child: Column(children: [
        Container(
          height: 60,
          padding: const EdgeInsets.only(left: 16, right: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF991B1B), Color(0xFFDC2626), Color(0xFFEF4444)]),
            boxShadow: [BoxShadow(color: primary.withOpacity(.18), blurRadius: 12, offset: const Offset(0, 3))],
          ),
          child: Row(children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.white.withOpacity(.16), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20)),
            const SizedBox(width: 10),
            const Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('MOOD AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: .3)),
              Text('Mobica business assistant', style: TextStyle(color: Colors.white70, fontSize: 10.5)),
            ])),
            IconButton(tooltip: widget.isMaximized ? 'Restore size' : 'Maximize', onPressed: widget.onToggleMaximize, icon: Icon(widget.isMaximized ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded, color: Colors.white, size: 19)),
            IconButton(tooltip: 'Minimize', onPressed: widget.onMinimize, icon: const Icon(Icons.remove_rounded, color: Colors.white, size: 22)),
          ]),
        ),
        Expanded(child: content),
      ]),
    );
  }

  Widget _suggestion(String text) => ActionChip(
    label: Text(text, style: const TextStyle(fontSize: 11.5)),
    onPressed: _busy ? null : () => _send(text),
    visualDensity: VisualDensity.compact,
    side: BorderSide(color: const Color(0xFFDC2626).withOpacity(.18)),
    backgroundColor: const Color(0xFFDC2626).withOpacity(.06),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}

class _ChatMessage {
  final String text;
  final bool isUser;
  const _ChatMessage({required this.text, required this.isUser});
}

