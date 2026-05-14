import 'package:flutter/material.dart';

/// A public, unauthenticated terms of service screen.
/// Accessible at /terms-of-service (production) or /test/terms-of-service (test environment).
/// No authentication required - intended for direct linking from external sources
/// (e.g., app store listings, footer links).
class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  static const String _lastUpdated = '14 במאי 2026';
  static const String _contactEmail = 'omer.bengal7@gmail.com';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('תנאי שימוש'),
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
                      title: '1. קבלת התנאים',
                      body:
                          'ברוכים הבאים לשבצק (להלן: "האפליקציה", "השירות"). תנאי שימוש אלה (להלן: "התנאים") מהווים הסכם משפטי מחייב בין המשתמש (להלן: "אתה", "המשתמש") לבין מפעיל האפליקציה.\n\nהשימוש באפליקציה, בכל אופן שהוא, מהווה הסכמתך המלאה לתנאים אלה. אם אינך מסכים לתנאים, אנא הימנע משימוש באפליקציה.',
                    ),
                    _buildSection(
                      context,
                      title: '2. תיאור השירות',
                      body:
                          'שבצק היא אפליקציית רשת לניהול צוותים, אירועים ושיבוצים. השירות מאפשר למנהלים ליצור ולנהל אירועים, להגדיר תפקידים ויכולות לחברי צוות, ולשבץ אותם לאירועים בהתאם לזמינות ולכישורים.\n\nהשירות עשוי לכלול תכונות נוספות שיתווספו או יוסרו מעת לעת, לפי שיקול דעתנו הבלעדי.',
                    ),
                    _buildSection(
                      context,
                      title: '3. זכאות וחשבון משתמש',
                      body:
                          'השימוש באפליקציה מותר אך ורק למשתמשים שהוזמנו על ידי מנהל המערכת של הצוות הרלוונטי. כל משתמש אחראי:',
                      bullets: const [
                        'לשמור על סודיות פרטי הזיהוי האישיים שלו.',
                        'לוודא שהמידע שהוזן עליו במערכת מדויק ומעודכן.',
                        'להודיע מיידית על כל שימוש בלתי מורשה בחשבונו.',
                        'לעשות שימוש באפליקציה בהתאם לחוק ולתנאים אלה.',
                      ],
                      footer:
                          'השירות אינו מיועד לקטינים מתחת לגיל 13. שימוש על ידי קטינים מתחת לגיל 18 דורש הסכמת הורה או אפוטרופוס חוקי.',
                    ),
                    _buildSection(
                      context,
                      title: '4. שימוש מקובל',
                      body: 'המשתמש מתחייב שלא:',
                      bullets: const [
                        'להשתמש באפליקציה לכל מטרה בלתי חוקית או אסורה.',
                        'להעלות, להזין או להפיץ תוכן פוגעני, מאיים, משמיץ או בלתי הולם.',
                        'לנסות לחדור, לפרוץ, לעקוף או לפגוע באבטחת המערכת.',
                        'להעתיק, לשכפל, להפיץ או למכור כל חלק מהשירות ללא הרשאה מפורשת.',
                        'להשתמש בכלים אוטומטיים, רובוטים או סקריפטים לצורך גישה למידע.',
                        'להפריע לשימוש של משתמשים אחרים או לפעילות התקינה של השירות.',
                        'להתחזות לאדם או גורם אחר, או להציג מידע כוזב.',
                      ],
                    ),
                    _buildSection(
                      context,
                      title: '5. תוכן המשתמש',
                      body:
                          'המשתמש שומר על כל הזכויות בתוכן שהוא מזין למערכת (כגון שמות, אירועים, הערות). יחד עם זאת, בהזנת תוכן למערכת, המשתמש מעניק לנו רישיון לא בלעדי, גלובלי ופטור מתמלוגים לאחסן, לעבד ולהציג את התוכן לצורך אספקת השירות.\n\nהמשתמש מצהיר ומתחייב כי התוכן שהוא מזין אינו מפר זכויות של צד שלישי ואינו מנוגד לחוק.',
                    ),
                    _buildSection(
                      context,
                      title: '6. קניין רוחני',
                      body:
                          'כל הזכויות באפליקציה, לרבות קוד המקור, העיצוב, הלוגו, הממשק, התכנים והתיעוד, שמורות למפעיל. אין להעתיק, לשכפל, להפיץ, לפרסם, לשנות או ליצור יצירות נגזרות מהאפליקציה ללא אישור מראש ובכתב.',
                    ),
                    _buildSection(
                      context,
                      title: '7. פרטיות',
                      body:
                          'השימוש באפליקציה כפוף גם למדיניות הפרטיות שלנו, המהווה חלק בלתי נפרד מתנאים אלה. אנא קרא את מדיניות הפרטיות בעיון לפני השימוש באפליקציה.',
                    ),
                    _buildSection(
                      context,
                      title: '8. זמינות השירות',
                      body:
                          'אנו עושים את מירב המאמצים להבטיח שהשירות יהיה זמין באופן רציף, אך איננו מתחייבים לזמינות בלתי פוסקת. השירות עלול להיות מושבת מעת לעת לצורך תחזוקה, שדרוגים או מסיבות טכניות, ללא הודעה מוקדמת.\n\nאיננו אחראים לכל נזק שייגרם עקב חוסר זמינות של השירות.',
                    ),
                    _buildSection(
                      context,
                      title: '9. הסתייגויות והגבלת אחריות',
                      body:
                          'האפליקציה מסופקת "כפי שהיא" (AS IS) ו"כפי שזמינה" (AS AVAILABLE), ללא כל אחריות מסוג כלשהו, מפורשת או משתמעת.',
                      bullets: const [
                        'איננו מבטיחים שהשירות יענה על כל הציפיות או הצרכים של המשתמש.',
                        'איננו מבטיחים שהשירות יהיה נקי משגיאות, באגים או הפרעות.',
                        'איננו אחראים לאיבוד מידע, אף שננקטים אמצעי הגנה סבירים.',
                        'איננו אחראים להחלטות שיתקבלו על בסיס המידע באפליקציה.',
                      ],
                      footer:
                          'במידה המרבית המותרת על פי דין, אחריותנו הכוללת כלפי המשתמש, מכל סיבה שהיא, מוגבלת לסכום הסמלי של 1 ש"ח.',
                    ),
                    _buildSection(
                      context,
                      title: '10. שיפוי',
                      body:
                          'המשתמש מתחייב לשפות ולפצות את מפעיל האפליקציה בגין כל תביעה, דרישה, נזק, אובדן או הוצאה (לרבות שכר טרחת עורכי דין) שייגרמו עקב הפרת תנאים אלה על ידי המשתמש, או עקב שימוש לרעה באפליקציה.',
                    ),
                    _buildSection(
                      context,
                      title: '11. סיום ההסכם',
                      body:
                          'אנו שומרים לעצמנו את הזכות, על פי שיקול דעתנו הבלעדי, להשעות, להגביל או להפסיק את גישת המשתמש לשירות, כולה או חלקה, בכל עת וללא הודעה מוקדמת, וזאת במקרים הבאים:',
                      bullets: const [
                        'הפרת תנאי שימוש אלה.',
                        'שימוש לרעה באפליקציה או בשירות.',
                        'חשד לפעילות בלתי חוקית או מזיקה.',
                        'הפסקת השירות לכלל המשתמשים מסיבות עסקיות.',
                      ],
                    ),
                    _buildSection(
                      context,
                      title: '12. שינויים בתנאים',
                      body:
                          'אנו שומרים לעצמנו את הזכות לעדכן ולשנות תנאים אלה מעת לעת, על פי שיקול דעתנו הבלעדי. שינויים יפורסמו בעמוד זה עם תאריך עדכון מעודכן.\n\nהמשך השימוש באפליקציה לאחר עדכון התנאים מהווה הסכמה לתנאים המעודכנים. מומלץ לעיין בתנאים מעת לעת.',
                    ),
                    _buildSection(
                      context,
                      title: '13. דין חל וסמכות שיפוט',
                      body:
                          'תנאים אלה כפופים לדיני מדינת ישראל ויפורשו על פיהם, ללא התחשבות בעקרונות ברירת הדין. סמכות השיפוט הבלעדית בכל סכסוך הנובע מתנאים אלה או מהשימוש באפליקציה תהיה נתונה לבתי המשפט המוסמכים במחוז תל אביב, ישראל.',
                    ),
                    _buildSection(
                      context,
                      title: '14. כלליות',
                      body:
                          'אם תנאי כלשהו בתנאים אלה יימצא כבלתי תקף או בלתי אכיף, יוסיפו יתר התנאים לעמוד בתוקפם. אי אכיפת זכות כלשהי על ידינו לא תיחשב כוויתור על אותה זכות. תנאים אלה מהווים את ההסכם המלא בין הצדדים בכל הנוגע לשימוש באפליקציה.',
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
          'תנאי שימוש',
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
            'לכל שאלה, הבהרה או בקשה בנושא תנאי שימוש אלה, ניתן לפנות אלינו בכתובת:',
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
