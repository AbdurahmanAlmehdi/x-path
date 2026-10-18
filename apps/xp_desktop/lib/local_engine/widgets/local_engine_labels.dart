import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/local_engine/bloc/local_engine_bloc.dart';

/// Why the engine on this Mac did not start, in the Run Sheet voice; `null`
/// when the last start did not fail.
String? localEngineFailureText(AppLocalizations l10n, LocalEngineState state) =>
    switch (state.failure) {
      null => null,
      LocalEngineFailure.noEngine => l10n.localEngineNoEngine,
      LocalEngineFailure.needsApproval => l10n.localEngineNeedsApproval,
      LocalEngineFailure.unsupported => l10n.localEngineUnsupported,
      LocalEngineFailure.refused => l10n.localEngineRefused(
        state.message ?? '',
      ),
      LocalEngineFailure.timedOut => l10n.localEngineTimedOut,
      LocalEngineFailure.token => l10n.localEngineToken(state.message ?? ''),
    };
