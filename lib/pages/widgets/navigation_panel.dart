import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../services/routing_service.dart';
import '../../services/voice_guidance_service.dart';

/// High-level navigation instruction panel shown at the top of the map.
/// Includes the current turn instruction, distance-to-next-turn indicator,
/// lane guidance, route overview toggle, and next step preview.
class NavigationPanel extends StatelessWidget {
  final NavigationStep currentStep;
  final bool hasNext;
  final NavigationStep? nextStep;
  final List<NavigationStep> navigationSteps;
  final int currentStepIndex;
  final double remainingDistance;
  final int remainingDuration;
  final double distToNextTurn;
  final double distToStepEnd;
  final double turnProgress;
  final Color turnProgressColor;
  final bool showRouteOverview;
  final String Function() formatTurnDistance;
  final VoidCallback onToggleVoice;
  final VoidCallback onToggleRouteOverview;
  final Widget Function() buildRouteOverview;

  const NavigationPanel({
    super.key,
    required this.currentStep,
    required this.hasNext,
    required this.nextStep,
    required this.navigationSteps,
    required this.currentStepIndex,
    required this.remainingDistance,
    required this.remainingDuration,
    required this.distToNextTurn,
    required this.distToStepEnd,
    required this.turnProgress,
    required this.turnProgressColor,
    required this.formatTurnDistance,
    required this.showRouteOverview,
    required this.onToggleVoice,
    required this.onToggleRouteOverview,
    required this.buildRouteOverview,
  });

  @override
  Widget build(BuildContext context) {
    final voiceService = Get.find<VoiceGuidanceService>();

    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 64,
        left: 16,
        right: 16,
      ),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main instruction row
              _buildInstructionRow(voiceService),
              // Distance to next turn + remaining progress
              if (remainingDistance > 0) ...[
                const SizedBox(height: 12),
                _buildDistanceIndicator(voiceService),
              ],
              // Lane guidance
              if (hasNext && distToNextTurn < 500 && nextStep != null)
                _buildLaneGuidance(nextStep!),
              // Route overview toggle
              _buildRouteOverviewToggle(),
              // Route overview content
              if (showRouteOverview) buildRouteOverview(),
              // Next step preview
              if (nextStep != null) ...[
                const Divider(height: 16),
                Row(
                  children: [
                    Icon(
                      nextStep!.maneuverIcon,
                      size: 16,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Next: ${nextStep!.cleanInstruction}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionRow(VoiceGuidanceService voiceService) {
    return Row(
      children: [
        // Maneuver icon
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF10713C).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            currentStep.maneuverIcon,
            color: const Color(0xFF10713C),
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        // Instruction text
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentStep.cleanInstruction,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${currentStep.distance.toStringAsFixed(1)} km  ·  ${currentStep.duration.ceil()} min',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        // Voice toggle
        Obx(() => GestureDetector(
          onTap: onToggleVoice,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: voiceService.isVoiceEnabled.value
                  ? const Color(0xFF10713C).withOpacity(0.1)
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              voiceService.isVoiceEnabled.value
                  ? Icons.volume_up
                  : Icons.volume_off,
              size: 20,
              color: voiceService.isVoiceEnabled.value
                  ? const Color(0xFF10713C)
                  : Colors.grey[500],
            ),
          ),
        )),
        const SizedBox(width: 8),
        // Step counter
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${currentStepIndex + 1}/${navigationSteps.length}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDistanceIndicator(VoiceGuidanceService voiceService) {
    return Row(
      children: [
        // Circular progress ring
        SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  value: turnProgress,
                  strokeWidth: 3.5,
                  backgroundColor: Colors.grey[200],
                  color: turnProgressColor,
                  strokeCap: StrokeCap.round,
                ),
              ),
              Icon(
                hasNext
                    ? (nextStep?.maneuverIcon ?? Icons.turn_slight_right)
                    : Icons.flag,
                size: 16,
                color: turnProgressColor,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Distance text
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasNext ? 'Next turn' : 'Destination',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              const SizedBox(height: 2),
              Text(
                formatTurnDistance(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // Compact remaining distance / time
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                Icon(Icons.route, size: 12, color: Colors.grey[400]),
                const SizedBox(width: 3),
                Text(
                  '${remainingDistance.toStringAsFixed(1)} km',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700]),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.access_time, size: 12, color: Colors.grey[400]),
                const SizedBox(width: 3),
                Text(
                  '$remainingDuration min',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRouteOverviewToggle() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: onToggleRouteOverview,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                showRouteOverview ? Icons.map : Icons.map_outlined,
                size: 16,
                color: const Color(0xFF10713C),
              ),
              const SizedBox(width: 6),
              Text(
                showRouteOverview ? 'Hide route overview' : 'Route overview',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF10713C),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Icon(
                showRouteOverview ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: Colors.grey[500],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Determine which lanes to recommend based on the upcoming maneuver.
  static List<bool> getSuggestedLanes(NavigationStep step, {int laneCount = 3}) {
    final List<bool> recommended = List.filled(laneCount, false);

    switch (step.maneuver) {
      case 'turn-left':
      case 'turn-sharp-left':
        recommended[0] = true;
        break;
      case 'turn-right':
      case 'turn-sharp-right':
        recommended[laneCount - 1] = true;
        break;
      case 'straight':
      case 'merge':
        recommended[1] = true;
        break;
      case 'fork-left':
      case 'ramp-left':
        recommended[0] = true;
        recommended[1] = true;
        break;
      case 'fork-right':
      case 'ramp-right':
        recommended[1] = true;
        recommended[laneCount - 1] = true;
        break;
      case 'roundabout-left':
        recommended[0] = true;
        break;
      case 'roundabout-right':
        recommended[laneCount - 1] = true;
        break;
      default:
        for (int i = 0; i < laneCount; i++) recommended[i] = true;
    }
    return recommended;
  }

  /// Build the lane guidance visualization widget
  Widget _buildLaneGuidance(NavigationStep step) {
    final lanes = getSuggestedLanes(step);
    final turnIcon = step.maneuverIcon;

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.drive_eta, size: 13, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(
                'Stay in suggested lane',
                style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < lanes.length; i++) ...[
                  if (i > 0)
                    Container(
                      width: 1,
                      height: 42,
                      color: Colors.grey[300],
                    ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: lanes[i]
                          ? const Color(0xFF10713C).withOpacity(0.15)
                          : Colors.grey[50],
                      border: Border.all(
                        color: lanes[i]
                            ? const Color(0xFF10713C)
                            : Colors.grey[300]!,
                        width: lanes[i] ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: lanes[i]
                        ? Icon(
                            i == 0
                                ? Icons.arrow_left
                                : i == lanes.length - 1
                                    ? Icons.arrow_right
                                    : Icons.north,
                            size: 18,
                            color: const Color(0xFF10713C),
                          )
                        : null,
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(turnIcon, size: 20, color: const Color(0xFF10713C)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
