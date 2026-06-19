import Foundation
import MapboxDirections
import MapboxNavigationCore

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
    }
}
