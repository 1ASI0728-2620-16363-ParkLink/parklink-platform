import 'package:flutter/material.dart';

import '../../../../../domain/models/admin_records.dart';
import '../../../../core/app_theme.dart';
import 'dashboard_common.dart';

class SentInvitationsSection extends StatefulWidget {
  const SentInvitationsSection({required this.invitations, super.key});

  final List<InvitationRecord> invitations;

  @override
  State<SentInvitationsSection> createState() => _SentInvitationsSectionState();
}

class _SentInvitationsSectionState extends State<SentInvitationsSection> {
  bool _isExpanded = false;

  @override
  void didUpdateWidget(covariant SentInvitationsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.invitations.length <= 1) _isExpanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final canExpand = widget.invitations.length > 1;
    final isExpanded = canExpand && _isExpanded;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 300);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final cardHeight = 82.0 + ((textScale - 1).clamp(0.0, 2.0) * 22).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InvitationsHeader(
          canExpand: canExpand,
          isExpanded: isExpanded,
          duration: duration,
          onToggle: _toggleExpanded,
        ),
        const SizedBox(height: 12),
        if (widget.invitations.isEmpty)
          const DashboardEmptyState(message: 'No hay invitaciones enviadas')
        else
          AnimatedSize(
            alignment: Alignment.topCenter,
            duration: duration,
            curve: Curves.easeInOutCubic,
            child: AnimatedSwitcher(
              duration: duration,
              switchInCurve: Curves.easeInOutCubic,
              switchOutCurve: Curves.easeInOutCubic,
              child: KeyedSubtree(
                key: ValueKey(isExpanded),
                child: _buildInvitations(
                  isExpanded: isExpanded,
                  cardHeight: cardHeight,
                  duration: duration,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInvitations({
    required bool isExpanded,
    required double cardHeight,
    required Duration duration,
  }) {
    if (widget.invitations.length == 1) {
      return _InvitationCard(
        invitation: widget.invitations.first,
        height: cardHeight,
        duration: duration,
      );
    }

    if (isExpanded) {
      return Column(
        children: [
          for (var index = 0; index < widget.invitations.length; index++) ...[
            _InvitationCard(
              key: ValueKey(widget.invitations[index].id),
              invitation: widget.invitations[index],
              height: cardHeight,
              duration: duration,
              onTap: index == 0 ? _toggleExpanded : null,
              semanticHint: index == 0
                  ? 'Toca dos veces para contraer las invitaciones'
                  : null,
            ),
            if (index != widget.invitations.length - 1)
              const SizedBox(height: 8),
          ],
        ],
      );
    }

    return _CollapsedInvitationStack(
      invitations: widget.invitations,
      cardHeight: cardHeight,
      duration: duration,
      onToggle: _toggleExpanded,
    );
  }

  void _toggleExpanded() {
    if (widget.invitations.length <= 1) return;
    setState(() => _isExpanded = !_isExpanded);
  }
}

class _InvitationsHeader extends StatelessWidget {
  const _InvitationsHeader({
    required this.canExpand,
    required this.isExpanded,
    required this.duration,
    required this.onToggle,
  });

  final bool canExpand;
  final bool isExpanded;
  final Duration duration;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final stateLabel = isExpanded ? 'expandida' : 'contraída';

    return Semantics(
      container: true,
      excludeSemantics: true,
      header: true,
      button: canExpand,
      expanded: canExpand ? isExpanded : null,
      label: canExpand
          ? 'Invitaciones enviadas, $stateLabel'
          : 'Invitaciones enviadas',
      hint: canExpand ? 'Toca dos veces para cambiar la vista' : null,
      onTap: canExpand ? onToggle : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canExpand ? onToggle : null,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Invitaciones enviadas',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (canExpand)
                  SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: duration,
                        curve: Curves.easeInOutCubic,
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: appDashboardTextMuted,
                        ),
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

class _CollapsedInvitationStack extends StatelessWidget {
  const _CollapsedInvitationStack({
    required this.invitations,
    required this.cardHeight,
    required this.duration,
    required this.onToggle,
  });

  static const _layerStripHeight = 12.0;

  final List<InvitationRecord> invitations;
  final double cardHeight;
  final Duration duration;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final visibleInvitations = invitations.take(4).toList();
    final rearLayerCount = visibleInvitations.length - 1;
    final layers = <Widget>[];

    for (
      var invitationIndex = visibleInvitations.length - 1;
      invitationIndex >= 0;
      invitationIndex--
    ) {
      final isFront = invitationIndex == 0;
      final top = (rearLayerCount - invitationIndex) * _layerStripHeight;
      final inset = switch (invitationIndex) {
        0 => 0.0,
        1 => 6.0,
        2 => 11.0,
        _ => 8.0,
      };
      final card = _InvitationCard(
        invitation: visibleInvitations[invitationIndex],
        height: cardHeight,
        duration: duration,
        isRearLayer: !isFront,
        onTap: isFront ? onToggle : null,
        semanticHint: isFront
            ? 'Toca dos veces para mostrar todas las invitaciones'
            : null,
      );

      layers.add(
        AnimatedPositioned(
          key: ValueKey(visibleInvitations[invitationIndex].id),
          duration: duration,
          curve: Curves.easeInOutCubic,
          top: top,
          left: inset,
          right: inset,
          height: cardHeight,
          child: isFront ? card : ExcludeSemantics(child: card),
        ),
      );
    }

    return SizedBox(
      height: cardHeight + rearLayerCount * _layerStripHeight,
      child: Stack(children: layers),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.height,
    required this.duration,
    this.isRearLayer = false,
    this.onTap,
    this.semanticHint,
    super.key,
  });

  final InvitationRecord invitation;
  final double height;
  final Duration duration;
  final bool isRearLayer;
  final VoidCallback? onTap;
  final String? semanticHint;

  @override
  Widget build(BuildContext context) {
    final name = invitation.driverName?.trim();
    final hasName = name != null && name.isNotEmpty;
    final primaryLabel = hasName ? name : invitation.email;
    final status = _invitationStatus(invitation.status);
    final semanticLabel = hasName
        ? '$primaryLabel, ${invitation.email}, ${status.label}'
        : '$primaryLabel, ${status.label}';

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: onTap != null,
      label: semanticLabel,
      hint: semanticHint,
      onTap: onTap,
      child: AnimatedContainer(
        height: height,
        duration: duration,
        curve: Curves.easeInOutCubic,
        decoration: BoxDecoration(
          color: isRearLayer ? appDashboardCardSoft : appDashboardCard,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: appDashboardBorder),
        ),
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          primaryLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: appWhite,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (hasName) ...[
                          const SizedBox(height: 3),
                          Text(
                            invitation.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: appDashboardTextMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _InvitationStatusPill(status: status),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InvitationStatusPill extends StatelessWidget {
  const _InvitationStatusPill({required this.status});

  final _InvitationStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: status.foreground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              status.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: status.foreground,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _InvitationStatus = ({
  String label,
  Color background,
  Color foreground,
});

_InvitationStatus _invitationStatus(String rawStatus) {
  final status = rawStatus.toUpperCase();

  if (status == 'ACCEPTED' || status == 'ACTIVE') {
    return (
      label: status == 'ACTIVE' ? 'Activa' : 'Aceptada',
      background: appLime,
      foreground: appBlack,
    );
  }
  if (status == 'PENDING') {
    return (
      label: 'Pendiente',
      background: appDashboardLight,
      foreground: appBlack,
    );
  }

  return (
    label: switch (status) {
      'EXPIRED' => 'Expirada',
      'CANCELLED' || 'CANCELED' => 'Cancelada',
      _ => rawStatus,
    },
    background: appDashboardTrack,
    foreground: appDashboardTextMuted,
  );
}
