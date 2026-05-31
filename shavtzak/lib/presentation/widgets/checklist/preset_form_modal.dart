import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/debug/logger.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../core/utils/rtl_text_field_utils.dart';
import '../../../domain/entities/preset.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_state.dart';
import '../loading_overlay.dart';

/// Modal form for creating or editing a preset
class PresetFormModal extends StatefulWidget {
  final Preset? preset;
  final Future<CrudActionResult> Function(Preset) onSave;

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
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _nameController = TextEditingController();
  final _itemsScrollController = ScrollController();
  late final FocusNode _nameFocusNode;
  List<PresetItem> _items = [];
  bool _isSaving = false;
  String _savingMessage = '';

  @override
  void initState() {
    super.initState();
    _nameFocusNode = createRtlCursorFixedFocusNode(_nameController);
    if (widget.preset != null) {
      _nameController.text = widget.preset!.name;
      _items = List.from(widget.preset!.items);
    }
  }

  @override
  void dispose() {
    _itemsScrollController.dispose();
    _nameFocusNode.dispose();
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

  void _showMutationError(String message) {
    _scaffoldMessengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
  }

  Widget _buildMemberLabel(TeamMember? member, String fallback) {
    if (member == null) {
      return Text(fallback);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            member.name,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (member.isPermanent) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.verified_user,
            size: 14,
            color: Colors.blue.shade700,
          ),
        ],
      ],
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
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

    setState(() {
      _isSaving = true;
      _savingMessage =
          widget.preset == null ? 'יוצר פריסט...' : 'שומר פריסט...';
    });

    final result = await widget.onSave(preset);
    if (!mounted) {
      return;
    }

    if (result.isFailure) {
      setState(() {
        _isSaving = false;
        _savingMessage = '';
      });
      _showMutationError(result.message ?? 'שגיאה בשמירת הפריסט');
      return;
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth =
        screenSize.width < 700 ? screenSize.width * 0.92 : 640.0;
    final dialogHeight =
        screenSize.height < 820 ? screenSize.height * 0.86 : 700.0;

    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Stack(
                children: [
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // Header
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                widget.preset == null
                                    ? 'יצירת פריסט'
                                    : 'עריכת פריסט',
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  Logger.action('tap:close:presetForm');
                                  Navigator.pop(context);
                                },
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
                                  focusNode: _nameFocusNode,
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'פריטים בתבנית (${_items.length})',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Logger.action('tap:addItem');
                                        _addItem();
                                      },
                                      icon: const Icon(Icons.add,
                                          color: Colors.white),
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
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.list_alt,
                                                  size: 64,
                                                  color: Colors.grey[400]),
                                              const SizedBox(height: 16),
                                              Text(
                                                'אין פריטים בתבנית',
                                                style: TextStyle(
                                                    color: Colors.grey[600]),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'לחץ על "הוסף פריט" להוספת פריט חדש',
                                                style: TextStyle(
                                                    color: Colors.grey[500],
                                                    fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        )
                                      : BlocBuilder<TeamBloc, TeamState>(
                                          builder: (context, teamState) {
                                            final members =
                                                teamState is TeamLoaded
                                                    ? teamState.members
                                                    : <TeamMember>[];
                                            final memberMap = {
                                              for (var m in members) m.id: m
                                            };

                                            return ReorderableListView.builder(
                                              scrollController:
                                                  _itemsScrollController,
                                              itemCount: _items.length,
                                              onReorder: (oldIndex, newIndex) {
                                                Logger.action('tap:reorderItem', {'oldIndex': oldIndex, 'newIndex': newIndex});
                                                setState(() {
                                                  if (newIndex > oldIndex) {
                                                    newIndex -= 1;
                                                  }
                                                  final item =
                                                      _items.removeAt(oldIndex);
                                                  _items.insert(newIndex, item);
                                                });
                                              },
                                              itemBuilder: (context, index) {
                                                final item = _items[index];
                                                final responsible = memberMap[
                                                    item.responsibleId];
                                                final ccCount =
                                                    item.ccIds.length;

                                                return Card(
                                                  key: ValueKey('item_$index'),
                                                  margin: const EdgeInsets
                                                      .symmetric(vertical: 4),
                                                  child: ListTile(
                                                    leading: CircleAvatar(
                                                      child:
                                                          Text('${index + 1}'),
                                                    ),
                                                    title: Text(item.name),
                                                    subtitle: Wrap(
                                                      crossAxisAlignment:
                                                          WrapCrossAlignment
                                                              .center,
                                                      children: [
                                                        const Text('אחראי: '),
                                                        _buildMemberLabel(
                                                          responsible,
                                                          'לא הוגדר',
                                                        ),
                                                        if (ccCount > 0) ...[
                                                          const Text(' | '),
                                                          Text(
                                                              '$ccCount מיודעים'),
                                                        ],
                                                      ],
                                                    ),
                                                    trailing: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        IconButton(
                                                          icon: const Icon(
                                                              Icons.edit,
                                                              size: 20),
                                                          onPressed: () {
                                                            Logger.action('tap:editItem', {'index': index});
                                                            _editItem(index);
                                                          },
                                                          tooltip: 'ערוך',
                                                        ),
                                                        IconButton(
                                                          icon: const Icon(
                                                              Icons.delete,
                                                              size: 20,
                                                              color:
                                                                  Colors.red),
                                                          onPressed: () {
                                                            Logger.action('tap:removeItem', {'index': index});
                                                            _removeItem(index);
                                                          },
                                                          tooltip: 'הסר',
                                                        ),
                                                        const Icon(
                                                            Icons.drag_handle,
                                                            color: Colors.grey),
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
                              onPressed: _isSaving ? null : () {
                                Logger.action('tap:savePreset', {'isNew': widget.preset == null});
                                _save();
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.all(16),
                              ),
                              child: Text(widget.preset == null
                                  ? 'צור פריסט'
                                  : 'שמור שינויים'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  LoadingOverlay(
                    isLoading: _isSaving,
                    message: _savingMessage,
                  ),
                ],
              ),
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
  late final FocusNode _nameFocusNode;
  late final FocusNode _adminNoteFocusNode;
  TeamMember? _selectedResponsible;
  List<TeamMember> _selectedCcMembers = [];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _nameFocusNode = createRtlCursorFixedFocusNode(_nameController);
    _adminNoteFocusNode = createRtlCursorFixedFocusNode(_adminNoteController);
    if (widget.item != null) {
      _nameController.text = widget.item!.name;
      _adminNoteController.text = widget.item!.adminNote;
    }
  }

  @override
  void dispose() {
    _nameFocusNode.dispose();
    _adminNoteFocusNode.dispose();
    _nameController.dispose();
    _adminNoteController.dispose();
    super.dispose();
  }

  Widget _buildMemberChipLabel(TeamMember member) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(member.name),
        ),
        if (member.isPermanent) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.verified_user,
            size: 14,
            color: Colors.blue.shade700,
          ),
        ],
      ],
    );
  }

  Widget _buildCenteredMemberDropdownLabel(TeamMember member) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SizedBox(
        width: double.infinity,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  member.name,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (member.isPermanent) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.verified_user,
                  size: 14,
                  color: Colors.blue.shade700,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _initializeFromItem(PresetItem item, List<TeamMember> members) {
    if (_initialized) return;
    _initialized = true;

    try {
      _selectedResponsible =
          members.firstWhere((m) => m.id == item.responsibleId);
    } catch (e) {
      _selectedResponsible = null;
    }

    _selectedCcMembers =
        members.where((m) => item.ccIds.contains(m.id)).toList();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    widget.onSave(PresetItem(
      name: _nameController.text.trim(),
      responsibleId: _selectedResponsible?.id ?? '',
      ccIds: _selectedCcMembers.map((m) => m.id).toList(),
      adminNote: _adminNoteController.text.trim(),
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final itemDialogWidth =
        screenSize.width < 700 ? screenSize.width * 0.9 : 460.0;

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
        final ccOptions =
            members.where((m) => m.id != _selectedResponsible?.id).toList();

        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            title: Text(widget.item == null ? 'הוסף פריט' : 'ערוך פריט'),
            content: SizedBox(
              width: itemDialogWidth,
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Name field
                      TextFormField(
                        controller: _nameController,
                        focusNode: _nameFocusNode,
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
                        alignment: AlignmentDirectional.center,
                        decoration: const InputDecoration(
                          labelText: 'אחראי (אופציונלי)',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded: true,
                        selectedItemBuilder: (context) {
                          return members
                              .map(_buildCenteredMemberDropdownLabel)
                              .toList();
                        },
                        items: members
                            .map((m) => DropdownMenuItem<TeamMember>(
                                  value: m,
                                  child: _buildCenteredMemberDropdownLabel(m),
                                ))
                            .toList(),
                        onChanged: (value) {
                          Logger.action('select:responsible', {'memberId': value?.id});
                          setState(() {
                            _selectedResponsible = value;
                            // Remove from CC if selected as responsible
                            if (value != null) {
                              _selectedCcMembers
                                  .removeWhere((m) => m.id == value.id);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // Admin note field
                      TextFormField(
                        controller: _adminNoteController,
                        focusNode: _adminNoteFocusNode,
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
                                    final isSelected =
                                        _selectedCcMembers.contains(m);
                                    return FilterChip(
                                      label: _buildMemberChipLabel(m),
                                      selected: isSelected,
                                      onSelected: (selected) {
                                        Logger.action('toggle:ccMember', {'memberId': m.id, 'on': selected});
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
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Logger.action('tap:cancel:presetItemEditor');
                  Navigator.pop(context);
                },
                child: const Text('ביטול'),
              ),
              ElevatedButton(
                onPressed: () {
                  Logger.action('tap:savePresetItem', {'isNew': widget.item == null});
                  _save();
                },
                child: const Text('שמור'),
              ),
            ],
          ),
        );
      },
    );
  }
}
