/// Carries all collected user data through the sign-up flow.
class SignupData {
  // ── Source account ──────────────────────────────────────────────────────────
  final String? binanceId;
  final String? derivEmail;
  final String? derivName;
  final String? derivAccount;

  // ── Deriv OAuth tokens (from PKCE exchange — stored encrypted in DB) ────────
  final String? derivAccessToken;
  final String? derivRefreshToken;
  final String? derivTokenExpiresAt; // ISO-8601 UTC string

  // ── Payment methods ─────────────────────────────────────────────────────────
  final String? mpesaPhone;
  final String? airtelPhone;
  final String? bankName;
  final String? bankAccountName;
  final String? bankAccountNumber;

  // ── OTP verification token (issued by backend after /otp/verify) ────────────
  final String? verificationToken;

  const SignupData({
    this.binanceId,
    this.derivEmail,
    this.derivName,
    this.derivAccount,
    this.derivAccessToken,
    this.derivRefreshToken,
    this.derivTokenExpiresAt,
    this.mpesaPhone,
    this.airtelPhone,
    this.bankName,
    this.bankAccountName,
    this.bankAccountNumber,
    this.verificationToken,
  });

  /// True when we already know their email (from Deriv OAuth).
  bool get hasKnownEmail => derivEmail != null && derivEmail!.trim().isNotEmpty;

  /// First available phone number (M-Pesa takes priority over Airtel).
  String? get primaryPhone => mpesaPhone ?? airtelPhone;

  SignupData copyWith({
    String? binanceId,
    String? derivEmail,
    String? derivName,
    String? derivAccount,
    String? derivAccessToken,
    String? derivRefreshToken,
    String? derivTokenExpiresAt,
    String? mpesaPhone,
    String? airtelPhone,
    String? bankName,
    String? bankAccountName,
    String? bankAccountNumber,
    String? verificationToken,
  }) {
    return SignupData(
      binanceId: binanceId ?? this.binanceId,
      derivEmail: derivEmail ?? this.derivEmail,
      derivName: derivName ?? this.derivName,
      derivAccount: derivAccount ?? this.derivAccount,
      derivAccessToken: derivAccessToken ?? this.derivAccessToken,
      derivRefreshToken: derivRefreshToken ?? this.derivRefreshToken,
      derivTokenExpiresAt: derivTokenExpiresAt ?? this.derivTokenExpiresAt,
      mpesaPhone: mpesaPhone ?? this.mpesaPhone,
      airtelPhone: airtelPhone ?? this.airtelPhone,
      bankName: bankName ?? this.bankName,
      bankAccountName: bankAccountName ?? this.bankAccountName,
      bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
      verificationToken: verificationToken ?? this.verificationToken,
    );
  }
}
