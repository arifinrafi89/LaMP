import '../../l10n/app_localizations.dart';

/// An error from the server, or from getting to it (plan 2.1).
///
/// The server sends `{"detail": "plain English", "code": "otp_wrong",
/// "retry_after": 30}`. The app shows its own words for each `code`, in
/// English or Bangla, and falls back to `detail`.
class ApiProblem implements Exception {
  const ApiProblem(this.code, {this.detail, this.status, this.retryAfter});

  /// The server's machine code, or `offline` when it couldn't be reached.
  final String code;
  final String? detail;
  final int? status;
  final Duration? retryAfter;

  static const offline = 'offline';

  @override
  String toString() => 'ApiProblem($code, $status, $detail)';
}

/// The words the owner reads for [p].
String problemMessage(L10n l, ApiProblem p) => switch (p.code) {
      'otp_wrong' => l.errOtpWrong,
      'otp_expired' => l.errOtpExpired,
      'otp_too_many' => l.errOtpTooMany,
      'not_banglalink' => l.errNotBanglalink,
      'session_expired' => l.errSessionExpired,
      'plus_required' => l.errPlusRequired,
      'scan_limit_reached' => l.errScanLimitReached,
      'ai_budget_reached' => l.errAiBudgetReached,
      'update_required' => l.errUpdateRequired,
      'rate_limited' => l.errRateLimited,
      'applink_down' => l.errApplinkDown,
      'charge_failed' => l.errChargeFailed,
      'not_found' => l.errNotFound,
      'invalid' => l.errInvalid,
      ApiProblem.offline => l.errOffline,
      _ => (p.detail?.trim().isNotEmpty ?? false) ? p.detail! : l.errUnknown,
    };
