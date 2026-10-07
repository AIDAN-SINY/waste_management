/// WhatsApp-style chat bottom sheet for the WastePro chatbot.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:waste_pro/core/brand.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../providers/user_provider.dart';
import '../payment/screens/bills_screen.dart';
import 'chatbot_service.dart';
import 'support_screen.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  static void open(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ChatbotScreen(),
    );
  }

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  final List<_Msg> _messages = [];
  late final ChatbotService _bot;
  bool _typing = false;
  bool _init = false;
  late AnimationController _dots;

  // Design colors
  static const _bg = Color(0xFFF4F7F2);
  static const _surface = Color(0xFFFFFFFF);
  static const _green = Color(0xFF0B5A2A);
  static const _muted = Color(0xFF6E8274);
  static const _border = Color(0xFFE1E9DD);
  static const _text = Color(0xFF13261A);
  static const _greenSoft = Color(0xFFE6F2E4);
  static const _blueSoft = Color(0xFFE7EEFB);

  @override
  void initState() {
    super.initState();
    _dots = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      _init = true;
      _bot = ChatbotService();
      final aiOn = _bot.isAiConfigured;
      _addBot(
        aiOn
            ? "Hey there! I'm WasteBot, your WastePro AI assistant.\n\nAsk me anything about plans, pickups, CamPay payments, or support."
            : "Hey there! I'm WasteBot, your WastePro assistant.\n\nFAQ is ready. To unlock AI answers, add HF_TOKEN in .env and restart the app.",
        'greeting',
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    _dots.dispose();
    super.dispose();
  }

  void _addBot(String text, String intent, {bool confirm = false, List<String> suggestions = const []}) {
    setState(() => _messages.add(_Msg(text: text, user: false, intent: intent, confirm: confirm, suggestions: suggestions)));
    _scrollDown();
  }

  void _addUser(String text) {
    setState(() => _messages.add(_Msg(text: text, user: true)));
    _scrollDown();
  }

  void _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _addUser(text);
    _controller.clear();
    _focus.unfocus();
    setState(() => _typing = true);

    final user = context.read<UserProvider>().user;
    await Future.delayed(const Duration(milliseconds: 500)); // natural feel
    final reply = await _processSafely(text, user);
    if (!mounted) return;
    setState(() => _typing = false);
    _addBot(reply.text, reply.intent, confirm: reply.needsConfirmation, suggestions: reply.suggestions);
    _afterReply(reply);
  }

  void _confirm(bool yes) async {
    _addUser(yes? 'Yes, submit': 'No, cancel');
    setState(() => _typing = true);
    final user = context.read<UserProvider>().user;
    await Future.delayed(const Duration(milliseconds: 400));
    final reply = await _processSafely(yes? 'yes': 'no', user);
    if (!mounted) return;
    setState(() => _typing = false);
    _addBot(reply.text, reply.intent, suggestions: reply.suggestions);
    _afterReply(reply);
  }

  /// Appelle le service en attrapant toute erreur (Firestore hors ligne,
  /// règles… ): le chat affiche un message propre au lieu de planter.
  Future<ChatReply> _processSafely(String text, UserModel? user) async {
    try {
      return await _bot.process(text, user: user);
    } catch (_) {
      return const ChatReply(
        text: "Something went wrong on my end. \n\nPlease try again or contact support.",
        intent: 'error',
      );
    }
  }

  /// Quand le bot s'engage à ouvrir une vraie fonctionnalité (paiement,
  /// support), on la livre: la feuille se ferme et l'écran s'ouvre.
  void _afterReply(ChatReply reply) {
    if (reply.intent == 'payment_initiated') {
      _openFeature(const BillsScreen());
    } else if (reply.intent == 'escalate') {
      _openFeature(const SupportScreen());
    }
  }

  void _openFeature(Widget screen) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => screen));
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bp = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.82, minChildSize: 0.5, maxChildSize: 0.95,
      builder: (_, _) => Container(
        decoration: const BoxDecoration(color: _bg, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          _handle(),
          _header(),
          Expanded(child: _chatList()),
          if (_typing) _typingIndicator(),
          _inputBar(bp),
        ]),
      ),
    );
  }

  Widget _chatList() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _bubble(_messages[i]),
    );
  }

  Widget _bubble(_Msg m) {
    if (m.user) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Flexible(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(color: _green, borderRadius: BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(4))),
            child: Text(m.text, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
          )),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: _greenSoft, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.smart_toy_rounded, color: _green, size: 17),
        ),
        const SizedBox(width: 8),
        Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: _surface, borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)), border: Border.all(color: _border)),
            child: _richText(m.text),
          ),
          if (m.confirm)...[const SizedBox(height: 8), _confirmButtons()],
          if (m.suggestions.isNotEmpty &&!m.confirm)...[const SizedBox(height: 8), _suggestionChips(m.suggestions)],
        ])),
      ]),
    );
  }

  Widget _richText(String text) {
    final parts = text.split(RegExp(r'(\*\*[^*]+\*\*)'));
    final spans = <TextSpan>[];
    for (final p in parts) {
      if (p.startsWith('**') && p.endsWith('**')) {
        spans.add(TextSpan(text: p.substring(2, p.length - 2), style: const TextStyle(color: _text, fontSize: 15, height: 1.5, fontWeight: FontWeight.w700)));
      } else {
        spans.add(TextSpan(text: p, style: const TextStyle(color: _text, fontSize: 15, height: 1.5)));
      }
    }
    return RichText(text: TextSpan(children: spans));
  }

  Widget _confirmButtons() {
    return Row(children: [
      GestureDetector(
        onTap: () => _confirm(true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(20)),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check, color: Colors.white, size: 16),
              SizedBox(width: 6),
              Text('Yes, submit', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => _confirm(false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: _border)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.close, color: _muted, size: 16),
              const SizedBox(width: 6),
              Text('Cancel', style: TextStyle(color: _muted, fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _suggestionChips(List<String> items) {
    return Wrap(
      spacing: 8, runSpacing: 6,
      children: items.map((s) => GestureDetector(
        onTap: () { _controller.text = s; _send(); },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: _blueSoft, borderRadius: BorderRadius.circular(20), border: Border.all(color: _border)),
          child: Text(s, style: const TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.w500)),
        ),
      )).toList(),
    );
  }

  Widget _typingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(left: 40, bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: _greenSoft, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.smart_toy_rounded, color: _green, size: 17),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: _surface, borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)), border: Border.all(color: _border)),
          child: AnimatedBuilder(
            animation: _dots,
            builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
              final opacity = ((_dots.value - i * 0.33).abs() < 0.33)? 1.0: 0.3;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Opacity(opacity: opacity, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: _muted, shape: BoxShape.circle))),
              );
            })),
          ),
        ),
      ]),
    );
  }

  Widget _inputBar(double bp) {
    return Container(
      padding: EdgeInsets.only(left: 16, right: 12, top: 10, bottom: bp + 10),
      decoration: const BoxDecoration(color: _surface, border: Border(top: BorderSide(color: _border))),
      child: Row(children: [
        Expanded(child: Container(
          decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(24), border: Border.all(color: _border)),
          child: TextField(
            controller: _controller, focusNode: _focus,
            textCapitalization: TextCapitalization.sentences, textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            style: const TextStyle(color: _text, fontSize: 15),
            decoration: InputDecoration(hintText: 'Type a message...', hintStyle: TextStyle(color: _muted, fontSize: 14), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
          ),
        )),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _send,
          child: Container(
            width: 42, height: 42,
            decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
          ),
        ),
      ]),
    );
  }

  Widget _handle() {
    return Center(child: Container(margin: const EdgeInsets.only(top: 10, bottom: 4), width: 40, height: 4, decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2))));
  }

  Widget _header() {
    final aiOn = _init && _bot.isAiConfigured;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(color: _surface, border: Border(bottom: BorderSide(color: _border))),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: _greenSoft, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.smart_toy_rounded, color: _green, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('WasteBot', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: _text)),
          Row(children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: aiOn ? Brand.leaf : Brand.gold,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              aiOn ? 'AI online' : 'FAQ only — add HF_TOKEN',
              style: TextStyle(
                fontSize: 11,
                color: aiOn ? Brand.leaf : Brand.goldDim,
              ),
            ),
          ]),
        ])),
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(width: 32, height: 32, decoration: BoxDecoration(color: _bg, shape: BoxShape.circle), child: Icon(Icons.close, color: _muted, size: 18)),
        ),
      ]),
    );
  }
}

class _Msg {
  const _Msg({required this.text, required this.user, this.intent = '', this.confirm = false, this.suggestions = const []});
  final String text;
  final bool user;
  final String intent;
  final bool confirm;
  final List<String> suggestions;
}
