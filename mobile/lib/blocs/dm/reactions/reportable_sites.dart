// ABOUTME: Stable site identifiers for ConversationReactionsCubit
// ABOUTME: addError callsites. Reactions are network/IO class per the
// ABOUTME: error-handling matrix and are NOT Reportable — these
// ABOUTME: identifiers exist for log triage, not Crashlytics grouping.

/// Stable site identifiers for the `addError` callsites in
/// `ConversationReactionsCubit`. Not wrapped in `Reportable` because
/// reaction publish failures are network/IO class per the matrix.
abstract class ConversationReactionsReportableSites {
  /// `_onToggled`: publish call threw inside the cubit handler.
  static const String publishThrew = '_onToggled.publishThrew';

  /// `_onRetryRequested`: replay publish call threw.
  static const String retryThrew = '_onRetryRequested.retryThrew';
}
