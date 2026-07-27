import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/debug/logger.dart';
import '../../core/services/calendar_feed_links.dart';
import '../../core/services/environment_service.dart';
import '../../data/repositories/team_repository.dart';
import '../../domain/entities/team_member.dart';

/// Opens the personal-calendar subscribe dialog for [member].
///
/// [isAdminView] additionally reveals the "send over WhatsApp" and
/// "reset link" actions, which only make sense when an admin is managing
/// another member's feed rather than the member managing their own.
Future<void> showCalendarFeedDialog(
  BuildContext context, {
  required TeamMember member,
  required bool isAdminView,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CalendarFeedDialog(
      member: member,
      isAdminView: isAdminView,
    ),
  );
}

enum _FeedLoadState { loading, ready, error }

class _CalendarFeedDialog extends StatefulWidget {
  final TeamMember member;
  final bool isAdminView;

  const _CalendarFeedDialog({
    required this.member,
    required this.isAdminView,
  });

  @override
  State<_CalendarFeedDialog> createState() => _CalendarFeedDialogState();
}

class _CalendarFeedDialogState extends State<_CalendarFeedDialog> {
  // Deliberately vague: _invokeMutation flattens every backend failure
  // (network, validation, the server-side self-or-admin permission check)
  // into a single message-only exception, so the UI cannot know which one
  // happened and must not guess.
  static const String _genericErrorMessage = 'משהו השתבש. נסה/י שוב.';

  _FeedLoadState _loadState = _FeedLoadState.loading;
  String? _token;
  bool _isRotating = false;

  bool get _isTestMode => EnvironmentService.instance.isTestMode;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    setState(() => _loadState = _FeedLoadState.loading);
    try {
      final token = await context
          .read<TeamRepository>()
          .database
          .ensureCalendarFeedToken(widget.member.id);
      if (!mounted) return;
      setState(() {
        _token = token;
        _loadState = _FeedLoadState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadState = _FeedLoadState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(
          widget.isAdminView
              ? 'יומן אישי – ${widget.member.name}'
              : 'היומן האישי שלי',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(child: _buildContent()),
        ),
        actions: [
          TextButton(
            onPressed: _isRotating
                ? null
                : () {
                    Logger.action('tap:close:calendarFeedDialog');
                    Navigator.of(context).pop();
                  },
            child: const Text('סגירה'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_loadState) {
      case _FeedLoadState.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('מכינים קישור אישי...'),
            ],
          ),
        );
      case _FeedLoadState.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red[400], size: 40),
              const SizedBox(height: 12),
              const Text(_genericErrorMessage, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Logger.action('tap:retry:calendarFeedToken');
                  _loadToken();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('נסה שוב'),
              ),
            ],
          ),
        );
      case _FeedLoadState.ready:
        return _buildReadyContent();
    }
  }

  Widget _buildReadyContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _isRotating ? null : _addToCalendar,
                icon: const Icon(Icons.calendar_month),
                label: const Text('הוסף ליומן'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isRotating ? null : _copyLink,
                icon: const Icon(Icons.copy),
                label: const Text('העתק קישור'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
          title: const Text(
            'איך מוסיפים?',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          onExpansionChanged: (expanded) {
            if (expanded) {
              Logger.action('open:howToInstructions:calendarFeedDialog');
            }
          },
          children: [
            _buildInstructionSection(
              'באייפון או ב-Mac (Apple Calendar)',
              'לוחצים על הכפתור "הוסף ליומן" למעלה ומאשרים את ההרשמה. '
                  'Apple Calendar בודק עדכונים בערך כל 5 דקות, כך ששינויים '
                  'במשמרות נכנסים מהר.',
            ),
            const SizedBox(height: 10),
            _buildInstructionSection(
              'ב-Google Calendar (אנדרואיד או דפדפן)',
              'מעתיקים את הקישור עם הכפתור "העתק קישור", נכנסים ל-Google '
                  'Calendar באתר, ליד "יומנים אחרים" לוחצים על + ואז על '
                  '"הוספה לפי כתובת URL", ומדביקים את הקישור שהועתק.\n\n'
                  'חשוב לדעת: Google Calendar מתעדכן פעם ביום בערך, ואין '
                  'דרך לזרז את זה. אחרי שינוי במשמרת ייתכן שיעבור יום עד '
                  'שהוא יופיע ביומן.',
            ),
            const SizedBox(height: 10),
            _buildInstructionSection(
              'רוצים עדכון מהיר יותר באנדרואיד?',
              'אפשר להתקין את האפליקציה החינמית ICSx⁵ ולהירשם לקישור '
                  'דרכה במקום ב-Google Calendar הרגיל — היא בודקת עדכונים '
                  'הרבה יותר מהר.',
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildWarningBanner(),
        if (widget.isAdminView) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isRotating ? null : _sendWhatsApp,
            icon: const Icon(Icons.chat),
            label: const Text('שלח בוואטסאפ'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green[800],
              side: BorderSide(color: Colors.green.shade300),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _isRotating ? null : _confirmAndRotate,
            icon: _isRotating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restart_alt),
            label: const Text('אפס קישור'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ],
    );
  }

  Widget _buildInstructionSection(String heading, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          style: TextStyle(fontSize: 13, color: Colors.grey[800]),
        ),
      ],
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, color: Colors.orange[700], size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.isAdminView
                  ? 'הקישור הזה אישי לחבר/ת הצוות ומעניק גישה למשמרות '
                      'שלו/שלה בלבד. יש לשלוח אותו רק אליו/אליה, ולא '
                      'להעביר אותו הלאה.'
                  : 'הקישור הזה אישי ומעניק גישה למשמרות שלך בלבד. אין '
                      'לשתף אותו עם אף אחד.',
              style: TextStyle(color: Colors.orange[900], fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {required Color backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text(message),
          ),
          backgroundColor: backgroundColor,
        ),
      );
  }

  Future<void> _addToCalendar() async {
    final token = _token;
    if (token == null) return;
    Logger.action('tap:addToCalendar:calendarFeedDialog', {
      'memberId': widget.member.id,
    });

    // Launch webcal: FIRST, before any other await. url_launcher_web routes
    // a custom scheme like webcal: through window.open, which browsers gate
    // on transient user activation from the tap that triggered this
    // handler — and iOS Safari (the platform this one-tap button exists
    // for) commonly refuses that window.open if an async hop, such as the
    // clipboard write below, runs first and the activation has expired by
    // the time we get to it.
    //
    // On Flutter Web — the only platform this app ships to —
    // url_launcher_web's openNewWindow() unconditionally returns true for
    // any non-disallowed scheme (window.open cannot report whether a
    // webcal: handler actually caught it), so a launchUrl() return value
    // can never tell us whether the calendar app really opened. Copy the
    // https link afterwards so the member always has a working fallback
    // regardless of what actually happened.
    final webcalUrl = CalendarFeedLinks.webcalUrl(token, isTestMode: _isTestMode);
    try {
      await launchUrl(Uri.parse(webcalUrl));
    } catch (_) {
      // A genuine exception is still possible (e.g. platform channel
      // failure); the clipboard copy below still gives the member a
      // working fallback either way.
    }
    if (!mounted) return;

    await Clipboard.setData(
      ClipboardData(
        text: CalendarFeedLinks.httpsUrl(token, isTestMode: _isTestMode),
      ),
    );
    if (!mounted) return;

    _showSnackBar(
      'אמור להיפתח יישום היומן. ליתר ביטחון, הקישור הועתק גם ללוח.',
      backgroundColor: Colors.green,
    );
  }

  Future<void> _copyLink() async {
    final token = _token;
    if (token == null) return;
    Logger.action('tap:copyLink:calendarFeedDialog', {
      'memberId': widget.member.id,
    });

    await Clipboard.setData(
      ClipboardData(
        text: CalendarFeedLinks.httpsUrl(token, isTestMode: _isTestMode),
      ),
    );
    if (!mounted) return;
    _showSnackBar('הקישור הועתק ללוח', backgroundColor: Colors.green);
  }

  Future<void> _sendWhatsApp() async {
    final token = _token;
    if (token == null) return;
    Logger.action('tap:sendWhatsApp:calendarFeedDialog', {
      'memberId': widget.member.id,
    });

    final url = CalendarFeedLinks.whatsappShareUrl(
      token: token,
      phoneNumber: widget.member.phoneNumber,
      isTestMode: _isTestMode,
    );
    // As with the webcal launch above, launchUrl's return value is not a
    // reliable success signal on web — and here the URL is always
    // https://wa.me/..., a scheme openNewWindow() always resolves to true
    // for regardless, so there is no meaningful "did it fail" branch left
    // to act on.
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Nothing actionable to do differently for a thrown exception either.
    }
  }

  Future<void> _confirmAndRotate() async {
    Logger.action('open:rotateConfirm:calendarFeedDialog', {
      'memberId': widget.member.id,
    });

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('איפוס קישור היומן', textAlign: TextAlign.center),
          content: Text(
            'הקישור הנוכחי של ${widget.member.name} יפסיק לעבוד לצמיתות, '
            'וכל מנוי קיים אליו יפסיק להתעדכן. לאחר האיפוס יהיה צריך '
            'לשתף קישור חדש. להמשיך?',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () {
                Logger.action('tap:cancel:rotateCalendarFeedToken');
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () {
                Logger.action('tap:confirmRotate:calendarFeedToken');
                Navigator.of(dialogContext).pop(true);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('אפס קישור'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isRotating = true);
    try {
      final newToken = await context
          .read<TeamRepository>()
          .database
          .rotateCalendarFeedToken(widget.member.id);
      if (!mounted) return;
      setState(() {
        _token = newToken;
        _isRotating = false;
      });
      _showSnackBar(
        'הקישור אופס בהצלחה. יש לשתף את הקישור החדש.',
        backgroundColor: Colors.green,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isRotating = false);
      _showSnackBar(_genericErrorMessage, backgroundColor: Colors.red);
    }
  }
}
