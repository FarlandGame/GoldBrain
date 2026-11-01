import 'package:flutter/material.dart';

/// Lazily mounts a tab, then retains its state during navigation. Offstage
/// hides layout/semantics and TickerMode pauses only invisible animations;
/// asynchronous work and stored conversation state continue normally.
class RetainedTab extends StatefulWidget {
  const RetainedTab({
    super.key,
    required this.active,
    required this.retainedChild,
    required this.otherChild,
  });

  final bool active;
  final Widget retainedChild;
  final Widget otherChild;

  @override
  State<RetainedTab> createState() => _RetainedTabState();
}

class _RetainedTabState extends State<RetainedTab> {
  bool _visited = false;

  @override
  Widget build(BuildContext context) {
    _visited = _visited || widget.active;
    return Stack(
      children: [
        if (_visited)
          Offstage(
            offstage: !widget.active,
            child: TickerMode(
              enabled: widget.active,
              child: ExcludeFocus(
                excluding: !widget.active,
                child: widget.retainedChild,
              ),
            ),
          ),
        if (!widget.active) widget.otherChild,
      ],
    );
  }
}
