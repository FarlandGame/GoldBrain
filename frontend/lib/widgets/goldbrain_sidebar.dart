import 'dart:io';

import 'package:flutter/material.dart';

import '../screens/selection_screen.dart';
import '../core/motion_preferences.dart';

class GoldBrainSidebarItem {
  const GoldBrainSidebarItem({
    required this.icon,
    required this.label,
    this.badge,
  });

  final IconData icon;
  final String label;
  final String? badge;
}

class GoldBrainSidebar extends StatelessWidget {
  const GoldBrainSidebar({
    super.key,
    required this.palette,
    required this.items,
    required this.selectedIndex,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onSelected,
    this.onHover,
    required this.profileName,
    required this.profileSubtitle,
    required this.profileImagePath,
    this.compactLandscape = false,
  });

  final ThemePalette palette;
  final List<GoldBrainSidebarItem> items;
  final int selectedIndex;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<int> onSelected;
  final VoidCallback? onHover;
  final String profileName;
  final String profileSubtitle;
  final String profileImagePath;
  final bool compactLandscape;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: MotionPreferences.duration(420),
      curve: Curves.easeOutExpo,
      width: compactLandscape ? 66 : (expanded ? 250 : 84),
      padding: EdgeInsets.fromLTRB(
        compactLandscape ? 3 : (expanded ? 10 : 4),
        compactLandscape ? 7 : 14,
        compactLandscape ? 3 : (expanded ? 10 : 4),
        compactLandscape ? 7 : 12,
      ),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: palette.primary.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(
            color: palette.primary.withValues(alpha: 0.08),
            blurRadius: 38,
            spreadRadius: 2,
          ),
          const BoxShadow(
            color: Colors.black45,
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Keep the compact content until the animated width is large enough.
          // Switching all children immediately used to overflow during toggles.
          final contentExpanded = constraints.maxWidth >= 170;

          return Column(
            children: [
              if (compactLandscape)
                Semantics(
                  label: 'GoldBrain',
                  image: true,
                  child: Container(
                    key: const ValueKey('mobile-landscape-sidebar-brand'),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [palette.primary, palette.secondary],
                      ),
                    ),
                    child: Icon(
                      Icons.psychology_alt_rounded,
                      color: palette.isLight ? Colors.white : Colors.black,
                      size: 23,
                    ),
                  ),
                )
              else
                _SidebarBrand(
                  palette: palette,
                  expanded: contentExpanded,
                  onToggleExpanded: onToggleExpanded,
                ),
              SizedBox(height: compactLandscape ? 6 : 22),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  physics: const BouncingScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (context, index) {
                    return SizedBox(height: compactLandscape ? 3 : 7);
                  },
                  itemBuilder: (context, index) {
                    return _SidebarButton(
                      key: ValueKey('sidebar-item-$index'),
                      palette: palette,
                      item: items[index],
                      selected: selectedIndex == index,
                      expanded: contentExpanded,
                      dense: compactLandscape,
                      onTap: () => onSelected(index),
                      onHover: onHover,
                    );
                  },
                ),
              ),
              if (!compactLandscape) ...[
                const SizedBox(height: 10),
                _SidebarProfile(
                  palette: palette,
                  expanded: contentExpanded,
                  name: profileName,
                  subtitle: profileSubtitle,
                  imagePath: profileImagePath,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand({
    required this.palette,
    required this.expanded,
    required this.onToggleExpanded,
  });

  final ThemePalette palette;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return SizedBox(
        height: 54,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [palette.primary, palette.secondary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.primary.withValues(alpha: 0.34),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Icon(
                Icons.psychology_alt_rounded,
                color: palette.isLight ? Colors.white : Colors.black,
                size: 25,
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Transform.scale(
                scale: 0.78,
                child: _SidebarToggleButton(
                  palette: palette,
                  expanded: expanded,
                  onTap: onToggleExpanded,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 54,
      child: Row(
        textDirection: TextDirection.ltr,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [palette.primary, palette.secondary],
              ),
              boxShadow: [
                BoxShadow(
                  color: palette.primary.withValues(alpha: 0.34),
                  blurRadius: 22,
                ),
              ],
            ),
            child: Icon(
              Icons.psychology_alt_rounded,
              color: palette.isLight ? Colors.white : Colors.black,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRect(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GOLDBRAIN',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'NEURAL TERMINAL',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: palette.primary,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _SidebarToggleButton(
            palette: palette,
            expanded: expanded,
            onTap: onToggleExpanded,
          ),
        ],
      ),
    );
  }
}

class _SidebarToggleButton extends StatefulWidget {
  const _SidebarToggleButton({
    required this.palette,
    required this.expanded,
    required this.onTap,
  });

  final ThemePalette palette;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_SidebarToggleButton> createState() {
    return _SidebarToggleButtonState();
  }
}

class _SidebarToggleButtonState extends State<_SidebarToggleButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() {
          hovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          hovered = false;
        });
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: MotionPreferences.duration(220),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: widget.palette.primary.withValues(
              alpha: hovered ? 0.15 : 0.07,
            ),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: widget.palette.primary.withValues(
                alpha: hovered ? 0.48 : 0.18,
              ),
            ),
          ),
          child: AnimatedRotation(
            duration: MotionPreferences.duration(420),
            curve: Curves.easeOutExpo,
            turns: widget.expanded ? 0 : 0.5,
            child: Icon(
              Icons.keyboard_double_arrow_left_rounded,
              color: hovered
                  ? widget.palette.secondary
                  : widget.palette.mutedText,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarButton extends StatefulWidget {
  const _SidebarButton({
    super.key,
    required this.palette,
    required this.item,
    required this.selected,
    required this.expanded,
    this.dense = false,
    required this.onTap,
    this.onHover,
  });

  final ThemePalette palette;
  final GoldBrainSidebarItem item;
  final bool selected;
  final bool expanded;
  final bool dense;
  final VoidCallback onTap;
  final VoidCallback? onHover;

  @override
  State<_SidebarButton> createState() {
    return _SidebarButtonState();
  }
}

class _SidebarButtonState extends State<_SidebarButton> {
  bool hovered = false;
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        widget.onHover?.call();
        setState(() {
          hovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          hovered = false;
          pressed = false;
        });
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          setState(() {
            pressed = true;
          });
        },
        onTapCancel: () {
          setState(() {
            pressed = false;
          });
        },
        onTapUp: (_) {
          setState(() {
            pressed = false;
          });

          widget.onTap();
        },
        child: AnimatedScale(
          duration: MotionPreferences.duration(160),
          scale: pressed ? 0.97 : 1,
          child: AnimatedContainer(
            duration: MotionPreferences.duration(280),
            curve: Curves.easeOutCubic,
            height: widget.dense ? 42 : 52,
            padding: EdgeInsets.symmetric(
              horizontal: widget.expanded ? 12 : (widget.dense ? 6 : 9),
            ),
            decoration: BoxDecoration(
              color: widget.selected
                  ? widget.palette.primary.withValues(alpha: 0.13)
                  : widget.palette.text.withValues(
                      alpha: hovered ? 0.055 : 0.012,
                    ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.selected
                    ? widget.palette.primary.withValues(alpha: 0.62)
                    : hovered
                    ? widget.palette.primary.withValues(alpha: 0.28)
                    : Colors.transparent,
              ),
              boxShadow: [
                if (widget.selected)
                  BoxShadow(
                    color: widget.palette.primary.withValues(alpha: 0.15),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                SizedBox(
                  width: widget.dense ? 34 : 38,
                  height: widget.dense ? 34 : 38,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (widget.selected)
                        Container(
                          width: widget.dense ? 30 : 34,
                          height: widget.dense ? 30 : 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.palette.primary.withValues(
                              alpha: 0.10,
                            ),
                          ),
                        ),
                      Icon(
                        widget.item.icon,
                        color: widget.selected
                            ? widget.palette.secondary
                            : hovered
                            ? widget.palette.primary
                            : widget.palette.mutedText,
                        size: widget.dense ? 21 : 23,
                      ),
                    ],
                  ),
                ),
                if (widget.expanded) ...[
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      widget.item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.selected
                            ? widget.palette.text
                            : widget.palette.mutedText,
                        fontSize: 13,
                        fontWeight: widget.selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.item.badge != null)
                    Container(
                      constraints: const BoxConstraints(minWidth: 24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: widget.palette.primary.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        widget.item.badge!,
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          color: widget.palette.secondary,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return Semantics(
      container: true,
      button: true,
      selected: widget.selected,
      label: widget.item.label,
      child: button,
    );
  }
}

class _SidebarProfile extends StatelessWidget {
  const _SidebarProfile({
    required this.palette,
    required this.expanded,
    required this.name,
    required this.subtitle,
    required this.imagePath,
  });

  final ThemePalette palette;
  final bool expanded;
  final String name;
  final String subtitle;
  final String imagePath;

  bool get hasValidImage {
    if (imagePath.trim().isEmpty) {
      return false;
    }

    try {
      return File(imagePath).existsSync();
    } catch (_) {
      return false;
    }
  }

  Widget _buildDefaultAvatar() {
    return Container(
      color: palette.primary,
      alignment: Alignment.center,
      child: Icon(
        Icons.person_rounded,
        color: palette.isLight ? Colors.white : Colors.black,
        size: 22,
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            palette.primary.withValues(alpha: 0.86),
            palette.secondary.withValues(alpha: 0.78),
          ],
        ),
        border: Border.all(color: palette.primary.withValues(alpha: 0.38)),
        boxShadow: [
          BoxShadow(
            color: palette.primary.withValues(alpha: 0.17),
            blurRadius: 14,
          ),
        ],
      ),
      padding: const EdgeInsets.all(2),
      child: ClipOval(
        child: hasValidImage
            ? Image.file(
                File(imagePath),
                key: ValueKey(imagePath),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) {
                  return _buildDefaultAvatar();
                },
              )
            : _buildDefaultAvatar(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shownName = name.trim().isEmpty ? 'GoldBrain User' : name.trim();

    return AnimatedContainer(
      duration: MotionPreferences.duration(320),
      height: 58,
      padding: EdgeInsets.symmetric(horizontal: expanded ? 9 : 5),
      decoration: BoxDecoration(
        color: palette.text.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: palette.text.withValues(alpha: 0.07)),
      ),
      child: Row(
        textDirection: TextDirection.ltr,
        mainAxisAlignment: expanded
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          _buildAvatar(),
          if (expanded) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shownName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF43E394),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
