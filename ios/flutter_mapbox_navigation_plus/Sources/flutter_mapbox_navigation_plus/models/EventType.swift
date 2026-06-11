import Foundation

/// Event names emitted to the Flutter side. The raw string of each case must
/// stay in sync with `MapBoxEvent` in `lib/src/models/events.dart`.
enum MapBoxEventType: String, Codable
{
    case map_ready
    case route_building
    case route_built
    case route_build_failed
    case progress_change
    case user_off_route
    case milestone_event
    case navigation_running
    case navigation_cancelled
    case navigation_finished
    case faster_route_found
    case speech_announcement
    case banner_instruction
    case on_arrival
    case failed_to_reroute
    case reroute_along
    case on_map_tap
    case standardPoiTapped
    case standardBuildingTapped
    case mapStyleLoaded
    case camera_state_changed
    // Offline maps & routing (parity with the Android v3 implementation).
    case offline_region_progress
    case offline_region_complete
    case offline_region_error
    case offline_region_removed
}
