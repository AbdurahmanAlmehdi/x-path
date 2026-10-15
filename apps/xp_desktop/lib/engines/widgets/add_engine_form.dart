import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/engines/bloc/add_engine_bloc.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// Adds a remote engine by name, URL and token. Once the engine passed the
/// checks the app switches to it.
class AddEngineForm extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        AddEngineBloc(engines: context.read<AppServices>().engines),
    child: const AddEngineFormView(),
  );
}

class AddEngineFormView extends StatefulWidget {
  const new({super.key});

  @override
  State<AddEngineFormView> createState() => _AddEngineFormViewState();
}

class _AddEngineFormViewState extends State<AddEngineFormView> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _token = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  String _failure(AppLocalizations l10n, EngineCheckFailure failure) =>
      switch (failure) {
        EngineCheckFailure.invalidUrl => l10n.engineCheckInvalidUrl,
        EngineCheckFailure.unreachable => l10n.engineCheckUnreachable,
        EngineCheckFailure.notAnEngine => l10n.engineCheckNotAnEngine,
        EngineCheckFailure.apiMismatch => l10n.engineCheckApiMismatch,
        EngineCheckFailure.tokenRejected => l10n.engineCheckTokenRejected,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final device = context.read<AppServices>().deviceName;
    return BlocConsumer<AddEngineBloc, AddEngineState>(
      listenWhen: (previous, current) =>
          current.status == AddEngineStatus.added,
      listener: (context, state) {
        _name.clear();
        _url.clear();
        _token.clear();
        context.read<EngineConnectionBloc>().add(const EnginesChanged());
      },
      builder: (context, state) {
        final checking = state.status == AddEngineStatus.checking;
        return XpPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.enginesAddTitle,
                style: context.xpType.title.copyWith(
                  color: context.xpColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.enginesAddHelp(device),
                style: context.xpType.body.copyWith(
                  color: context.xpColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: XpTextField(
                      key: const Key('addEngine.name'),
                      label: l10n.fieldName,
                      hint: l10n.fieldNameHint,
                      controller: _name,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: XpTextField(
                      key: const Key('addEngine.url'),
                      label: l10n.fieldUrl,
                      hint: l10n.fieldUrlHint,
                      controller: _url,
                      code: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              XpTextField(
                key: const Key('addEngine.token'),
                label: l10n.fieldToken,
                controller: _token,
                obscure: true,
                code: true,
              ),
              if (state.failure case final failure?) ...[
                const SizedBox(height: 12),
                XpMessage(XpStatus.engineUnreachable, _failure(l10n, failure)),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: ListenableBuilder(
                  listenable: Listenable.merge([_url, _token]),
                  builder: (context, _) => XpButton(
                    label: checking
                        ? l10n.enginesChecking
                        : l10n.enginesAddButton,
                    kind: XpButtonKind.primary,
                    busy: checking,
                    onPressed:
                        _url.text.trim().isEmpty || _token.text.trim().isEmpty
                        ? null
                        : () => context.read<AddEngineBloc>().add(
                            AddEngineSubmitted(
                              name: _name.text,
                              url: _url.text,
                              token: _token.text,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
