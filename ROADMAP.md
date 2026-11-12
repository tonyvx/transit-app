# Boston Transit roadmap

Status today: on-device only (no backend). Live vehicles for rail and the Silver Line, alerts filtered to favorite routes and branches, a first-run guide, a trip planner with live predictions, favorites, reminders, a widget, opt-in trip Live Activity tracking, and a Help & feedback hub. The revised planner and trip map filter have targeted simulator coverage; the latest interface still needs real-device validation.

## Done

- Live map, preferences, station arrivals, alerts with drive times, how-to guide, first-run line picker.
- Multi-transfer trip planner (rail and Silver Line) with walk, bike, scooter and car access.
- Live predictions in the planner: live times and delay per leg, cancelled trains skipped, later connections follow the live arrival, "Live" badge, pull to refresh.
- Planning for any day with published schedules, with Leave now, Depart at and Arrive by. This fixed a bug where every day except today found no trips.
- Planner opens from the map's trip-summary bar. Typed locations are looked up on leaving the field or submitting, and planning starts when both endpoints are ready; GO retries or replans.
- Walk, Drive, Scooter and Bike controls set both station access legs, with per-leg mode overrides beside the address fields. Current-location and dropped-pin controls remain available for either endpoint.
- Saved trips are collapsed behind a count; trip cards show duration and estimated miles for each leg and the total. Transit distance is estimated between stops, not from track geometry.
- Planner has Clear and Swap; Clear resets the form and removes the selected itinerary from the map, while swapping reverses the endpoints.
- A bottom-left map switch hides non-trip route traces and trains, fades unused portions of trip routes, and limits saved-line station markers to stops on the trip. Hidden traces are excluded from route hit testing. Matching route shapes are clipped to trip stops when available; otherwise the trip is drawn between stops.
- Direction and approaching-train preferences persist immediately when changed; favorite route and branch selections are shown individually and alerts match the selected route IDs.
- Favorite stations, saved trips, a weekday reminder per saved trip, and a one-off "Remind me to leave".
- "Next trains" widget (small, medium, lock screen) that reads favorites through an App Group.
- Trip boarding confirmation when the planned train ID, GPS matcher and rider/train proximity agree.
- Lock Screen Live Activity with next stop and stops remaining, updated using fresh train positions and background GPS when opted in. Always access and background location are enabled only after explicit consent and only during a confirmed trip.
- Unit tests for the router, matcher, filters, live predictions, arrive-by, favorites, trip confirmation and stop progression.
- The settings drawer provides the how-to guide, bug and feature request email links, MBTA developer information, and privacy details.
- How-to instructions use short bullet points and current simulator screenshots for each step.

## Next steps (in value-for-effort order)

### 1. Check the new features on the phone
- Still verify on a real trip: boarding prompt, Always location permission, Live Activity updates and ending at disembarkment. Also confirm a leave reminder fires and the widget receives favorites. A free personal team may not honor the App Group.
- Verify the support email opens the composer with the intended subject and template on a device with an email account configured.
- Validate the revised planner, saved trips, per-leg mode controls and hide-other-lines switch on a real device; refresh the affected App Store screenshots.

### 2. Finish the planner
- Include MBTA alerts for the lines a trip uses, and warn when a leg has a "Suspension" or "Shuttle" alert.
- Refresh the selected trip automatically while the planner is open, not just on pull to refresh.
- Flag a transfer that live times make tight or missed.
- Show a clear message when the MBTA has not published schedules for the chosen date (after the current rating ends).

### 3. Release
- Paid Apple developer account, regenerated MBTA key (consider a small proxy so the key does not ship in the app), TestFlight, then the App Store.
- Privacy policy, listing and screenshots are drafted in `docs/appstore`. Check the MBTA developer terms and that the name "Boston Transit" is free.
- Pricing proposal: launch free with no paywall or subscription, then revisit after TestFlight feedback; this is not a final pricing decision.
- Add error and offline states first, so a bad connection is not a blank screen.

### 4. Alerts and live updates
- Local notifications for alerts on preferred lines (needs background fetch, which is unreliable).
- Push alerts and server-driven Live Activity updates for conditions independent of active GPS tracking need APNs and a small server. Decide this together with the crowdsourcing store.
- Apple Watch app after on-device trip tracking is validated.

### 5. Coverage: buses and ferries
- Add route types 3 and 4, opt-in per route (there are hundreds of bus routes).
- Extend `network()` for the planner, measure load time, and cache it on disk with an expiry.
- Done when a trip can use a bus or ferry leg without slowing the map.

## Future steps

### Opt-in crowdsourcing (Version 1 option C)
- Automatic opt-in GPS sharing, plus manual stoppage and crowding reports. This is the clearest way to beat other apps on Commuter Rail.
- Needs a shared store (own backend or CloudKit), "Always" location access and a privacy design. An earlier server design is in `backend/`.
- Update the permission text, privacy policy and App Privacy answers at the same time.
- Prove first that rider GPS identifies the correct train and improves position estimates under real conditions.

### Version 2 features
Crowd-aware arrival predictions, stoppage detection, train-specific alerts, historical reliability statistics and departure recommendations.

### Planner extras
- Bluebikes stations and bike-lane aware routing, station parking, step-by-step navigation, fares and tickets.

### Polish and testing
- Accessibility: VoiceOver labels, Dynamic Type, contrast, not relying on color alone for lines.
- More tests: MBTA response parsing, and the widget's feed.
- Widgets are limited to two favorites. Add a way to choose which ones.

### Multi-city support
- `TransitProvider` is the interface. Move MBTA-specific strings and line groups behind it, then add a city picker and a second provider.
