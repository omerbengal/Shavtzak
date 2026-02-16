import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/preset.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/preset/preset_bloc.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_state.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_state.dart';
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
              body: Column(
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
                          onPressed: () => Navigator.pop(context),
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
                  onPressed: () =>
                      context.read<PresetBloc>().add(LoadPresets()),
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
                  onPressed: () => _showPresetFormModal(context, null),
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
                                  onPressed: () =>
                                      _showPresetFormModal(context, preset),
                                  tooltip: 'ערוך',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () =>
                                      _confirmDelete(context, preset),
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
    return BlocConsumer<PresetBloc, PresetState>(
      listener: (context, state) {
        if (state is PresetLoadedIntoEvent) {
          _scaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(
              content: Text(
                  'נטענו ${state.itemCount} פריטים מ-"${state.presetName}" לאירוע "${state.eventName}"'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        } else if (state is PresetError) {
          _scaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
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
                        decoration: const InputDecoration(
                          labelText: 'בחר פריסט',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded: true,
                        items: presets
                            .map((p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(
                                      '${p.name} (${p.items.length} פריטים)'),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedPreset = value),
                      ),
                      const SizedBox(height: 16),

                      // Event dropdown
                      DropdownButtonFormField<Event>(
                        value: _selectedEvent,
                        decoration: const InputDecoration(
                          labelText: 'בחר אירוע',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded: true,
                        items: events
                            .map((e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(
                                      '${e.name} (${e.startDate.day}/${e.startDate.month}/${e.startDate.year})'),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedEvent = value),
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
                                final responsibleLabel =
                                    responsible?.name.isNotEmpty == true
                                        ? responsible!.name
                                        : 'לא הוגדר';
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 14,
                                    child: Text('${index + 1}'),
                                  ),
                                  title: Text(item.name),
                                  subtitle: Text(
                                    'אחראי: $responsibleLabel'
                                    '${ccCount > 0 ? " | $ccCount מיודעים" : ""}',
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
                        onPressed:
                            _selectedPreset != null && _selectedEvent != null
                                ? () {
                                    context
                                        .read<PresetBloc>()
                                        .add(LoadPresetIntoEvent(
                                          presetId: _selectedPreset!.id,
                                          eventId: _selectedEvent!.id,
                                        ));
                                  }
                                : null,
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

  void _showPresetFormModal(BuildContext context, Preset? preset) {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (modalContext) => PresetFormModal(
        preset: preset,
        onSave: (savedPreset) {
          if (preset == null) {
            context.read<PresetBloc>().add(CreatePreset(savedPreset));
          } else {
            context.read<PresetBloc>().add(UpdatePreset(savedPreset));
          }
          Navigator.of(modalContext).pop();
        },
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
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () {
                context.read<PresetBloc>().add(DeletePreset(preset.id));
                Navigator.pop(dialogContext);
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
