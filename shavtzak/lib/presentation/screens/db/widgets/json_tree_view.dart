import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/debug/logger.dart';

/// A recursive widget that renders JSON/Map data as an expandable tree view.
/// Handles special Firestore types like Timestamp and GeoPoint.
class JsonTreeView extends StatefulWidget {
  final Map<String, dynamic> data;
  final int indentLevel;
  final bool initiallyExpanded;

  const JsonTreeView({
    super.key,
    required this.data,
    this.indentLevel = 0,
    this.initiallyExpanded = true,
  });

  @override
  State<JsonTreeView> createState() => _JsonTreeViewState();
}

class _JsonTreeViewState extends State<JsonTreeView> {
  late Map<String, bool> _expandedKeys;

  @override
  void initState() {
    super.initState();
    _expandedKeys = {};
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.data.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.map((entry) {
        return _buildEntry(entry.key, entry.value);
      }).toList(),
    );
  }

  Widget _buildEntry(String key, dynamic value) {
    final indent = widget.indentLevel * 16.0;
    final isExpanded = _expandedKeys[key] ?? widget.initiallyExpanded;

    // Handle different value types
    if (value == null) {
      return _buildLeafNode(key, 'null', Colors.grey, indent);
    } else if (value is Map<String, dynamic>) {
      return _buildMapNode(key, value, indent, isExpanded);
    } else if (value is List) {
      return _buildListNode(key, value, indent, isExpanded);
    } else if (value is Timestamp) {
      return _buildLeafNode(
        key,
        _formatTimestamp(value),
        Colors.purple.shade700,
        indent,
      );
    } else if (value is GeoPoint) {
      return _buildLeafNode(
        key,
        '(${value.latitude.toStringAsFixed(4)}, ${value.longitude.toStringAsFixed(4)})',
        Colors.teal,
        indent,
      );
    } else if (value is bool) {
      return _buildLeafNode(
        key,
        value.toString(),
        value ? Colors.green.shade700 : Colors.red.shade700,
        indent,
      );
    } else if (value is num) {
      return _buildLeafNode(key, value.toString(), Colors.blue.shade700, indent);
    } else {
      // String or other types
      return _buildLeafNode(key, '"$value"', Colors.orange.shade800, indent);
    }
  }

  Widget _buildLeafNode(String key, String value, Color valueColor, double indent) {
    return Padding(
      padding: EdgeInsets.only(right: indent, top: 4, bottom: 4),
      child: InkWell(
        onLongPress: () {
          Logger.action('longPress:treeLeaf', {'indentLevel': widget.indentLevel});
          _copyToClipboard('$key: $value');
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 20), // Space for expand icon alignment
            Text(
              '$key: ',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapNode(
    String key,
    Map<String, dynamic> value,
    double indent,
    bool isExpanded,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(right: indent, top: 4, bottom: 4),
          child: InkWell(
            onTap: () {
              Logger.action('tap:expandTreeNode', {'expanding': !isExpanded, 'indentLevel': widget.indentLevel});
              setState(() {
                _expandedKeys[key] = !isExpanded;
              });
            },
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_left,
                  size: 18,
                  color: Colors.grey.shade600,
                ),
                Text(
                  '$key: ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '{${value.length}}',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: JsonTreeView(
              data: value,
              indentLevel: widget.indentLevel + 1,
              initiallyExpanded: false, // Nested objects collapsed by default
            ),
          ),
      ],
    );
  }

  Widget _buildListNode(
    String key,
    List value,
    double indent,
    bool isExpanded,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(right: indent, top: 4, bottom: 4),
          child: InkWell(
            onTap: () {
              Logger.action('tap:expandTreeNode', {'expanding': !isExpanded, 'indentLevel': widget.indentLevel});
              setState(() {
                _expandedKeys[key] = !isExpanded;
              });
            },
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_left,
                  size: 18,
                  color: Colors.grey.shade600,
                ),
                Text(
                  '$key: ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '[${value.length}]',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(value.length, (index) {
                final item = value[index];
                if (item is Map<String, dynamic>) {
                  return Padding(
                    padding: EdgeInsets.only(right: (widget.indentLevel + 1) * 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '[$index]:',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        JsonTreeView(
                          data: item,
                          indentLevel: widget.indentLevel + 2,
                          initiallyExpanded: false,
                        ),
                      ],
                    ),
                  );
                } else {
                  return _buildEntry('[$index]', item);
                }
              }),
            ),
          ),
      ],
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('הועתק: $text'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
