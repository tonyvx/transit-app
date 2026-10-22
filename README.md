# Boston Transit

Native SwiftUI iOS app (iOS 17+) with no backend. It calls the MBTA V3 API directly and matches your own GPS to a train on the device. Location never leaves the phone.

## Features
- Live map of Commuter Rail, Red, Orange, Blue, Green and Silver Line vehicles, with line and direction chips.
- Preferences for lines, routes and branches, directions, and only trains that haven't passed you.
- Station arrivals per train, and a halo on a train you pick.
- MBTA alerts grouped by relevance, with drive time to lines that start ahead of you.
- On-device "you're probably on train X" matching.
- Trip planner with transfers and walk, bike, scooter or car access legs (see below).

## Favorites, reminders and widget
- Star a station in its sheet to add it to your favorites. Save a planned trip and give it a weekday reminder. Tap "Remind me to leave" on a trip for a one-off notification. Reminders are local and don't react to delays.
- Add the "Next trains" widget (small, medium, lock screen) to see live departures at your first two favorites. Favorites are shared with the widget through the App Group `group.com.tonyvx.transitapp`.

## Tests
`cd ios && xcodegen generate`, then run the `TransitApp` scheme's tests in Xcode (Cmd+U), or:
`xcodebuild test -project TransitApp.xcodeproj -scheme TransitApp -destination 'platform=iOS Simulator,name=iPhone 17'`

They cover the trip router (direct rides, transfers, walking transfers, direction, cost), the GPS train matcher, the line, route, branch, direction and "approaching" vehicle filter, and the access-mode estimates. They don't call the network.

## Roadmap
- Opt-in GPS sharing and manual stoppage and crowding reports, pooled across riders. This needs a shared store (own backend or CloudKit) and "Always" location access, and the privacy text and App Store privacy answers must change with it.
- Provider interface (`TransitProvider`) to support other cities. In-app MBTA strings would then come from the provider.
- Later: crowd-aware arrival predictions, stoppage detection, train-specific alerts, reliability statistics and departure recommendations.

## Before releasing
- Regenerate the MBTA API key, since it ships in the app bundle.
- Publish a privacy policy and fill in the App Privacy answers.
- Check the MBTA developer terms for attribution (the app credits the MBTA under Preferences, About and privacy).
- A personal signing team expires the profile every 7 days and can't use TestFlight or the App Store.

## Run
1. `cd ios && cp Secrets.example.xcconfig Secrets.xcconfig` and put your MBTA key in it (git-ignored).
2. `xcodegen generate && open TransitApp.xcodeproj`.

## Limits of the no-backend design
- The MBTA key is embedded in the app bundle, so it can be extracted.
- No crowdsourcing across riders and no shared stoppage/crowding reports; those need a shared store (own backend or CloudKit).

`backend/` holds the earlier server-based design (rider GPS pooling, reports). It is not used by the app.

## Trip planner

Tap the route icon in the chip row. Set a start and destination by searching, using your location, or dropping a pin on the map. Choose how you get to the first station and from the last one (walk, bike, scooter or car). Pick Leave now, Depart at or Arrive by (any day the MBTA has published schedules for). The planner finds up to three trips, including transfers, using live MBTA predictions where they exist (marked Live, with the delay) and scheduled times otherwise, and draws the selected one on the map.

The MBTA has no trip-planner API, so routing runs on-device over the MBTA schedule data. Walk and car legs use Apple Maps. Bike and scooter legs are estimated from the walking distance at typical speeds. Parking and bike facilities are not considered.
