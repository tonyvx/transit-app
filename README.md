# Boston Transit

Native SwiftUI iOS app (iOS 17+) with no backend. It calls the MBTA V3 API directly and matches your own GPS to a train on the device. Location never leaves the phone.

## Features
- Live map of Commuter Rail, Red, Orange, Blue, Green and Silver Line vehicles, with every route drawn on the map. Tap a route for its details and to favorite it.
- A settings drawer (gear icon) with specific favorite routes and branches, directions, only trains that haven't passed you, trip tracking, favorite stations, feedback, terms and MBTA information. Direction and approaching-train settings save as soon as they change.
- Alerts grouped by direction for selected favorite routes and branches and colored by line; other lines are collapsed.
- Works offline-tolerantly: route shapes are cached on the phone for a week, polling stops in the background, and the map shows a banner when the connection drops.
- Station arrivals per train, and a halo on a train you pick.
- MBTA alerts grouped by relevance, with drive time to lines that start ahead of you.
- On-device "you're probably on train X" matching.
- Trip planner with transfers and walk, drive, scooter or bike station legs. Locations are searched as you leave each field, trips are found when both endpoints are ready, and GO retries the search. Results include estimated miles per leg and for the trip.
- Collapsible saved trips and a map toggle to hide routes and trains not used by the selected trip.
- Optional trip confirmation when your GPS and the live MBTA train match a selected itinerary. A Lock Screen Live Activity tracks the next stop and stops to disembarkment; background GPS requires opt-in Always access and stays on the phone.
- Feedback, how-to guide, a Terms & Policy popup and MBTA information in the settings drawer.

## Favorites, reminders and widget
- Star a station in its sheet to add it to your favorites. Save a planned trip and give it a weekday reminder. Tap "Remind me to leave" on a trip for a one-off notification. Reminders are local and don't react to delays.
- Add the "Next trains" widget (small, medium, lock screen) to see live departures at your first two favorites. Favorites are shared with the widget through the App Group `group.com.tonyvx.transitapp`.

## Tests
`cd ios && xcodegen generate`, then run the `TransitApp` scheme's tests in Xcode (Cmd+U), or:
`xcodebuild test -project TransitApp.xcodeproj -scheme TransitApp -destination 'platform=iOS Simulator,name=iPhone 17'`

Unit tests cover the trip router (direct rides, transfers, walking transfers, direction, cost), the GPS train matcher, trip boarding confirmation, stop progression, map and vehicle filters, access-mode and distance estimates, live predictions, arrive-by and favorites. Unit tests use fake providers; UI tests may use live location search and MBTA data.

## Roadmap
- Opt-in GPS sharing and manual stoppage and crowding reports, pooled across riders. This needs a shared store (own backend or CloudKit); the on-device trip tracking feature does not share location.
- Provider interface (`TransitProvider`) to support other cities. In-app MBTA strings would then come from the provider.
- Later: crowd-aware arrival predictions, stoppage detection, train-specific alerts, reliability statistics and departure recommendations.

## Before releasing
- Regenerate the MBTA API key, since it ships in the app bundle.
- Publish a privacy policy and fill in the App Privacy answers.
- Check the MBTA developer terms for attribution (the app credits the MBTA in Terms & Policy).
- A personal signing team expires the profile every 7 days and can't use TestFlight or the App Store.
- Finish real-device checks for trip confirmation, background location, Live Activity, reminders and the widget; then prepare the App Store screenshots and TestFlight build.

## App Store launch and pricing

The listing draft in [`docs/appstore/listing.md`](docs/appstore/listing.md) currently proposes a **free** launch. This is a recommendation to validate, not a final pricing decision.

### Suggested 1.0 approach
- Keep the core app free at launch, with no subscription or paywall. The current product is an on-device MBTA utility with no ongoing backend service, and keeping trip planning, live information and accessibility-independent basics available lowers the barrier to trying it.
- Use TestFlight and rider feedback to learn which features people rely on before adding a paid tier. Do not treat downloads alone as evidence that a subscription is worthwhile.
- Revisit monetization if the product adds meaningful ongoing costs or services, such as shared crowdsourcing, push alerts, historical reliability data or multi-city coverage.

### Options to revisit
- **Optional one-time tip:** a low-friction way for users to support development, without restricting core transit features.
- **One-time Pro unlock:** only if a clearly separable set of durable premium features emerges; avoid splitting essential real-time or trip-planning capabilities.
- **Subscription:** consider only if there is continuing value and operating cost to support it (for example, hosted crowd data and server-driven alerts). The current app does not provide those services.
- **Paid upfront:** possible, but not the recommended first-release choice for a new local transit utility; it adds friction before riders can assess its usefulness.

Before deciding, compare similar transit apps and their current prices in the target storefront, validate willingness to pay with riders, and account for Apple’s program and payment terms, taxes, and any future hosting costs. Update the listing price and any in-app purchase disclosures together when the decision is made.

## Run
1. `cd ios && cp Secrets.example.xcconfig Secrets.xcconfig` and put your MBTA key in it (git-ignored).
2. `xcodegen generate && open TransitApp.xcodeproj`.

## Limits of the no-backend design
- The MBTA key is embedded in the app bundle, so it can be extracted.
- No crowdsourcing across riders and no shared stoppage/crowding reports; those need a shared store (own backend or CloudKit).

`backend/` holds the earlier server-based design (rider GPS pooling, reports). It is not used by the app.

## Trip planner

Tap the trip summary at the top of the map. Expand **Saved trips (count)** to load or manage a saved trip and its weekday reminder. Choose Walk, Drive, Scooter or Bike above the addresses to set both station legs, or use the mode icon at the right of either address to override that leg.

Enter a start and destination; leaving a field or pressing Search looks up the location, and the planner automatically finds trips when both locations are ready. Each row also has buttons for using your current location or dropping a pin. Tap **GO** to retry or replan, **Swap** to reverse the endpoints, or **Clear** to reset the form and remove the route and markers. Choose Leave now, Depart at or Arrive by (any day the MBTA has published schedules for), then tap GO after changing the time.

The planner finds up to three trips with transfers, using live MBTA predictions where available (marked Live, with the delay) and scheduled times otherwise. Each trip shows its total duration and estimated miles; expanded results show times, duration and estimated miles for each leg. Transit distances sum straight lines between stops; transfer distances are approximations, and walk/drive access distances use Apple Maps where available. Bike and scooter legs use walking distance at typical speeds. Totals include all legs and are unavailable if a leg's distance is unavailable.

The selected trip is drawn on the map while other lines fade. Use **Hide other lines** at the bottom left to hide other routes and trains, fade the unused portions of trip routes, and show only saved-line station markers on the trip. The app highlights the matching route shape between the trip's stops where available; otherwise it uses straight lines between stops. Turn the switch off to restore the usual map. When your GPS matches the selected train, the app asks if you are aboard. Confirm to start a Live Activity showing the next stop and count to disembarkment.

Background trip updates are optional. Enable **Allow background trip updates** in the settings drawer (gear icon) to request Always location access. GPS runs in the background only for a trip you confirm. If the app is backgrounded when a likely boarding match is found, an authorized local notification opens the app to confirm; otherwise the confirmation appears when the app is open. If Always access is not granted, the Live Activity updates while the app is open and displays the last update when backgrounded.

The MBTA has no trip-planner API, so routing runs on-device over the MBTA schedule data. Walk and car legs use Apple Maps. Bike and scooter legs are estimated from the walking distance at typical speeds. Parking and bike facilities are not considered.
