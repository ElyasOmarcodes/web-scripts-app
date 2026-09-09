import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/activity_screen.dart' show EventLine;
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import 'mac_widgets.dart';

/// Live output docked at the bottom of the script detail page.
class LogPanel extends StatefulWidget {
  const LogPanel({super.key, this.height = 150});

  final double height;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final state = context.watch<AppState>();
    _scrollToEnd();

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: mac.sidebar,
        border: Border(top: BorderSide(color: mac.hairline, width: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 2),
            child: Row(
              children: [
                Icon(Icons.terminal_rounded, size: 15, color: mac.text2),
                const SizedBox(width: 8),
                Text('پېښې',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: mac.text)),
                const Spacer(),
                MacIconButton(
                  icon: Icons.open_in_new_rounded,
                  tooltip: 'ټولې پېښې',
                  onPressed: () => state.navigate(AppPage.activity),
                ),
                MacIconButton(
                  icon: Icons.clear_all_rounded,
                  tooltip: 'پاکول',
                  onPressed: state.log.isEmpty ? null : state.clearLog,
                ),
              ],
            ),
          ),
          Expanded(
            child: state.log.isEmpty
                ? Center(
                    child: Text('لا هېڅ پېښه نشته',
                        style: TextStyle(fontSize: 12, color: mac.text3)),
                  )
                : ListView.builder(
                    controller: _controller,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    itemCount: state.log.length,
                    itemBuilder: (context, index) =>
                        EventLine(event: state.log[index], showTime: false),
                  ),
          ),
        ],
      ),
    );
  }
}
