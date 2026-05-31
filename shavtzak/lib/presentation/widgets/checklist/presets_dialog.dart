import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/debug/logger.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../domain/entities/preset.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/preset/preset_bloc.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_state.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_state.dart';
import '../loading_overlay.dart';
import 'preset_form_modal.dart';

/// Dialog for managing and loading checklist presets
class PresetsDialog extends StatefulWidget {
  const PresetsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: context.read<PresetBloc>(),
        child: const PresetsDialog(),
      ),
    );
  }

  @override
  State<PresetsDialog> createState() => _PresetsDialogState();
}

class _PresetsDialogState extends State<PresetsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  Preset? _selectedPreset;
  Event? _selectedEvent;
  bool _isMutating = false;
  String _mutationMessage = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Load presets when dialog opens
    context.read<PresetBloc>().add(LoadPresets());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showMessage(
    String message, {
    required Color backgroundColor,
  }) {
    _scaffoldMessengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
        ),
      );
  }

  Future<CrudActionResult> _waitForPresetAction(
    void Function(CrudActionCompleter completion) dispatch,
  ) {
    final completion = Completer<CrudActionResult>();
    dispatch(completion);
    return completion.future;
  }

  Future<CrudActionResult> _runPresetMutation({
    required String message,
    required void Function(CrudActionCompleter completion) dispatch,
  }) async {
    if (_isMutating) {
      return const CrudActionResult.failure('פעולה אחרת עדיין מתבצעת');
    }

    setState(() {
      _isMutating = true;
      _mutationMessage = message;
    });

    final result = await _waitForPresetAction(dispatch);
    if (!mounted) {
      return result;
    }

    setState(() {
      _isMutating = false;
      _mutationMessage = '';
    });
    return result;
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

  Widget _buildCenteredDropdownText(String text) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SizedBox(
        width: double.infinity,
        child: Text(
          text,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth =
        screenSize.width < 700 ? screenSize.width * 0.85 : 560.0;
    final dialogHeight =
        screenSize.height < 820 ? screenSize.height * 0.75 : 600.0;

    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Stack(
                children: [
                  Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'פריסטים',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                Logger.action('tap:close:presetsDialog');
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ),

                      // Tabs
                      TabBar(
                        controller: _tabController,
                        tabs: const [
                          Tab(text: 'ניהול פריסטים'),
                          Tab(text: 'טעינה לאירוע'),
                        ],
                      ),

                      // Tab content
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildManagePresetsTab(),
                            _buildLoadPresetTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                  LoadingOverlay(
                    isLoading: _isMutating,
                    message: _mutationMessage,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManagePresetsTab() {
    return BlocBuilder<PresetBloc, PresetState>(
      builder: (context, state) {
        if (state is PresetLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is PresetError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(state.message, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Logger.action('tap:retryLoadPresets');
                    context.read<PresetBloc>().add(LoadPresets());
                  },
                  child: const Text('נסה שוב'),
                ),
              ],
            ),
          );
        }

        final presets = state is PresetsLoaded ? state.presets : <Preset>[];

        return Column(
          children: [
            // Add button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isMutating
                      ? null
                      : () {
                          Logger.action('open:presetFormModal', {'mode': 'create'});
                          _showPresetFormModal(context, null);
                        },
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('הוסף פריסט'),
                ),
              ),
            ),

            // Preset list
            Expanded(
              child: presets.isEmpty
                  ? const Center(
                      child: Text(
                        'אין פריסטים\nלחץ על "הוסף פריסט" ליצירת פריסט חדש',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: presets.length,
                      itemBuilder: (context, index) {
                        final preset = presets[index];
                        return Card(
                          child: ListTile(
                            title: Text(preset.name),
                            subtitle: Text('${preset.items.length} פריטים'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: _isMutating
                                      ? null
                                      : () {
                                          Logger.action('open:presetFormModal', {'mode': 'edit', 'presetId': preset.id});
                                          _showPresetFormModal(
                                            context,
                                            preset,
                                          );
                                        },
                                  tooltip: 'ערוך',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: _isMutating
                                      ? null
                                      : () {
                                          Logger.action('open:deletePresetDialog', {'presetId': preset.id});
                                          _confirmDelete(context, preset);
                                        },
                                  tooltip: 'מחק',
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLoadPresetTab() {
    return BlocBuilder<PresetBloc, PresetState>(
      builder: (context, presetState) {
        return BlocBuilder<EventBloc, EventState>(
          builder: (context, eventState) {
            return BlocBuilder<TeamBloc, TeamState>(
              builder: (context, teamState) {
                final presets = presetState is PresetsLoaded
                    ? presetState.presets
                    : <Preset>[];
                final now = DateTime.now();
                final events = eventState is EventsLoaded
                    ? eventState.events
                        .where((e) => e.endDate.isAfter(now))
                        .toList()
                    : <Event>[];
                final members = teamState is TeamLoaded
                    ? teamState.members
                    : <TeamMember>[];
                final memberMap = {for (var m in members) m.id: m};

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Preset dropdown
                      DropdownButtonFormField<Preset>(
                        value: _selectedPreset,
                        alignment: AlignmentDirectional.center,
                        decoration: const InputDecoration(
                          labelText: 'בחר פריסט',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded: true,
                        selectedItemBuilder: (context) {
                          return presets
                              .map(
                                (p) => _buildCenteredDropdownText(
                                  '${p.name} (${p.items.length} פריטים)',
                                ),
                              )
                              .toList();
                        },
                        items: presets
                            .map((p) => DropdownMenuItem<Preset>(
                                  value: p,
                                  child: _buildCenteredDropdownText(
                                    '${p.name} (${p.items.length} פריטים)',
                                  ),
                                ))
                            .toList(),
                        onChanged: (value) {
                          Logger.action('select:preset', {'presetId': value?.id});
                          setState(() => _selectedPreset = value);
                        },
                      ),
                      const SizedBox(height: 16),

                      // Event dropdown
                      DropdownButtonFormField<Event>(
                        value: _selectedEvent,
                        alignment: AlignmentDirectional.center,
                        decoration: const InputDecoration(
                          labelText: 'בחר אירוע',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded: true,
                        selectedItemBuilder: (context) {
                          return events
                              .map(
                                (e) => _buildCenteredDropdownText(
                                  '${e.name} (${e.startDate.day}/${e.startDate.month}/${e.startDate.year})',
                                ),
                              )
                              .toList();
                        },
                        items: events
                            .map((e) => DropdownMenuItem<Event>(
                                  value: e,
                                  child: _buildCenteredDropdownText(
                                    '${e.name} (${e.startDate.day}/${e.startDate.month}/${e.startDate.year})',
                                  ),
                                ))
                            .toList(),
                        onChanged: (value) {
                          Logger.action('select:event', {'eventId': value?.id});
                          setState(() => _selectedEvent = value);
                        },
                      ),
                      const SizedBox(height: 24),

                      // Preview section
                      if (_selectedPreset != null) ...[
                        const Text(
                          'פריטים בפריסט:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: _selectedPreset!.items.length,
                              itemBuilder: (context, index) {
                                final item = _selectedPreset!.items[index];
                                final responsible =
                                    memberMap[item.responsibleId];
                                final ccCount = item.ccIds.length;
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 14,
                                    child: Text('${index + 1}'),
                                  ),
                                  title: Text(item.name),
                                  subtitle: Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      const Text('אחראי: '),
                                      _buildMemberLabel(
                                        responsible,
                                        'לא הוגדר',
                                      ),
                                      if (ccCount > 0) ...[
                                        const Text(' | '),
                                        Text('$ccCount מיודעים'),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ] else
                        const Expanded(
                          child: Center(
                            child: Text(
                              'בחר פריסט כדי לראות את הפריטים שלו',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ),

                      const SizedBox(height: 16),

                      // Load button
                      ElevatedButton.icon(
                        onPressed: _isMutating ||
                                _selectedPreset == null ||
                                _selectedEvent == null
                            ? null
                            : () {
                                Logger.action('tap:loadPresetIntoEvent', {
                                  'presetId': _selectedPreset?.id,
                                  'eventId': _selectedEvent?.id,
                                });
                                _handleLoadPresetIntoEvent();
                              },
                        icon: const Icon(Icons.download, color: Colors.white),
                        label: const Text('טען לאירוע'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _handleLoadPresetIntoEvent() async {
    if (_selectedPreset == null || _selectedEvent == null) {
      return;
    }

    final result = await _runPresetMutation(
      message: 'טוען פריסט לאירוע...',
      dispatch: (completion) => context.read<PresetBloc>().add(
            LoadPresetIntoEvent(
              presetId: _selectedPreset!.id,
              eventId: _selectedEvent!.id,
              completion: completion,
            ),
          ),
    );

    if (!mounted) {
      return;
    }

    if (result.isFailure) {
      _showMessage(
        result.message ?? 'שגיאה בטעינת פריסט לאירוע',
        backgroundColor: Colors.red,
      );
      return;
    }

    _showMessage(
      result.message ?? 'הפריסט נטען בהצלחה',
      backgroundColor: Colors.green,
    );
    Navigator.pop(context);
  }

  void _showPresetFormModal(BuildContext context, Preset? preset) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (modalContext) => PresetFormModal(
        preset: preset,
        onSave: (savedPreset) => _runPresetMutation(
          message: preset == null ? 'יוצר פריסט...' : 'שומר פריסט...',
          dispatch: (completion) {
            if (preset == null) {
              context.read<PresetBloc>().add(
                    CreatePreset(savedPreset, completion: completion),
                  );
            } else {
              context.read<PresetBloc>().add(
                    UpdatePreset(savedPreset, completion: completion),
                  );
            }
          },
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Preset preset) {
    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת פריסט'),
          content:
              Text('האם אתה בטוח שברצונך למחוק את הפריסט "${preset.name}"?'),
          actions: [
            TextButton(
              onPressed: () {
                Logger.action('tap:cancel:deletePresetDialog', {'presetId': preset.id});
                Navigator.pop(dialogContext);
              },
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () async {
                Logger.action('tap:confirmDeletePreset', {'presetId': preset.id});
                Navigator.pop(dialogContext);
                final result = await _runPresetMutation(
                  message: 'מוחק פריסט...',
                  dispatch: (completion) => context.read<PresetBloc>().add(
                        DeletePreset(
                          preset.id,
                          completion: completion,
                        ),
                      ),
                );
                if (!mounted) {
                  return;
                }

                if (result.isFailure) {
                  _showMessage(
                    result.message ?? 'שגיאה במחיקת פריסט',
                    backgroundColor: Colors.red,
                  );
                  return;
                }

                _showMessage(
                  result.message ?? 'הפריסט נמחק בהצלחה',
                  backgroundColor: Colors.green,
                );
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('מחק'),
            ),
          ],
        ),
      ),
    );
  }
}
