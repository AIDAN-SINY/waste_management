/// Simple chatbot service for WastePro clients.
///
/// Handles FAQ, account queries (Firestore), and write operations with confirmation.
/// All in one file — keep it simple.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../services/huggingface_chat_service.dart';

/// Supported languages for the chatbot.
enum Lang { en, fr }

/// Translation keys and their localised strings.
Map<String, Map<Lang, String>> _translations = {
  'confirm_yes': {
    Lang.en: "Great!",
    Lang.fr: "Super !",
  },
  'confirm_no': {
    Lang.en: "No problem! I've cancelled that.",
    Lang.fr: "Pas de souci ! J'ai annulé.",
  },
  'greeting': {
    Lang.en: "Hey there! I'm WasteBot, your WastePro assistant.\n\nHow can I help you today?",
    Lang.fr: "Salut ! Je suis WasteBot, votre assistant WastePro.\n\nComment puis-je vous aider aujourd'hui ?",
  },
  'thanks': {
    Lang.en: "You're welcome! Anything else?",
    Lang.fr: "De rien ! Autre chose ?",
  },
  'escalate': {
    Lang.en: "I'll connect you with an Agency representative. \n\nThey'll contact you shortly. Is there anything else I can help with?",
    Lang.fr: "Je vais vous connecter à un représentant de l'agence. \n\nIls vous contacteront sous peu. Puis-je vous aider avec autre chose ?",
  },
  'upgrade': {
    Lang.en: "Easy! \n\n1. Go to Subscription Plan\n2. Choose your new plan\n3. Pay via MoMo/Orange Money\n\nTakes 30 seconds!",
    Lang.fr: "Facile ! \n\n1. Allez dans Abonnement\n2. Choisissez votre nouveau plan\n3. Payez via MoMo/Orange Money\n\nÇa prend 30 secondes !",
  },
  'plan_difference': {
    Lang.en: "It's all about pickup frequency! \n\n Essential (5k) → 2 pickups/week\n Standard (10k) → 3 pickups/week\n Premium (15k) → Daily pickups\n\nMore pickups = cleaner area!",
    Lang.fr: "C'est tout une question de fréquence de collecte ! \n\n Essentiel (5k) → 2 collectes/semaine\n Standard (10k) → 3 collectes/semaine\n Premium (15k) → Collectes quotidiennes\n\nPlus de collectes = zone plus propre !",
  },
  'plans': {
    Lang.en: "We've got 3 plans! \n\n Essential — 5,000 XAF/mo → 2x/week\n Standard — 10,000 XAF/mo → 3x/week\n Premium — 15,000 XAF/mo → daily",
    Lang.fr: "Nous avons 3 plans ! \n\n Essentiel — 5 000 XAF/mois → 2x/semaine\n Standard — 10 000 XAF/mois → 3x/semaine\n Premium — 15 000 XAF/mois → quotidien",
  },
  'support': {
    Lang.en: "We're here for you! \n\n WhatsApp: +237 696 713 899\n Call: +237 696 713 899\n Email: support@wastepro.cm",
    Lang.fr: "Nous sommes là pour vous ! \n\n WhatsApp: +237 696 713 899\n Appel: +237 696 713 899\n Email: support@wastepro.cm",
  },
  'report_issue': {
    Lang.en: "Super quick! \n\n1. Tap Report Issue\n2. Pick a category\n3. Add details\n4. Submit!",
    Lang.fr: "Super rapide ! \n\n1. Touchez Signaler un problème\n2. Choisissez une catégorie\n3. Ajoutez des détails\n4. Envoyez !",
  },
  'how_it_works': {
    Lang.en: "Super simple! \n\n1. Pick a plan\n2. We assign a collector to your zone\n3. Collector picks up on scheduled days\n4. Collector marks the pickup done\n5. You get a notification to confirm\n6. Confirm or dispute the pickup!\n7. Track everything on your dashboard!",
    Lang.fr: "Super simple ! \n\n1. Choisissez un plan\n2. On vous assigne un collecteur dans votre zone\n3. Le collecteur vient les jours prévus\n4. Le collecteur marque la collecte\n5. Vous recevez une notification pour confirmer\n6. Confirmez ou contestez la collecte !\n7. Tout garder un œil sur votre tableau de bord !",
  },
  'validation': {
    Lang.en: "Two-step now! \n\n1. Collector verifies with OTP or QR code\n2. You get a notification to confirm\n3. Tap Confirm — pickup is verified! \n4. Or tap Report an issue to dispute\n\nAfter confirmation, the collector is credited and the pickup is complete!",
    Lang.fr: "Maintenant en deux étapes ! \n\n1. Le collecteur vérifie avec OTP ou code QR\n2. Vous recevez une notification pour confirmer\n3. Touchez Confirmer — collecte vérifiée ! \n4. Ou Touchez Signaler un problème pour contester\n\nAprès confirmation, le collecteur est crédité et la collecte est terminée !",
  },
  'missed_pickup': {
    Lang.en: "No stress! \n\n• Your collector will note it\n• Book an extra pickup (1,000 XAF)\n• Tap Request Pickup on dashboard\n\nWe've got your back!",
    Lang.fr: "Pas de stress ! \n\n• Votre collecteur le notera\n• Réservez une collecte supplémentaire (1 000 XAF)\n• Touchez Demander une collecte sur le tableau de bord\n\nOn est là pour vous !",
  },
  'payment_methods': {
    Lang.en: "Mobile Money! \n\n• MTN MoMo\n• Orange Money\n\nPowered by CamPay — secure & instant!",
    Lang.fr: "Monnaie mobile ! \n\n• MTN MoMo\n• Orange Money\n\nExécuté par CamPay — sécurisé et instantané !",
  },
  'extra_pickup': {
    Lang.en: "Easy! \n\n1. Tap Request Pickup\n2. Pay 1,000 XAF via MoMo/Orange Money\n3. Collector arrives within 24h! ⏰",
    Lang.fr: "Facile ! \n\n1. Touchez Demander une collecte\n2. Payez 1 000 XAF via MoMo/Orange Money\n3. Le collecteur arrive sous 24h ! ⏰",
  },
  'update_address': {
    Lang.en: "Here's how! \n\n1. Go to Profile\n2. Tap Edit Profile\n3. Update your zone",
    Lang.fr: "Voici comment ! \n\n1. Allez dans Profil\n2. Touchez Modifier le profil\n3. Mettez à jour votre zone",
  },
  'password': {
    Lang.en: "Forgot your password? On the login screen, tap \"Forgot password?\", enter your phone number and the code we send you by SMS, then choose a new password.",
    Lang.fr: "Mot de passe oublié ? Sur l'écran de connexion, touchez « Forgot password? », entrez votre numéro puis le code reçu par SMS, et choisissez un nouveau mot de passe.",
  },
  'track': {
    Lang.en: "Live tracking! \n\nScroll to the Tracking section — you'll see a mini-map with your collector's position!",
    Lang.fr: "Suivi en direct ! \n\nFaites défiler vers la section Suivi — vous verrez une mini-carte avec la position de votre collecteur !",
  },
  'need_login': {
    Lang.en: "I need you to be logged in for that. Please log in first!",
    Lang.fr: "Je besoin que vous soyez connecté pour ça. Connectez-vous d'abord !",
  },
  'unknown': {
    Lang.en: "I'm not sure about that one \n\nTry asking about:\n Plans & pricing\n How collection works\n Payment methods\n My next pickup\n Reporting issues",
    Lang.fr: "Je ne suis pas sûr de ça \n\nEssayez de demander :\n Plans et prix\n Comment la collecte fonctionne\n Méthodes de paiement\n Ma prochaine collecte\n Signaler des problèmes",
  },
  'no_schedule': {
    Lang.en: "No pickup schedule set up yet. \n\nSubscribe to a plan to get regular pickups!",
    Lang.fr: "Pas encore de calendrier de collecte configuré. \n\nAbonnez-vous à un plan pour des collectes régulières !",
  },
  'no_subscription': {
    Lang.en: "You don't have an active subscription yet. \n\nChoose a plan to start getting regular pickups!",
    Lang.fr: "Vous n'avez pas encore d'abonnement actif. \n\nChoisissez un plan pour commencer à recevoir des collectes régulières !",
  },
  'no_pickup_today': {
    Lang.en: "No pickup scheduled for today. \n\nCheck your contract card for your next scheduled pickup!",
    Lang.fr: "Pas de collecte prévue aujourd'hui. \n\nRegardez votre carte contrat pour votre prochaine collecte !",
  },
  'no_payments': {
    Lang.en: "No payment history yet. \n\nYour first payment will appear here after you subscribe!",
    Lang.fr: "Pas encore d'historique de paiement. \n\nVotre premier paiement apparaîtra ici après votre abonnement !",
  },
  'no_notifications': {
    Lang.en: "You're all caught up! No unread notifications.",
    Lang.fr: "Vous êtes à jour ! Aucune notification non lue.",
  },
  'complaint_flow_category': {
    Lang.en: "What type of issue?\n\n1 Missed collection\n2 Overflowing bin\n3 Illegal dumping\n4 Damaged bin\n5 Other",
    Lang.fr: "Quel type de problème ?\n\n1 Collecte manquée\n2 Benne débordée\n3 Décharge illégale\n4 Benne endommagée\n5 Autre",
  },
  'complaint_describe': {
    Lang.en: "Got it — **{category}** \n\nCan you describe what happened?",
    Lang.fr: "Compris — **{category}** \n\nPouvez-vous décrire ce qui s'est passé ?",
  },
  'complaint_category_select': {
    Lang.en: "Please reply with a number 1-5, or describe the issue in your own words.",
    Lang.fr: "Veuillez répondre par un numéro 1-5, ou décrivez le problème en vos propres mots.",
  },
  'complaint_confirmation': {
    Lang.en: "Here's your complaint:\n\n **Type:** {category}\n **Details:** {description}\n\nSubmit this complaint?",
    Lang.fr: "Voici votre plainte :\n\n **Type :** {category}\n **Détails :** {description}\n\nSoumettre cette plainte ?",
  },
  'complaint_submitted': {
    Lang.en: "Your complaint has been submitted! \n\nYour agency will review it. You'll get a notification when there's an update.",
    Lang.fr: "Votre plainte a été soumise ! \n\nVotre agence l'examinera. Vous recevrez une notification quand il y aura une mise à jour.",
  },
  'pickup_ask_date': {
    Lang.en: "Sure! What date for the pickup?\n\n(e.g. 'tomorrow', 'Friday', 'August 25')",
    Lang.fr: "Bien sûr ! Quelle date pour la collecte ?\n\n(par ex. 'demain', 'vendredi', '25 août')",
  },
  'pickup_date_help': {
    Lang.en: "I didn't catch the date. Could you try again?\n\nExamples: 'tomorrow', 'Friday', 'August 25'",
    Lang.fr: "Je n'ai pas bien saisi la date. Pouvez-vous réessayer ?\n\nExemples : 'demain', 'vendredi', '25 août'",
  },
  'pickup_confirmation': {
    Lang.en: "Here's your pickup request:\n\n **Type:** On-demand pickup\n **Date:** {date}\n **Address:** {address}\n **Cost:** 1,000 XAF (via Mobile Money)\n\nSubmit this request?",
    Lang.fr: "Voici votre demande de collecte :\n\n **Type :** Collecte à la demande\n **Date :** {date}\n **Adresse :** {address}\n **Coût :** 1 000 XAF (via Monnaie mobile)\n\nSoumettre cette demande ?",
  },
  'payment_intro': {
    Lang.en: "To proceed with payment, I'll redirect you to the payment screen.\n\nYou'll receive a USSD prompt to confirm with your PIN.\n\nProceed with payment?",
    Lang.fr: "Pour procéder au paiement, je vous redirigerai vers l'écran de paiement.\n\nVous recevrez une invite USSD pour confirmer avec votre PIN.\n\nProcéder au paiement ?",
  },
  'payment_initiated': {
    Lang.en: "Redirecting to payment... \n\nYou'll receive a USSD prompt on your phone.",
    Lang.fr: "Redirection vers le paiement... \n\nVous recevrez une invite USSD sur votre téléphone.",
  },
  'pickup_submitted': {
    Lang.en: "Pickup request submitted! \n\nYour collector will be notified. You'll get a confirmation once it's scheduled.",
    Lang.fr: "Demande de collecte soumise ! \n\nVotre collecteur sera notifié. Vous recevrez une confirmation une fois planifiée.",
  },
  'complaint_plain_category': {
    Lang.en: "Got it — **{category}** \n\nCan you describe what happened?",
    Lang.fr: "Compris — **{category}** \n\nDécrivez ce qui s'est passé, s'il vous plaît ?",
  },
  'complaint_plain_describe': {
    Lang.en: "Got it — **{category}** \n\nCan you describe what happened?",
    Lang.fr: "Compris — **{category}** \n\nDécrivez ce qui s'est passé, s'il vous plaît ?",
  },
  'pickup_error': {
    Lang.en: "Something went wrong. Let's start fresh! How can I help?",
    Lang.fr: "Quelque chose s'est mal passé. On recommence ! Comment puis-je vous aider ?",
  },
  'login_error': {
    Lang.en: "Please log in first.",
    Lang.fr: "Veuillez d'abord vous connecter.",
  },
  'submit_error': {
    Lang.en: "Sorry, something went wrong. Please try again or contact support.",
    Lang.fr: "Désolé, quelque chose s'est mal passé. Réessayez ou contactez le support.",
  },
  'complaint_submit_fail': {
    Lang.en: "Sorry, I couldn't submit your complaint. Please try again.",
    Lang.fr: "Désolé, je n'ai pas pu soumettre votre plainte. Réessayez.",
  },
  'pickup_submit_fail': {
    Lang.en: "Sorry, I couldn't submit your pickup request. Please try again.",
    Lang.fr: "Désolé, je n'ai pas pu soumettre votre demande. Réessayez.",
  },
  'see_you_soon': {
    Lang.en: "Got it! I'll be here if you need anything else. Have a great day!",
    Lang.fr: "Compris ! Je serai là si vous avez besoin de quoi que ce soit. Bonne journée !",
  },
  'confirm_slip': {
    Lang.en: "Cancelled.",
    Lang.fr: "Annulé.",
  },
};

/// Chat reply from the bot.
class ChatReply {
  const ChatReply({
    required this.text,
    required this.intent,
    this.needsConfirmation = false,
    this.suggestions = const [],
  });

  final String text;
  final String intent;
  final bool needsConfirmation;
  final List<String> suggestions;
}

/// Simple chatbot — FAQ + Firestore + Hugging Face AI fallback.
class ChatbotService {
  ChatbotService({
    FirebaseFirestore? db,
    HuggingFaceChatService? ai,
  })  : _db = db ?? FirebaseFirestore.instance,
        _ai = ai ?? HuggingFaceChatService();

  final FirebaseFirestore _db;
  final HuggingFaceChatService _ai;

  /// Recent turns for AI context: `{role, content}`.
  final List<Map<String, String>> _aiHistory = [];

  // Conversation state for multi-step flows
  String _state = 'idle';
  final Map<String, dynamic> _buffer = {};
  Lang _lang = Lang.en;

  bool get isAiConfigured => _ai.isConfigured;

  /// Process a user message and return a reply.
  Future<ChatReply> process(String message, {UserModel? user}) async {
    final text = message.trim().toLowerCase();
    if (text.isEmpty) {
      return _reply(
        text: _lang == Lang.fr ? "Qu'est-ce qui vous préoccupe ? " : "What's on your mind? ",
        intent: 'unknown',
      );
    }

    // Detect language from input
    _lang = _detectLanguage(text);

    // Handle multi-step flows first
    if (_state != 'idle') return _handleFlow(message, user);

    // Handle confirmations
    if (_isYes(text)) return _reply(text: _t('confirm_yes'), intent: 'yes');
    if (_isNo(text)) {
      _state = 'idle';
      _buffer.clear();
      return _reply(text: _t('confirm_no'), intent: 'cancelled');
    }

    // Detect intent and respond
    return _detectIntent(text, message, user);
  }

  /// Reset conversation state.
  void reset() {
    _state = 'idle';
    _buffer.clear();
    _aiHistory.clear();
  }

  // ── Intent Detection ──────────────────────────────────────────────

  Future<ChatReply> _detectIntent(String text, String originalMessage, UserModel? user) async {
    // Greetings (word-boundary match for short words like 'hi')
    if (RegExp(r'\b(hello|hi|hey|bonjour|salut)\b').hasMatch(text)) {
      return _reply(text: _t('greeting'), intent: 'greeting');
    }
    // French conversational greetings
    if (RegExp(r'\b(comment tu vas|comment ça va|comment ca va|ça va|ca va|tu vas bien|comment allez|comment vas)\b').hasMatch(text)) {
      return _reply(text: _lang == Lang.fr
          ? "Ça va bien, merci !  Je suis WasteBot, votre assistant WastePro.\n\nComment puis-je vous aider aujourd'hui ?"
          : "I'm doing well, thanks!  I'm WasteBot, your WastePro assistant.\n\nHow can I help you today?", intent: 'greeting');
    }
    if (RegExp(r"\b(thanks?|thank you|merci|m'merci|merci beaucoup)\b").hasMatch(text)) {
      return _reply(text: _t('thanks'), intent: 'thanks');
    }

    // ── Write operations FIRST (before FAQ, since they share keywords) ──
    if (_matches(text, ['request pickup', 'request a pickup', 'need pickup', 'schedule pickup', 'book pickup', 'i need an extra', 'extra pickup request'])) {
      return _startPickupFlow(user);
    }
    if (_matches(text, ['file complaint', 'file a complaint', 'report issue', 'submit complaint', 'my bin was not', 'missed pickup'])) {
      return _startComplaintFlow(originalMessage, user);
    }
    if (_matches(text, ['pay my', 'pay for', 'pay now', 'renew'])) {
      return _startPaymentFlow(user);
    }

    // ── Escalation ──
    if (_matches(text, ['human', 'agent', 'representative', 'person', 'speak to', 'talk to', 'manager', 'representant', 'humain'])) {
      return _reply(text: _t('escalate'), intent: 'escalate');
    }

    // ── Backend queries (BEFORE FAQ to avoid keyword conflicts) ──
    if (user != null) {
      if (_matches(text, ['next pickup', 'upcoming', 'when is', 'when are', 'collection date', 'next collection'])) {
        return await _getNextPickup(user.phoneNumber);
      }
      if (_matches(text, ['subscription active', 'plan active', 'subscription status', 'still valid', 'expire'])) {
        return await _getSubscriptionStatus(user.phoneNumber);
      }
      if (_matches(text, ['collected today', 'pickup today', 'bin collected', 'pickup completed', 'was my pickup'])) {
        return await _getPickupStatus(user.phoneNumber);
      }
      if (_matches(text, ['payment history', 'last payment', 'recent payment', 'what did i pay', 'show payment'])) {
        return await _getPaymentHistory(user.phoneNumber);
      }
      if (_matches(text, ['notification', 'unread', "what's new", 'whats new', 'any notification'])) {
        return await _getNotifications(user.phoneNumber);
      }
    }

    // ── FAQ ──
    // Broader "how this app works" detection — also catch phrases like
    // "can you give me a briefing", "explain how this works", "how it functions"
    if (RegExp(r'\b(how|explain|briefing|overview|walk me through|faire un tour|décris|dis-moi|explique)\b.*\b(work|function|app|fonctionn|marche|tour|co|briefing|aperçu)\b|\b(work|function|app|fonctionn|applique|briefing)\b.*\b(how|explain|briefing|overview|walk me through|décris|dis-moi|explique)\b').hasMatch(text)) {
      return _reply(text: _t('how_it_works'), intent: 'how_it_works', suggestions: [_t('missed_pickup'), _t('payment_methods')]);
    }
    if (_matches(text, ['upgrade', 'switch plan', 'change plan', 'changer de plan', 'passer à'])) {
      return _reply(text: _t('upgrade'), intent: 'upgrade');
    }
    if (_matches(text, ['plan', 'subscription', 'pricing', 'price', 'cost', 'tier', 'how much', 'plan', 'abonnement', 'prix', 'combien'])) {
      if (_matches(text, ['difference', 'compare', 'between', 'weekly', 'monthly', 'difference', 'comparer', 'entre', 'hebdomadaire', 'mensuel'])) {
        return _reply(text: _t('plan_difference'), intent: 'plan_difference', suggestions: [_t('upgrade'), _t('payment_methods')]);
      }
      return _reply(text: _t('plans'), intent: 'plans', suggestions: ['Compare plans', 'How do I upgrade?']);
    }
    if (_matches(text, ['support', 'contact', 'phone', 'whatsapp', 'email', 'agency', 'call', 'support', 'contact', 'téléphone', 'agence', 'appel'])) {
      return _reply(text: _t('support'), intent: 'support');
    }
    if (_matches(text, ['report issue', 'issue', 'problem', 'complaint', 'signaler un problème', 'problème', 'plainte'])) {
      return _reply(text: _t('report_issue'), intent: 'report_issue');
    }
    if (_matches(text, ['how does', 'how do', 'how this work', 'how it works', 'how the app', 'explain', 'briefing', 'overview', 'walk me through', 'comment ça marche', 'comment fonctionne', 'comment ceci', 'brève'])) {
      return _reply(text: _t('how_it_works'), intent: 'how_it_works', suggestions: [_t('missed_pickup'), _t('payment_methods')]);
    }
    if (_matches(text, ['validate', 'otp', 'qr', 'verify', 'valider', 'otp', 'code qr'])) {
      return _reply(text: _t('validation'), intent: 'validation');
    }
    if (_matches(text, ['missed', 'not collected', 'didn.t come', 'never came', 'late', 'skip', 'manqu', 'pas collect', 'n\'est pas venu'])) {
      return _reply(text: _t('missed_pickup'), intent: 'missed_pickup', suggestions: [_t('extra_pickup'), _t('report_issue')]);
    }
    if (_matches(text, ['momo', 'orange money', 'mobile money', 'campay', 'momo', 'orange money', 'monnaie mobile', 'campay'])) {
      return _reply(text: _t('payment_methods'), intent: 'payment_methods', suggestions: [_t('extra_pickup'), 'Pay my subscription']);
    }
    if (_matches(text, ['extra pickup', 'on demand', 'one time', 'collecte supplémentaire', 'à la demande', 'une fois'])) {
      return _reply(text: _t('extra_pickup'), intent: 'extra_pickup');
    }
    if (_matches(text, ['update address', 'change address', 'new address', 'update zone', 'modifier adresse', 'nouvelle adresse', 'changer zone'])) {
      return _reply(text: _t('update_address'), intent: 'update_address');
    }
    if (_matches(text, ['password', 'reset password', 'forgot password', 'mot de passe', 'réinitialiser', 'mot de passe oublié'])) {
      return _reply(text: _t('password'), intent: 'password');
    }
    if (_matches(text, ['track', 'where is', 'map', 'gps', 'live', 'suivi', 'où est', 'carte', 'gps', 'en direct'])) {
      return _reply(text: _t('track'), intent: 'track');
    }
    if (_matches(text, ['pay', 'payment', 'momo', 'orange money', 'mobile money', 'campay', 'payer', 'paiement'])) {
      return _reply(text: _t('payment_methods'), intent: 'payment_methods', suggestions: [_t('extra_pickup'), 'Pay my subscription']);
    }

    // Login required for specific backend queries
    if (user == null && _matches(text, ['my pickup', 'my next', 'my subscription', 'my payment', 'my notification', 'next pickup', 'subscription active', 'payment history', 'collected today', 'ma collecte', 'mon abonnement', 'mon paiement', 'mes notifications'])) {
      return _reply(text: _t('need_login'), intent: 'need_login');
    }

    // Open questions → Hugging Face AI (with FAQ fallback).
    return _aiReply(originalMessage);
  }

  /// Ask Hugging Face; on failure fall back to the local unknown FAQ.
  Future<ChatReply> _aiReply(String originalMessage) async {
    if (!_ai.isConfigured) {
      return _reply(
        text: _t('unknown'),
        intent: 'unknown',
        suggestions: ['What plans?', 'Next pickup', 'Payment methods'],
      );
    }

    try {
      final history = _aiHistory.length > 10
          ? _aiHistory.sublist(_aiHistory.length - 10)
          : List<Map<String, String>>.from(_aiHistory);

      final answer = await _ai.chat(
        userMessage: originalMessage,
        french: _lang == Lang.fr,
        history: history,
      );

      _aiHistory.add({'role': 'user', 'content': originalMessage});
      _aiHistory.add({'role': 'assistant', 'content': answer});

      return _reply(
        text: answer,
        intent: 'ai',
        suggestions: _lang == Lang.fr
            ? ['Tarifs', 'Paiement CamPay', 'Prochaine collecte']
            : ['What plans?', 'CamPay payment', 'Next pickup'],
      );
    } on HuggingFaceChatException catch (e) {
      return _reply(
        text: '${e.messageFor(french: _lang == Lang.fr)}\n\n${_t('unknown')}',
        intent: 'unknown',
        suggestions: ['What plans?', 'Next pickup', 'Payment methods'],
      );
    } catch (_) {
      return _reply(
        text: _lang == Lang.fr
            ? 'WasteBot IA est temporairement indisponible.\n\n${_t('unknown')}'
            : 'WasteBot AI is temporarily unavailable.\n\n${_t('unknown')}',
        intent: 'unknown',
        suggestions: ['What plans?', 'Next pickup', 'Payment methods'],
      );
    }
  }

  // ── Multi-step Flows ──────────────────────────────────────────────

  Future<ChatReply> _handleFlow(String message, UserModel? user) async {
    if (_isNo(message.toLowerCase())) {
      _state = 'idle';
      _buffer.clear();
      return _reply(text: _t('confirm_no'), intent: 'cancelled');
    }

    switch (_state) {
      case 'complaint_awaiting_category_select':
        // L'utilisateur n'a pas donné de catégorie au départ : il choisit
        // maintenant (numéro 1-5 ou description libre).
        final category = _extractCategory(message);
        if (category != null) {
          _buffer['category'] = category;
          _state = 'complaint_awaiting_description';
          return _reply(
            text: _t('complaint_describe', params: {'category': category}),
            intent: 'complaint_flow',
          );
        }
        final options = [
          'Missed collection',
          'Overflowing bin',
          'Illegal dumping',
          'Damaged bin',
          'Other',
        ];
        final index = int.tryParse(message.trim());
        if (index != null && index >= 1 && index <= options.length) {
          final chosen = options[index - 1];
          _buffer['category'] = chosen;
          _state = 'complaint_awaiting_description';
          return _reply(
            text: _t('complaint_describe', params: {'category': chosen}),
            intent: 'complaint_flow',
          );
        }
        return _reply(
          text: _t('complaint_category_select'),
          intent: 'complaint_flow',
        );

      case 'complaint_awaiting_description':
        _buffer['description'] = message;
        _state = 'complaint_awaiting_confirmation';
        return _buildComplaintConfirmation();

      case 'pickup_awaiting_date':
        final date = _extractDate(message);
        if (date != null) {
          _buffer['date'] = date;
          _state = 'pickup_awaiting_confirmation';
          return _buildPickupConfirmation(user);
        }
        return _reply(
          text: _t('pickup_date_help'),
          intent: 'pickup_flow',
        );

      case 'complaint_awaiting_confirmation':
      case 'pickup_awaiting_confirmation':
      case 'payment_awaiting_confirmation':
        // « oui » tolérant : yes / ok / sure / go ahead… (et pas seulement
        // le mot exact) pour confirmer un formulaire.
        if (_isAffirmative(message.toLowerCase())) {
          return _submitAction(user);
        }
        return _buildCurrentConfirmation(user);

      default:
        _state = 'idle';
        _buffer.clear();
        return _reply(text: _t('pickup_error'), intent: 'unknown');
    }
  }

  // ── Complaint Flow ────────────────────────────────────────────────

  ChatReply _startComplaintFlow(String message, UserModel? user) {
    final category = _extractCategory(message);
    if (category != null) {
      _buffer['category'] = category;
      _state = 'complaint_awaiting_description';
      return _reply(
        text: _t('complaint_describe', params: {'category': category}),
        intent: 'complaint_flow',
      );
    }
    _state = 'complaint_awaiting_category_select';
    return _reply(
      text: _t('complaint_flow_category'),
      intent: 'complaint_flow',
    );
  }

  ChatReply _buildComplaintConfirmation() {
    final category = _buffer['category'] ?? 'Unknown';
    final description = _buffer['description'] ?? '';
    return _reply(
      text: _t('complaint_confirmation', params: {'category': category, 'description': description}),
      intent: 'complaint_confirm',
      needsConfirmation: true,
    );
  }

  // ── Pickup Request Flow ───────────────────────────────────────────

  ChatReply _startPickupFlow(UserModel? user) {
    _state = 'pickup_awaiting_date';
    return _reply(
      text: _t('pickup_ask_date'),
      intent: 'pickup_flow',
    );
  }

  ChatReply _buildPickupConfirmation(UserModel? user) {
    final date = _buffer['date'] ?? 'Not specified';
    final address = user?.agenceName ?? _t('login_error');
    return _reply(
      text: _t('pickup_confirmation', params: {
        'date': date,
        'address': address,
      }),
      intent: 'pickup_confirm',
      needsConfirmation: true,
    );
  }

  // ── Payment Flow ──────────────────────────────────────────────────

  ChatReply _startPaymentFlow(UserModel? user) {
    _state = 'payment_awaiting_confirmation';
    return _reply(
      text: _t('payment_intro'),
      intent: 'payment_confirm',
      needsConfirmation: true,
    );
  }

  // ── Submit Actions ────────────────────────────────────────────────

  Future<ChatReply> _submitAction(UserModel? user) async {
    final action = _state;
    _state = 'idle';

    if (user == null) {
      _buffer.clear();
      return _reply(text: _t('login_error'), intent: 'error');
    }

    try {
      ChatReply reply;
      switch (action) {
        case 'complaint_awaiting_confirmation':
          reply = await _submitComplaint(user);
          break;
        case 'pickup_awaiting_confirmation':
          reply = await _submitPickupRequest(user);
          break;
        case 'payment_awaiting_confirmation':
          reply = _reply(
            text: _t('payment_initiated'),
            intent: 'payment_initiated',
          );
          break;
        default:
          reply = _reply(text: _t('confirm_yes'), intent: 'done');
      }
      // Le buffer est vidé APRÈS la lecture par les méthodes de
      // soumission (sinon la catégorie/description/date serait perdue).
      _buffer.clear();
      return reply;
    } catch (e) {
      _buffer.clear();
      return _reply(text: _t('submit_error'), intent: 'error');
    }
  }

  ChatReply _buildCurrentConfirmation(UserModel? user) {
    switch (_state) {
      case 'complaint_awaiting_confirmation':
        return _buildComplaintConfirmation();
      case 'pickup_awaiting_confirmation':
        return _buildPickupConfirmation(user);
      default:
        return _reply(text: _lang == Lang.fr ? "Veuillez confirmer ou annuler." : "Please confirm or cancel.", intent: 'confirm');
    }
  }

  Future<ChatReply> _submitComplaint(UserModel user) async {
    final category = _buffer['category'] ?? 'Other issue';
    final description = _buffer['description'] ?? '';
    final now = DateTime.now();
    final id = 'ISS-${now.millisecondsSinceEpoch}';
    final createdAt = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    await _db.collection('issues').doc(id).set({
      'id': id,
      'client_id': user.phoneNumber,
      'client_name': user.fullName,
      'category': category,
      'description': description,
      'status': 'open',
      'created_at': createdAt,
    });

    return _reply(
      text: _t('complaint_submitted'),
      intent: 'complaint_submitted',
      suggestions: [_t('see_you_soon'), _t('support')],
    );
  }

  Future<ChatReply> _submitPickupRequest(UserModel user) async {
    final date = _buffer['date'] ?? '';
    final id = 'PKP-${DateTime.now().millisecondsSinceEpoch}';

    await _db.collection('pickups').doc(id).set({
      'pickup_id': id,
      'client_id': user.phoneNumber,
      'collector_id': user.collecteurId,
      'type': 'extra',
      'status': 'requested',
      'requested_date': date,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await _db.collection('users').doc(user.phoneNumber).update({'needsPickup': true});

    return _reply(
      text: _t('pickup_submitted'),
      intent: 'pickup_submitted',
      suggestions: [_t('see_you_soon'), 'Track collector'],
    );
  }

  // ── Backend Queries ───────────────────────────────────────────────

  Future<ChatReply> _getNextPickup(String phone) async {
    try {
      final doc = await _db.collection('users').doc(phone).get();
      if (!doc.exists) return const ChatReply(text: "No pickup schedule found.", intent: 'no_data');

      final data = doc.data()!;
      final collectionDays = (data['collection_days'] as List<dynamic>?)?.cast<String>() ?? [];
      final pickupTime = data['pickup_time'] as String? ?? '';

      if (collectionDays.isEmpty) {
        return _reply(
          text: _t('no_schedule'),
          intent: 'no_schedule',
          suggestions: ['View plans'],
        );
      }

      // Find next pickup day
      final dayMap = {'Monday': 1, 'Tuesday': 2, 'Wednesday': 3, 'Thursday': 4, 'Friday': 5, 'Saturday': 6, 'Sunday': 7};
      final now = DateTime.now();
      final today = now.weekday;
      final targetDays = collectionDays.map((d) => dayMap[d]).whereType<int>().toList()..sort();

      int daysUntil = -1;
      for (final day in targetDays) {
        if (day > today) { daysUntil = day - today; break; }
      }
      if (daysUntil < 0) daysUntil = 7 - today + targetDays.first;

      final nextDate = now.add(Duration(days: daysUntil));
      // Day names and months (both languages)
      final dayNames = {
        'en': ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'],
        'fr': ['Dimanche', 'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'],
      };
      final monthNames = {
        'en': ['', 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'],
        'fr': ['', 'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'],
      };

      final langKey = _lang == Lang.fr ? 'fr' : 'en';
      final dayName = dayNames[langKey]![nextDate.weekday % 7];
      final monthName = monthNames[langKey]![nextDate.month];
      final formatted = '$dayName, $monthName ${nextDate.day}';

      String countdown;
      if (daysUntil == 0) {
        countdown = _lang == Lang.fr ? 'Aujourd hui !' : 'Today!';
      } else if (daysUntil == 1) {
        countdown = _lang == Lang.fr ? 'Demain !' : 'Tomorrow!';
      } else {
        countdown = _lang == Lang.fr ? 'dans $daysUntil jours' : 'in $daysUntil days';
      }

      return _reply(
        text: _lang == Lang.fr
            ? "Votre prochaine collecte est le $formatted à $pickupTime ! \n\n$countdown"
            : "Your next pickup is $formatted at $pickupTime! \n\nThat's $countdown",
        intent: 'next_pickup',
        suggestions: [_t('track'), _t('extra_pickup')],
      );
    } catch (e) {
      return _reply(text: _t('submit_error'), intent: 'error');
    }
  }

  Future<ChatReply> _getSubscriptionStatus(String phone) async {
    try {
      final doc = await _db.collection('users').doc(phone).get();
      if (!doc.exists) return _reply(text: _t('login_error'), intent: 'no_data');

      final data = doc.data()!;
      final isSubscribed = data['isSubscribed'] as bool? ?? false;
      final plan = data['subscription_plan'] as String? ?? '';

      if (!isSubscribed || plan.isEmpty) {
        return _reply(
          text: _t('no_subscription'),
          intent: 'no_subscription',
          suggestions: ['View plans'],
        );
      }

      final emoji = plan.toLowerCase().contains('premium') ? '' : plan.toLowerCase().contains('standard') ? '' : '';

      return _reply(
        text: _lang == Lang.fr
            ? "Oui, votre abonnement est actif ! \n\n$emoji Plan : $plan\nStatut : Actif\n\nTout est prêt ! "
            : "Yes, your subscription is active! \n\n$emoji Plan: $plan\nStatus: Active\n\nYou're all set! ",
        intent: 'subscription_active',
        suggestions: [_t('track'), 'Change plan'],
      );
    } catch (e) {
      return _reply(text: _t('submit_error'), intent: 'error');
    }
  }

  Future<ChatReply> _getPickupStatus(String phone) async {
    try {
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Check pickups for today
      final pickups = await _db.collection('pickups').where('client_id', isEqualTo: phone).get();
      for (final doc in pickups.docs) {
        final ts = doc.data()['timestamp'];
        if (ts is Timestamp) {
          final d = ts.toDate();
          final pickupStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          if (pickupStr == todayStr) {
            final status = doc.data()['status'] as String? ?? 'scheduled';
            final isDone = status == 'completed' || status == 'paid';
            return _reply(
              text: isDone
                  ? (_lang == Lang.fr ? "Oui ! Votre benne a été collectée aujourd'hui ! " : "Yes! Your bin was collected today! ")
                  : (_lang == Lang.fr
                      ? "Oui, une collecte est prévue aujourd'hui ! \n\nVotre collecteur est en route !"
                      : "Yes, a pickup is scheduled for today! \n\nYour collector is on the way!"),
              intent: 'pickup_today',
              suggestions: [_t('track')],
            );
          }
        }
      }

      // Check if today is a collection day
      final userDoc = await _db.collection('users').doc(phone).get();
      if (userDoc.exists) {
        final collectionDays = (userDoc.data()?['collection_days'] as List<dynamic>?)?.cast<String>() ?? [];
        final dayNames = {
          'en': ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'],
          'fr': ['Dimanche', 'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'],
        };
        final langKey = _lang == Lang.fr ? 'fr' : 'en';
        final todayName = dayNames[langKey]![now.weekday % 7];
        if (collectionDays.contains(todayName)) {
          return _reply(
            text: _lang == Lang.fr
                ? "Oui, une collecte est prévue aujourd'hui ! \n\nVotre collecteur est en route !"
                : "Yes, a pickup is scheduled for today! \n\nYour collector is on the way!",
            intent: 'pickup_today',
            suggestions: [_t('track')],
          );
        }
      }

      return _reply(
        text: _t('no_pickup_today'),
        intent: 'no_pickup_today',
        suggestions: [_t('track'), _t('extra_pickup')],
      );
    } catch (e) {
      return _reply(text: _t('submit_error'), intent: 'error');
    }
  }

  Future<ChatReply> _getPaymentHistory(String phone) async {
    try {
      final snap = await _db.collection('transactions').where('userId', isEqualTo: phone).orderBy('createdAt', descending: true).limit(5).get();

      if (snap.docs.isEmpty) {
        return _reply(
          text: _t('no_payments'),
          intent: 'no_payments',
          suggestions: ['View plans'],
        );
      }

      final header = _lang == Lang.fr ? "Paiements récents : \n\n" : "Recent payments: \n\n";
      final buffer = StringBuffer(header);
      for (final doc in snap.docs) {
        final d = doc.data();
        final amount = d['amount'];
        final desc = d['description'] ?? d['type'] ?? '';
        final status = d['status'] ?? '';
        final icon = status == 'successful' ? '' : status == 'failed' ? '' : '⏳';
        buffer.writeln("$icon $amount XAF — $desc");
      }

      return _reply(text: buffer.toString(), intent: 'payment_history');
    } catch (e) {
      return _reply(text: _t('submit_error'), intent: 'error');
    }
  }

  Future<ChatReply> _getNotifications(String phone) async {
    try {
      final snap = await _db.collection('notifications').where('phone', isEqualTo: phone).get();
      final unread = snap.docs.where((d) => (d.data()['read'] as bool? ?? false) != true).toList();

      if (unread.isEmpty) {
        return _reply(text: _t('no_notifications'), intent: 'no_notifications');
      }

      final countText = _lang == Lang.fr
          ? "${unread.length} notification${unread.length > 1 ? 's' : ''} non lue${unread.length > 1 ? 's' : ''} : \n\n"
          : "${unread.length} unread notification${unread.length > 1 ? 's' : ''}: \n\n";
      final buffer = StringBuffer(countText);
      for (final doc in unread.take(5)) {
        final d = doc.data();
        buffer.writeln("• ${d['title']}: ${d['message']}");
      }

      return _reply(text: buffer.toString(), intent: 'notifications');
    } catch (e) {
      return _reply(text: _t('submit_error'), intent: 'error');
    }
  }

  // ── Language detection & translation ──────────────────────────────

  Lang _detectLanguage(String text) {
    // Check for French indicators first (use word boundaries for short words)
    final frenchPatterns = [
      r'\bmerci\b', r'\bbonjour\b', r'\bsalut\b', r'\bsvp\b', r'\berreur\b',
      r'\bpouvez\b', r'\bveuillez\b', r'\bvoici\b', r'\bcomment\b',
      r'\bquand\b', r'\bcombien\b', r'\bdemain\b', r'\baujourdhui\b',
      r'\bvendredi\b', r'\blundi\b', r'\bmardi\b', r'\bmercredi\b',
      r'\bjeudi\b', r'\bsamedi\b', r'\bdimanche\b', r'\baout\b',
      r'\bjanvier\b', r'\bfevrier\b', r'\bmars\b', r'\bavril\b', r'\ben\b',
      r'\bjuin\b', r'\bjuillet\b', r'\bseptembre\b', r'\boctobre\b',
      r'\bnovembre\b', r'\bdecembre\b', r'\bplainte\b', r'\bsignaler\b',
      r'\badresse\b', r'\bmot de passe\b', r'\babonnement\b',
      r'\bcollecteur\b', r'\bcamion\b', r'\bbenne\b',
    ];
    
    // Also check for common French patterns
    if (text.contains("s'") || text.contains("il vous") || text.contains("plait") ||
        text.contains("probl") || text.contains("erreur") || text.contains("aujour")) {
      return Lang.fr;
    }
    
    for (final pattern in frenchPatterns) {
      if (RegExp(pattern).hasMatch(text)) return Lang.fr;
    }

    // Check for English indicators
    final englishPatterns = [
      r'\bhello\b', r'\bhi\b', r'\bthanks?\b', r'\bplease\b', r'\berror\b',
      r'\bproblem\b', r'\bcan you\b', r'\bcould you\b', r'\bhelp\b',
      r'\bhow\b', r'\bwhen\b', r'\bhow much\b', r'\btomorrow\b', r'\btoday\b',
      r'\bmonday\b', r'\btuesday\b', r'\bwednesday\b', r'\bthursday\b',
      r'\bfriday\b', r'\bsaturday\b', r'\bsunday\b', r'\baugust\b',
      r'\bjanuary\b', r'\bfebruary\b', r'\bmarch\b', r'\bapril\b',
      r'\bmay\b', r'\bjune\b', r'\bjuly\b', r'\bseptember\b',
      r'\boctober\b', r'\bnovember\b', r'\bdecember\b', r'\bpickup\b',
      r'\bcomplaint\b', r'\breport\b', r'\baddress\b', r'\bpassword\b',
      r'\bsubscription\b', r'\bplan\b', r'\bcollector\b', r'\btruck\b',
      r'\bbin\b', r'\bmobile\b',
    ];
    
    for (final pattern in englishPatterns) {
      if (RegExp(pattern).hasMatch(text)) return Lang.en;
    }

    // Default to English
    return Lang.en;
  }

  String _t(String key, {Map<String, String>? params}) {
    final dict = _translations[key];
    if (dict == null) return key;
    final template = dict[_lang] ?? dict[Lang.en] ?? key;
    if (params != null) {
      var result = template;
      for (final entry in params.entries) {
        result = result.replaceAll('{${entry.key}}', entry.value);
      }
      return result;
    }
    return template;
  }

  // ── Helper to build a ChatReply from a translation key ────────────

  ChatReply _reply({required String text, required String intent, bool needsConfirmation = false, List<String> suggestions = const []}) {
    return ChatReply(text: text, intent: intent, needsConfirmation: needsConfirmation, suggestions: suggestions);
  }

  // ── Helpers ───────────────────────────────────────────────────────

  bool _matches(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }

  bool _isYes(String text) {
    return text == 'yes' || text == 'confirm' || text == 'proceed' || text == 'submit' ||
        text == 'ok' || text == 'sure' || text == 'go ahead' || text == 'do it' ||
        text == 'yeah' || text == 'yep' || text == 'yup';
  }

  /// « Oui » tolérant pour les confirmations de formulaire : accepte les
  /// réponses naturelles (« yes please », « ok sure », « go ahead »…).
  ///
  /// Utilisé UNIQUEMENT dans les états de confirmation (pas en haut niveau :
  /// une phrase comme « ok, combien coûte Premium ? » doit rester une
  /// question, pas une confirmation).
  bool _isAffirmative(String text) {
    return RegExp(
      r"\b(yes|yeah|yep|yup|sure|ok|okay|proceed|confirm|go ahead|do it|oui|si|d'accord|vas-y|bien sûr)\b",
    ).hasMatch(text);
  }

  bool _isNo(String text) {
    return text == 'no' || text == 'cancel' || text == 'never mind' || text == 'forget it' ||
        text == 'nah' || text == 'nope' || text == 'stop' || text == 'not now' ||
        text == 'no thanks' || text == 'cancel that' ||
        text == 'non' || text == 'pas maintenant' || text == 'annule';
  }

  String? _extractCategory(String message) {
    final lower = message.toLowerCase();
    if (RegExp(r'miss|not collect|didn.t come|never came|late|skip').hasMatch(lower)) return 'Missed collection';
    if (RegExp(r'overflow|full bin|scattered|debord|debor').hasMatch(lower)) return 'Overflowing bin';
    if (RegExp(r'illegal|dump|unauthorized|decharge|ill').hasMatch(lower)) return 'Illegal dumping';
    if (RegExp(r'damage|broken|crack|endommag').hasMatch(lower)) return 'Damaged bin';
    if (RegExp(r'hazard|danger|toxic|dangereux').hasMatch(lower)) return 'Hazardous waste';
    return null;
  }

  String? _extractDate(String message) {
    final lower = message.toLowerCase();
    final now = DateTime.now();

    // English
    if (lower.contains('tomorrow')) {
      final t = now.add(const Duration(days: 1));
      return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    }
    if (lower.contains('today')) {
      return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    }

    // French
    if (lower.contains('demain')) {
      final t = now.add(const Duration(days: 1));
      return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    }
    if (lower.contains('aujourdhui') || lower.contains('aujourd')) {
      return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    }

    // Day names (both languages)
    final days = {
      'monday': 1, 'lundi': 1,
      'tuesday': 2, 'mardi': 2,
      'wednesday': 3, 'mercredi': 3,
      'thursday': 4, 'jeudi': 4,
      'friday': 5, 'vendredi': 5,
      'saturday': 6, 'samedi': 6,
      'sunday': 7, 'dimanche': 7,
    };
    for (final entry in days.entries) {
      if (lower.contains(entry.key)) {
        var diff = entry.value - now.weekday;
        if (diff <= 0) diff += 7;
        final d = now.add(Duration(days: diff));
        return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }
    }

    // Next week
    if (lower.contains('next week') || lower.contains('la semaine prochaine')) {
      final d = now.add(const Duration(days: 7));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    return null;
  }
}
