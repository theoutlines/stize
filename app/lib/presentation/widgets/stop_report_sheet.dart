import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/stize_tokens.dart';
import '../../data/api/api_exceptions.dart';
import '../../data/feedback/stop_report_dedup.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../../core/design/stize_icons.dart';

/// The closed list of problems a rider can report at a stop, in screen order.
/// The keys are the backend's categories (`STOP_REPORT_CATEGORIES`).
const kStopReportCategories = [
  'not_here',
  'wrong_type',
  'wrong_lines',
  'arrivals_wrong',
  'wrong_name',
  'other',
];

String stopReportLabel(AppLocalizations l10n, String category) =>
    switch (category) {
      'not_here' => l10n.stopReportNotHere,
      'wrong_type' => l10n.stopReportWrongType,
      'wrong_lines' => l10n.stopReportWrongLines,
      'arrivals_wrong' => l10n.stopReportArrivalsWrong,
      'wrong_name' => l10n.stopReportWrongName,
      _ => l10n.stopReportOther,
    };

/// The quiet entry at the end of a stop board: "Something wrong with this
/// stop?". Opens [showStopReportSheet].
class StopReportEntry extends StatelessWidget {
  const StopReportEntry({
    super.key,
    required this.stopId,
    required this.stopName,
  });

  final String stopId;
  final String stopName;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      // The system's tertiary button: 40px, fill-06, radius-md, label 16/500,
      // 16px icon on the text's centre line.
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: c.ink80,
          backgroundColor: c.fill06,
          minimumSize: const Size(0, StizeSize.buttonSmallH),
          padding: const EdgeInsets.symmetric(horizontal: StizeSpace.space4),
          textStyle: StizeType.label,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(StizeRadius.radiusMd),
            ),
          ),
        ),
        onPressed: () =>
            showStopReportSheet(context, stopId: stopId, stopName: stopName),
        icon: const Icon(StizeIcons.flag, size: 16),
        label: Text(l10n.stopReportEntry),
      ),
    );
  }
}

Future<void> showStopReportSheet(
  BuildContext context, {
  required String stopId,
  required String stopName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (ctx) => PointerInterceptor(
      child: ((_) => StopReportSheet(stopId: stopId, stopName: stopName))(ctx),
    ),
  );
}

enum _Stage { form, sending, sent, already }

class StopReportSheet extends ConsumerStatefulWidget {
  const StopReportSheet({
    super.key,
    required this.stopId,
    required this.stopName,
    this.dedup,
  });

  final String stopId;
  final String stopName;
  final StopReportDedup? dedup;

  @override
  ConsumerState<StopReportSheet> createState() => _StopReportSheetState();
}

class _StopReportSheetState extends ConsumerState<StopReportSheet> {
  late final StopReportDedup _dedup = widget.dedup ?? StopReportDedup();
  final _comment = TextEditingController();
  String? _category;
  _Stage _stage = _Stage.form;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  bool get _canSend =>
      _category != null &&
      _stage == _Stage.form &&
      (_category != 'other' || _comment.text.trim().isNotEmpty);

  Future<void> _send() async {
    final category = _category!;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    if (await _dedup.sentRecently(widget.stopId, category)) {
      if (mounted) setState(() => _stage = _Stage.already);
      return;
    }
    setState(() {
      _stage = _Stage.sending;
      _error = null;
    });
    try {
      final version = await ref.read(appVersionProvider.future);
      await ref
          .read(feedbackRepositoryProvider)
          .submitStopReport(
            stopId: widget.stopId,
            category: category,
            comment: category == 'other' ? _comment.text : null,
            appVersion: version,
            platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
            locale: locale,
          );
      await _dedup.markSent(widget.stopId, category);
      if (mounted) setState(() => _stage = _Stage.sent);
    } on RateLimitedException {
      if (mounted) {
        setState(() {
          _stage = _Stage.form;
          _error = l10n.stopReportTooFast;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _stage = _Stage.form;
          _error = l10n.stopReportFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    final l10n = AppLocalizations.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          StizeSpace.space4,
          0,
          StizeSpace.space4,
          StizeSpace.space4 + bottom,
        ),
        child: switch (_stage) {
          _Stage.sent || _Stage.already => _done(c, l10n),
          _ => _form(c, l10n),
        },
      ),
    );
  }

  Widget _form(StizeColors c, AppLocalizations l10n) {
    final sending = _stage == _Stage.sending;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.stopReportTitle,
            style: StizeType.heroTitle.copyWith(color: c.ink),
          ),
          const SizedBox(height: 4),
          Text(
            widget.stopName,
            style: StizeType.label.copyWith(color: c.ink60),
          ),
          const SizedBox(height: StizeSpace.space3),
          RadioGroup<String>(
            groupValue: _category,
            onChanged: (v) => setState(() {
              _category = v;
              _error = null;
            }),
            child: Column(
              children: [
                for (final cat in kStopReportCategories)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: _category == cat ? c.fill08 : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        StizeRadius.radiusControl,
                      ),
                      child: RadioListTile<String>(
                        value: cat,
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: StizeSpace.space1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            StizeRadius.radiusControl,
                          ),
                        ),
                        title: Text(
                          stopReportLabel(l10n, cat),
                          style: StizeType.body.copyWith(color: c.ink),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_category == 'other') ...[
            const SizedBox(height: StizeSpace.space2),
            Text(
              l10n.stopReportOtherLabel,
              style: StizeType.caption.copyWith(color: c.ink60),
            ),
            const SizedBox(height: StizeSpace.space1),
            TextField(
              controller: _comment,
              autofocus: true,
              maxLength: 500,
              minLines: 3,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              style: StizeType.body.copyWith(color: c.ink),
              decoration: InputDecoration(
                hintText: l10n.stopReportOtherHint,
                filled: true,
                fillColor: c.fill08,
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    StizeRadius.radiusControl,
                  ),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
          const SizedBox(height: StizeSpace.space4),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: StizeSpace.space2),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: StizeType.caption.copyWith(color: c.ink),
              ),
            ),
          Text(
            l10n.stopReportPrivacy,
            textAlign: TextAlign.center,
            style: StizeType.caption.copyWith(color: c.ink50),
          ),
          const SizedBox(height: StizeSpace.space2),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.ink,
                foregroundColor: c.onInk,
                disabledBackgroundColor: c.fill08,
                disabledForegroundColor: c.ink50,
                shape: const StadiumBorder(),
                textStyle: StizeType.control,
              ),
              onPressed: _canSend ? _send : null,
              child: sending
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.onInk,
                      ),
                    )
                  : Text(l10n.stopReportSend),
            ),
          ),
        ],
      ),
    );
  }

  Widget _done(StizeColors c, AppLocalizations l10n) {
    final already = _stage == _Stage.already;
    final what = stopReportLabel(l10n, _category ?? 'other');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: StizeSpace.space4),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: already ? c.fill08 : c.accent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            already ? StizeIcons.flag : StizeIcons.check,
            size: 32,
            color: already ? c.ink : c.onAccent,
          ),
        ),
        const SizedBox(height: StizeSpace.space3),
        Text(
          already ? l10n.stopReportAlreadyTitle : l10n.stopReportSentTitle,
          textAlign: TextAlign.center,
          style: StizeType.heroTitle.copyWith(color: c.ink),
        ),
        const SizedBox(height: StizeSpace.space2),
        Text(
          already
              ? l10n.stopReportAlreadyBody(what)
              : l10n.stopReportSentBody(what, widget.stopName),
          textAlign: TextAlign.center,
          style: StizeType.label.copyWith(color: c.ink60),
        ),
        const SizedBox(height: StizeSpace.space6),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.fill08,
              foregroundColor: c.ink,
              shape: const StadiumBorder(),
              textStyle: StizeType.control,
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.stopReportBack),
          ),
        ),
      ],
    );
  }
}
