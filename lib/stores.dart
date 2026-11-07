import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Proveedor de tiempo inyectable para pruebas unitarias.
typedef Clock = DateTime Function();

String _generateSecureRandomString([int length = 32]) {
  final random = Random.secure();
  final values = Uint8List(length);
  for (var i = 0; i < length; i++) {
    values[i] = random.nextInt(256);
  }
  return base64UrlEncode(values).replaceAll('=', '');
}

enum TicketStatus { pending, complete, error }

class LoginTicket {
  final String ticketId;
  final String pollSecret;
  final DateTime createdAt;
  TicketStatus status;
  String? appToken;
  String? errorMessage;
  bool isUsed;
  DateTime? completedAt;

  LoginTicket({
    required this.ticketId,
    required this.pollSecret,
    required this.createdAt,
    this.status = TicketStatus.pending,
    this.isUsed = false,
  });
}

class TransactionData {
  final String codeVerifier;
  final String state;
  final String nonce;
  final String ticketId;
  final DateTime createdAt;

  TransactionData({
    required this.codeVerifier,
    required this.state,
    required this.nonce,
    required this.ticketId,
    required this.createdAt,
  });
}

class AppSession {
  final String appToken;
  final Map<String, dynamic> profile;
  final String sub;
  final String acr;
  final int authTime;
  final DateTime expiresAt;

  AppSession({
    required this.appToken,
    required this.profile,
    required this.sub,
    required this.acr,
    required this.authTime,
    required this.expiresAt,
  });
}

class InMemoryStores {
  final Clock _clock;
  final Map<String, LoginTicket> _tickets = {};
  final Map<String, TransactionData> _transactions = {};
  final Map<String, AppSession> _sessions = {};

  final int maxPendingTickets;
  final int maxSessions;
  final Duration ticketTtl;
  final Duration sessionTtl;

  InMemoryStores({
    Clock? clock,
    this.maxPendingTickets = 100,
    this.maxSessions = 10000,
    this.ticketTtl = const Duration(seconds: 300),
    this.sessionTtl = const Duration(seconds: 1800),
  }) : _clock = clock ?? DateTime.now;

  void purgeExpired() {
    final now = _clock();
    _tickets.removeWhere((_, t) {
      if (t.status == TicketStatus.complete || t.status == TicketStatus.error) {
        final graceTime = t.completedAt?.add(const Duration(seconds: 60));
        return graceTime != null && now.isAfter(graceTime);
      }
      return now.isAfter(t.createdAt.add(ticketTtl));
    });

    _transactions.removeWhere((_, tx) => now.isAfter(tx.createdAt.add(const Duration(seconds: 600))));
    _sessions.removeWhere((_, s) => now.isAfter(s.expiresAt));
  }

  LoginTicket? createTicket() {
    purgeExpired();
    final pendingCount = _tickets.values.where((t) => t.status == TicketStatus.pending).length;
    if (pendingCount >= maxPendingTickets) return null;

    final ticketId = _generateSecureRandomString(32);
    final pollSecret = _generateSecureRandomString(32);
    final ticket = LoginTicket(
      ticketId: ticketId,
      pollSecret: pollSecret,
      createdAt: _clock(),
    );

    _tickets[ticketId] = ticket;
    return ticket;
  }

  LoginTicket? getTicket(String ticketId) => _tickets[ticketId];

  void createTransaction(String cookieId, TransactionData data) {
    purgeExpired();
    _transactions[cookieId] = data;
  }

  TransactionData? consumeTransaction(String cookieId) {
    return _transactions.remove(cookieId);
  }

  void saveSession(AppSession session) {
    purgeExpired();
    _sessions[session.appToken] = session;
  }

  AppSession? getSession(String appToken) {
    final session = _sessions[appToken];
    if (session == null) return null;
    if (_clock().isAfter(session.expiresAt)) {
      _sessions.remove(appToken);
      return null;
    }
    return session;
  }

  void removeSession(String appToken) {
    _sessions.remove(appToken);
  }
}
