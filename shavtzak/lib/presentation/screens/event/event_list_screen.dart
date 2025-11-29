import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/role_types.dart';
import '../../../domain/entities/event.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/event/event_state.dart';
import 'event_form_screen.dart';

class EventListScreen extends StatefulWidget {
  const EventListScreen({super.key});

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    context.read<EventBloc>().add(const LoadEvents());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      context.read<EventBloc>().add(const LoadEvents());
    } else {
      context.read<EventBloc>().add(SearchEvents(query));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: _showSearch
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'חיפוש אירוע...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.black54),
                  ),
                  style: const TextStyle(color: Colors.black),
                  onChanged: _onSearchChanged,
                )
              : const Text('אירועים'),
          actions: [
            IconButton(
              icon: Icon(_showSearch ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) {
                    _searchController.clear();
                    context.read<EventBloc>().add(const LoadEvents());
                  }
                });
              },
            ),
          ],
        ),
        body: BlocConsumer<EventBloc, EventState>(
          listener: (context, state) {
            if (state is EventError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message), backgroundColor: Colors.red),
              );
            } else if (state is EventOperationSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message), backgroundColor: Colors.green),
              );
            }
          },
          builder: (context, state) {
            if (state is EventLoading || state is EventOperating) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is EventsEmpty) {
              return _buildEmptyState(state.message);
            }
            if (state is EventsLoaded) {
              return _buildEventList(state);
            }
            if (state is EventError) {
              return _buildErrorState(state.message);
            }
            return _buildEmptyState('טוען...');
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const EventFormScreen()),
            );
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildEventList(EventsLoaded state) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<EventBloc>().add(const RefreshEvents());
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('סך הכל', state.totalCount.toString()),
                _buildStatItem('קרובים', state.upcomingCount.toString()),
                _buildStatItem('פעילים', state.activeCount.toString()),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: state.events.length,
              itemBuilder: (context, index) {
                return _buildEventCard(state.events[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      ],
    );
  }

  Widget _buildEventCard(Event event) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue,
          child: Text(event.name.isNotEmpty ? event.name[0] : '?', style: const TextStyle(color: Colors.white)),
        ),
        title: Text(event.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(_formatDate(event.startDate), style: const TextStyle(fontSize: 12)),
            Text(event.location, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        onTap: () => _showEventDetail(event),
      ),
    );
  }

  void _showEventDetail(Event event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: ListView(
                controller: scrollController,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.blue,
                        child: Text(event.name[0], style: const TextStyle(color: Colors.white, fontSize: 24)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(event.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  _buildDetailRow('תאריך', event.dateRangeString),
                  _buildDetailRow('מיקום', event.location),
                  _buildDetailRow('שעת התחלה', event.startTime),
                  _buildDetailRow('שעת סיום', event.endTime),
                  _buildDetailRow('שעת התייצבות', event.assemblyTime),
                  if (event.requiresArmed) _buildDetailRow('דרוש חמוש', 'כן'),
                  if (event.notes.isNotEmpty) _buildDetailRow('הערות', event.notes),
                  const Divider(height: 32),
                  const Text('תפקידים נדרשים', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...event.roleRequirements.entries.where((e) => e.value > 0).map((e) =>
                    ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(e.key.hebrewName),
                      trailing: Text('${e.value} נדרשים'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => EventFormScreen(event: event)),
                          );
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('ערוך'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final eventBloc = context.read<EventBloc>();
                          Navigator.pop(context);
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => Directionality(
                              textDirection: TextDirection.rtl,
                              child: AlertDialog(
                                title: const Text('מחיקת אירוע'),
                                content: Text('האם למחוק את ${event.name}?\nפעולה זו תמחק גם את כל השיבוצים.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('ביטול'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                    child: const Text('מחק'),
                                  ),
                                ],
                              ),
                            ),
                          );
                          if (confirmed == true) {
                            eventBloc.add(DeleteEvent(event.id));
                          }
                        },
                        icon: const Icon(Icons.delete, color: Colors.red),
                        label: const Text('מחק', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EventFormScreen()),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('הוסף אירוע ראשון'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 80, color: Colors.red),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(fontSize: 18, color: Colors.red), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.read<EventBloc>().add(const LoadEvents()),
            icon: const Icon(Icons.refresh),
            label: const Text('נסה שוב'),
          ),
        ],
      ),
    );
  }
}
