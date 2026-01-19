import 'package:flutter/material.dart';
import '../../../core/services/environment_service.dart';
import 'widgets/collection_viewer.dart';

/// A hidden diagnostic screen for viewing Firestore data in real-time.
/// Accessible at /db (production) or /test/db (test environment).
/// No authentication required - URL obscurity is sufficient protection.
class DbPreviewScreen extends StatefulWidget {
  const DbPreviewScreen({super.key});

  @override
  State<DbPreviewScreen> createState() => _DbPreviewScreenState();
}

class _DbPreviewScreenState extends State<DbPreviewScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String? _expandedCollection;

  // All collections to display
  static const List<_CollectionConfig> _collections = [
    _CollectionConfig('teamMembers', 'חברי צוות', Icons.people, true),
    _CollectionConfig('events', 'אירועים', Icons.event, true),
    _CollectionConfig('assignments', 'שיבוצים', Icons.assignment_ind, true),
    _CollectionConfig('checklist_items', 'פריטי צ\'קליסט', Icons.checklist, true),
    _CollectionConfig('checklist_presets', 'תבניות צ\'קליסט', Icons.list_alt, true),
    _CollectionConfig('roles', 'תפקידים', Icons.work, true),
    _CollectionConfig('utilities', 'כלים (גלובלי)', Icons.build, false),
    _CollectionConfig('keys', 'מפתחות (גלובלי)', Icons.key, false),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EnvironmentService.instance,
      builder: (context, _) {
        final isTestMode = EnvironmentService.instance.isTestMode;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildEnvironmentBadge(isTestMode),
                  const SizedBox(width: 8),
                  const Text('DB Preview'),
                ],
              ),
            ),
            body: Column(
              children: [
                // Search bar
                _buildSearchBar(),
                // Collections list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _collections.length,
                    itemBuilder: (context, index) {
                      final config = _collections[index];
                      final isExpanded = _expandedCollection == config.name;

                      return _buildCollectionCard(config, isExpanded);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEnvironmentBadge(bool isTestMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isTestMode ? Colors.red.shade600 : Colors.green.shade600,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isTestMode ? 'TEST' : 'PROD',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.grey.shade100,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'חיפוש לפי ID או תוכן...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
      ),
    );
  }

  Widget _buildCollectionCard(_CollectionConfig config, bool isExpanded) {
    final fullName = config.useEnvironmentPrefix
        ? '${EnvironmentService.instance.collectionPrefix}${config.name}'
        : config.name;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          // Collection header
          ListTile(
            leading: Icon(config.icon, color: Theme.of(context).primaryColor),
            title: Text(
              config.hebrewName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              fullName,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Colors.grey.shade600,
              ),
            ),
            trailing: Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            onTap: () {
              setState(() {
                _expandedCollection = isExpanded ? null : config.name;
              });
            },
          ),
          // Expanded content
          if (isExpanded)
            SizedBox(
              height: 400,
              child: CollectionViewer(
                key: ValueKey('${config.name}_$_searchQuery'),
                collectionName: config.name,
                useEnvironmentPrefix: config.useEnvironmentPrefix,
                searchQuery: _searchQuery,
              ),
            ),
        ],
      ),
    );
  }
}

/// Configuration for a single collection
class _CollectionConfig {
  final String name;
  final String hebrewName;
  final IconData icon;
  final bool useEnvironmentPrefix;

  const _CollectionConfig(this.name, this.hebrewName, this.icon, this.useEnvironmentPrefix);
}
