import Foundation
import MapboxDirections
import MapboxNavigationCore

/// One lane of the road, as the navigation banner describes it.
///
/// Approaching a junction the Directions API lists the lanes left to right,
/// which turns are painted in each, and which of them can be used for the
/// manoeuvre coming up. Empty for most of a route.
///
/// Kept at parity with the Android side's `lanesFrom`: same field names, same
/// direction vocabulary, so one Dart model reads both.
public struct MapBoxLaneGuidance : Codable
{
    let directions: [String]
    let active: Bool
    let activeDirection: String
}

public class MapBoxRouteProgressEvent : Codable
{
    let arrived: Bool
    let distance: Double
    let duration: Double
    let distanceTraveled: Double
    let currentLegDistanceTraveled: Double
    let currentLegDistanceRemaining: Double
    let currentStepInstruction: String
    let legIndex: Int
    let stepIndex: Int
    let currentLeg: MapBoxRouteLeg
    var priorLeg: MapBoxRouteLeg? = nil
    var remainingLegs: [MapBoxRouteLeg] = []
    let currentSpeed: Double
    let maneuverType: String
    let maneuverModifier: String
    let upcomingInstruction: String
    let currentRoadName: String
    let upcomingRoadName: String
    // Posted speed limit in km/h, or 0 when unknown.
    let speedLimit: Double
    // Lanes of the road ahead, left to right. Empty away from a junction.
    var lanes: [MapBoxLaneGuidance] = []

    init(progress: RouteProgress, currentSpeed: Double = 0.0) {

        // CLLocation.speed is negative when the value is invalid; clamp to 0.
        self.currentSpeed = currentSpeed < 0 ? 0.0 : currentSpeed
        arrived = progress.isFinalLeg && progress.currentLegProgress.userHasArrivedAtWaypoint
        distance = progress.distanceRemaining
        distanceTraveled = progress.distanceTraveled
        duration = progress.durationRemaining
        legIndex = progress.legIndex
        stepIndex = progress.currentLegProgress.stepIndex

        currentLeg = MapBoxRouteLeg(leg: progress.currentLeg)

        if(progress.priorLeg != nil)
        {
            priorLeg = MapBoxRouteLeg(leg: progress.priorLeg!)
        }

        for leg in progress.remainingLegs
        {
            remainingLegs.append(MapBoxRouteLeg(leg: leg))
        }

        currentLegDistanceTraveled = progress.currentLegProgress.distanceTraveled
        currentLegDistanceRemaining = progress.currentLegProgress.distanceRemaining
        currentStepInstruction = progress.currentLegProgress.currentStep.description
        maneuverType = progress.currentLegProgress.currentStep.maneuverType.rawValue
        maneuverModifier = progress.currentLegProgress.currentStep.maneuverDirection?.rawValue ?? ""
        upcomingInstruction = progress.currentLegProgress.upcomingStep?.instructions ?? ""
        currentRoadName = progress.currentLegProgress.currentStep.names?.first ?? ""
        upcomingRoadName = progress.currentLegProgress.upcomingStep?.names?.first ?? ""
        if let limit = progress.currentLegProgress.currentSpeedLimit {
            speedLimit = limit.converted(to: .kilometersPerHour).value
        } else {
            speedLimit = 0
        }

        // Lane guidance rides in the tertiary instruction, which is where the
        // Directions API puts the sub-banner Android reads for the same thing.
        // Absent away from a junction, which is most of the route.
        if let components = progress
            .currentLegProgress
            .currentStepProgress
            .currentVisualInstruction?
            .tertiaryInstruction?
            .components
        {
            for component in components {
                guard case let .lane(indications, isUsable, preferredDirection) = component
                else { continue }

                lanes.append(
                    MapBoxLaneGuidance(
                        directions: MapBoxRouteProgressEvent.directions(from: indications),
                        active: isUsable,
                        activeDirection: preferredDirection?.rawValue ?? ""
                    )
                )
            }
        }
    }

    /// The turns painted in a lane, in the same words Android sends so a single
    /// Dart model can read either platform.
    private static func directions(from indications: LaneIndication) -> [String] {
        var directions: [String] = []

        if indications.contains(.sharpLeft) { directions.append("sharp left") }
        if indications.contains(.left) { directions.append("left") }
        if indications.contains(.slightLeft) { directions.append("slight left") }
        if indications.contains(.straightAhead) { directions.append("straight") }
        if indications.contains(.slightRight) { directions.append("slight right") }
        if indications.contains(.right) { directions.append("right") }
        if indications.contains(.sharpRight) { directions.append("sharp right") }
        if indications.contains(.uTurn) { directions.append("uturn") }

        return directions
    }
}
