import 'package:flutter/material.dart';

/// A public, unauthenticated privacy policy screen.
/// Accessible at /privacy-policy (production) or /test/privacy-policy (test environment).
/// No authentication required - intended for direct linking from external sources
/// (e.g., app store listings, footer links).
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String _lastUpdated = '14 במאי 2026';
  static const String _contactEmail = 'omer.bengal7@gmail.com';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('מדיניות פרטיות'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 32),
                    _buildSection(
                      context,
                      title: 'מבוא',
                      body:
                          'ברוכים הבאים לשבצק (להלן: "האפליקציה"). אנו מחויבים להגן על פרטיות המשתמשים שלנו. מדיניות פרטיות זו מסבירה אילו נתונים אנו אוספים, כיצד אנו משתמשים בהם, וכיצד אנו מגנים עליהם.\n\nהשימוש באפליקציה מהווה הסכמה לתנאי מדיניות פרטיות זו. אם אינכם מסכימים לתנאים אלה, אנא הימנעו משימוש באפליקציה.',
                    ),
                    _buildSection(
                      context,
                      title: 'איזה מידע אנו אוספים',
                      body:
                          'האפליקציה אוספת ושומרת את סוגי המידע הבאים:',
                      bullets: const [
                        'פרטי חברי צוות: שמות מלאים, תפקידים, יכולות ושיוך ארגוני.',
                        'אירועים: שמות, תאריכים, שעות, מיקומים ופרטים נלווים.',
                        'שיבוצים: שיוך חברי צוות לאירועים ולתפקידים ספציפיים.',
                        'מגבלות וזמינות: תאריכים בהם חברי צוות אינם זמינים או זמינים, כולל הערות חופשיות.',
                        'מזהה משתמש ייחודי: לצורכי זיהוי והתחברות לאפליקציה.',
                        'מידע טכני בסיסי: סוג דפדפן, מערכת הפעלה ונתונים טכניים הנחוצים לתפעול תקין.',
                      ],
                    ),
                    _buildSection(
                      context,
                      title: 'כיצד אנו משתמשים במידע',
                      body: 'המידע הנאסף משמש למטרות הבאות:',
                      bullets: const [
                        'ניהול ושיבוץ חברי צוות לאירועים.',
                        'מתן גישה למשתמשים לצפייה בשיבוצים האישיים שלהם.',
                        'מתן כלים למנהלים לניהול הצוות, האירועים והשיבוצים.',
                        'סנכרון אירועים עם Google Calendar (כאשר הופעל על ידי המנהל).',
                        'שיפור חוויית המשתמש ותפקוד האפליקציה.',
                        'תיעוד פעולות לצורכי ביקורת ושחזור היסטורי.',
                      ],
                    ),
                    _buildSection(
                      context,
                      title: 'שיתוף מידע עם צדדים שלישיים',
                      body:
                          'איננו מוכרים, משכירים או חולקים את המידע האישי שלכם עם צדדים שלישיים, למעט במקרים הבאים:',
                      bullets: const [
                        'ספקי תשתית: אנו משתמשים בשירותי Google Firebase לאחסון נתונים, אימות ותפעול.',
                        'שירותים מובנים: סנכרון אירועים עם Google Calendar מתבצע רק לפי הגדרות המנהל.',
                        'דרישות חוק: במקרה של דרישה חוקית מחייבת או צו בית משפט.',
                        'הגנה על זכויות: לצורך הגנה על זכויותינו או זכויות המשתמשים שלנו.',
                      ],
                    ),
                    _buildSection(
                      context,
                      title: 'אחסון ואבטחת מידע',
                      body:
                          'הנתונים מאוחסנים בצורה מאובטחת בתשתית הענן של Google Firebase, הכפופה לסטנדרטים גבוהים של אבטחת מידע. אנו נוקטים באמצעי אבטחה סבירים, טכניים וארגוניים, על מנת להגן על המידע מפני גישה לא מורשית, אובדן, שינוי, חשיפה או הרס.\n\nעם זאת, חשוב לציין כי אף שיטת העברה או אחסון אינה מאובטחת ב-100%, ואנו לא יכולים להבטיח אבטחה מוחלטת.',
                    ),
                    _buildSection(
                      context,
                      title: 'אחסון מקומי בדפדפן',
                      body:
                          'האפליקציה משתמשת באחסון מקומי בדפדפן (localStorage) למטרות הבאות:',
                      bullets: const [
                        'שמירת ההתחברות שלכם בין סשנים.',
                        'שמירת העדפות תצוגה והגדרות מסננים.',
                        'שיפור ביצועי האפליקציה.',
                      ],
                      footer:
                          'ניתן לנקות את האחסון המקומי בכל עת דרך הגדרות הדפדפן. שימו לב כי ניקוי האחסון יחייב התחברות מחדש.',
                    ),
                    _buildSection(
                      context,
                      title: 'זכויות המשתמש',
                      body: 'לכל משתמש עומדות הזכויות הבאות:',
                      bullets: const [
                        'הזכות לעיין במידע האישי שנאסף עליו.',
                        'הזכות לבקש תיקון של מידע שגוי או לא מדויק.',
                        'הזכות לבקש מחיקת המידע (כפוף למגבלות חוקיות ותפעוליות).',
                        'הזכות לבטל הסכמה לאיסוף מידע (עלול להגביל את השימוש באפליקציה).',
                        'הזכות להגיש תלונה לרשות להגנת הפרטיות במידת הצורך.',
                      ],
                      footer:
                          'להפעלת זכויות אלה, אנא פנו אלינו בכתובת המופיעה בסיום מסמך זה.',
                    ),
                    _buildSection(
                      context,
                      title: 'פרטיות ילדים',
                      body:
                          'האפליקציה אינה מיועדת לשימוש על ידי ילדים מתחת לגיל 13. איננו אוספים ביודעין מידע אישי מילדים מתחת לגיל זה. אם נודע לכם כי ילד מסר לנו מידע אישי, אנא צרו עמנו קשר ונפעל למחיקתו.',
                    ),
                    _buildSection(
                      context,
                      title: 'הגבלת אחריות',
                      body:
                          'האפליקציה מסופקת "כפי שהיא" (AS IS) ללא אחריות מכל סוג שהוא. השימוש באפליקציה הוא באחריות המשתמש בלבד. אנו לא נישא באחריות לכל נזק ישיר או עקיף הנובע מהשימוש או מאי השימוש באפליקציה.',
                    ),
                    _buildSection(
                      context,
                      title: 'שינויים במדיניות הפרטיות',
                      body:
                          'אנו שומרים לעצמנו את הזכות לעדכן את מדיניות פרטיות זו מעת לעת, בהתאם לשינויים בחוק, באפליקציה או בנהלי העבודה שלנו. עדכונים יפורסמו בעמוד זה עם תאריך עדכון מעודכן. מומלץ לעיין במדיניות מדי פעם.',
                    ),
                    _buildSection(
                      context,
                      title: 'דין חל וסמכות שיפוט',
                      body:
                          'מדיניות פרטיות זו תפורש ותיושם בהתאם לדיני מדינת ישראל. סמכות השיפוט הבלעדית בכל סכסוך הנוגע למדיניות זו תהיה נתונה לבתי המשפט המוסמכים בישראל.',
                    ),
                    const SizedBox(height: 16),
                    _buildContactSection(context),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'מדיניות פרטיות',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'עודכן לאחרונה: $_lastUpdated',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.grey.shade600,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 2,
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required String body,
    List<String>? bullets,
    String? footer,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.6,
              color: Colors.grey.shade800,
            ),
          ),
          if (bullets != null && bullets.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...bullets.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8, right: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 8),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.6,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: 12),
            Text(
              footer,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.6,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContactSection(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.contact_mail,
                color: theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'צור קשר',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'לכל שאלה, בקשה או הבהרה בנושא מדיניות פרטיות זו, ניתן לפנות אלינו בכתובת:',
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.6,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            _contactEmail,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
