import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/preset.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_state.dart';

/// Modal form for creating or editing a preset
class PresetFormModal extends StatefulWidget {
  final Preset? preset;
  final Function(Preset) onSave;

  const PresetFormModal({
    super.key,
    this.preset,
    required this.onSave,
  });

  @override
  State<PresetFormModal> createState() => _PresetFormModalState();
}

class _PresetFormModalState extends State<PresetFormModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  List<PresetItem> _items = [];

  @override
  void initState() {
    super.initState();
    if (widget.preset != null) {
      _nameController.text = widget.preset!.name;
      _items = List.from(widget.preset!.items);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addItem() {
    _showItemEditor(null, (item) {
      setState(() => _items.add(item));
    });
  }

  void _editItem(int index) {
    _showItemEditor(_items[index], (item) {
      setState(() => _items[index] = item);
    });
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  void _showItemEditor(PresetItem? item, Function(PresetItem) onSave) {
    showDialog(
      context: context,
      builder: (context) => _PresetItemEditor(
        item: item,
        onSave: onSave,
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('יש להוסיף לפחות פריט אחד'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final preset = Preset(
      id: widget.preset?.id ?? '',
      name: _nameController.text.trim(),
      items: _items,
      createdAt: widget.preset?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    widget.onSave(preset);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.preset == null ? 'יצירת פריסט' : 'עריכת פריסט',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Name field
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'שם הפריסט *',
                            border: OutlineInputBorder(),
                            hintText: 'לדוגמה: אירוע רגיל',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'אנא הזן שם לפריסט';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),

                        // Items section header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'פריטים בתבנית (${_items.length})',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _addItem,
                              icon: const Icon(Icons.add, color: Colors.white),
                              label: const Text('הוסף פריט'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Items list
                        Expanded(
                          child: _items.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.list_alt, size: 64, color: Colors.grey[400]),
                                      const SizedBox(height: 16),
                                      Text(
                                        'אין פריטים בתבנית',
                                        style: TextStyle(color: Colors.grey[600]),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'לחץ על "הוסף פריט" להוספת פריט חדש',
                                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                      ),
                                    ],
                                  ),
                                )
                              : BlocBuilder<TeamBloc, TeamState>(
                                  builder: (context, teamState) {
                                    final members = teamState is TeamLoaded
                                        ? teamState.members
                                        : <TeamMember>[];
                                    final memberMap = {for (var m in members) m.id: m};

                                    return ReorderableListView.builder(
                                      scrollController: scrollController,
                                      itemCount: _items.length,
                                      onReorder: (oldIndex, newIndex) {
                                        setState(() {
                                          if (newIndex > oldIndex) newIndex -= 1;
                                          final item = _items.removeAt(oldIndex);
                                          _items.insert(newIndex, item);
                                        });
                                      },
                                      itemBuilder: (context, index) {
                                        final item = _items[index];
                                        final responsible = memberMap[item.responsibleId];
                                        final ccCount = item.ccIds.length;

                                        return Card(
                                          key: ValueKey('item_$index'),
                                          margin: const EdgeInsets.symmetric(vertical: 4),
                                          child: ListTile(
                                            leading: CircleAvatar(
                                              child: Text('${index + 1}'),
                                            ),
                                            title: Text(item.name),
                                            subtitle: Text(
                                              'אחראי: ${responsible?.name ?? "לא ידוע"}'
                                              '${ccCount > 0 ? " | $ccCount מיודעים" : ""}',
                                            ),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.edit, size: 20),
                                                  onPressed: () => _editItem(index),
                                                  tooltip: 'ערוך',
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                                  onPressed: () => _removeItem(index),
                                                  tooltip: 'הסר',
                                                ),
                                                const Icon(Icons.drag_handle, color: Colors.grey),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Save button
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                      child: Text(widget.preset == null ? 'צור פריסט' : 'שמור שינויים'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog for editing a single preset item
class _PresetItemEditor extends StatefulWidget {
  final PresetItem? item;
  final Function(PresetItem) onSave;

  const _PresetItemEditor({
    this.item,
    required this.onSave,
  });

  @override
  State<_PresetItemEditor> createState() => _PresetItemEditorState();
}

class _PresetItemEditorState extends State<_PresetItemEditor> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _adminNoteController = TextEditingController();
  TeamMember? _selectedResponsible;
  List<TeamMember> _selectedCcMembers = [];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.item != null) {
      _nameController.text = widget.item!.name;
      _adminNoteController.text = widget.item!.adminNote;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _adminNoteController.dispose();
    super.dispose();
  }

  void _initializeFromItem(PresetItem item, List<TeamMember> members) {
    if (_initialized) return;
    _initialized = true;

    try {
      _selectedResponsible = members.firstWhere((m) => m.id == item.responsibleId);
    } catch (e) {
      _selectedResponsible = null;
    }

    _selectedCcMembers = members.where((m) => item.ccIds.contains(m.id)).toList();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedResponsible == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('יש לבחור אחראי'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    widget.onSave(PresetItem(
      name: _nameController.text.trim(),
      responsibleId: _selectedResponsible!.id,
      ccIds: _selectedCcMembers.map((m) => m.id).toList(),
      adminNote: _adminNoteController.text.trim(),
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TeamBloc, TeamState>(
      builder: (context, teamState) {
        final members = teamState is TeamLoaded
            ? teamState.members.where((m) => m.isActive).toList()
            : <TeamMember>[];

        // Initialize from item if editing
        if (widget.item != null && !_initialized) {
          _initializeFromItem(widget.item!, members);
        }

        // Filter out responsible from CC options
        final ccOptions = members.where((m) => m.id != _selectedResponsible?.id).toList();

        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(widget.item == null ? 'הוסף פריט' : 'ערוך פריט'),
            content: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Name field
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'שם הפריט *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'אנא הזן שם לפריט';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Responsible dropdown
                    DropdownButtonFormField<TeamMember>(
                      value: _selectedResponsible,
                      decoration: const InputDecoration(
                        labelText: 'אחראי *',
                        border: OutlineInputBorder(),
                      ),
                      isExpanded: true,
                      items: members.map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(m.name),
                      )).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedResponsible = value;
                          // Remove from CC if selected as responsible
                          if (value != null) {
                            _selectedCcMembers.removeWhere((m) => m.id == value.id);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Admin note field
                    TextFormField(
                      controller: _adminNoteController,
                      decoration: const InputDecoration(
                        labelText: 'הערת מנהל',
                        border: OutlineInputBorder(),
                        hintText: 'הערה שתועתק לכל פריט שנוצר מהפריסט',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),

                    // CC members
                    const Text(
                      'מיודעים:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ccOptions.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'אין חברי צוות זמינים',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : SingleChildScrollView(
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: ccOptions.map((m) {
                                  final isSelected = _selectedCcMembers.contains(m);
                                  return FilterChip(
                                    label: Text(m.name),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setState(() {
                                        if (selected) {
                                          _selectedCcMembers.add(m);
                                        } else {
                                          _selectedCcMembers.remove(m);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ביטול'),
              ),
              ElevatedButton(
                onPressed: _save,
                child: const Text('שמור'),
              ),
            ],
          ),
        );
      },
    );
  }
}
