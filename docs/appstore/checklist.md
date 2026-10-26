# Pre-submission checklist

## You do (needs your accounts)
- [ ] Enroll in the Apple Developer Program ($99/year)
- [ ] Check "Boston Transit" is available; pick a fallback name
- [ ] Regenerate the MBTA API key (the old one has been shared in chat and ships in the app); put it in `ios/Secrets.xcconfig`
- [ ] Check the MBTA developer terms (attribution, branding, app-store use)
- [ ] Host the privacy policy and support page at public URLs (GitHub Pages works); fill in the privacy policy effective date
- [ ] Verify the in-app bug report and feature request links open the correct email composer and prefilled template
- [ ] Change the signing team in `ios/project.yml` to the paid team ID
- [ ] Run on a real iPhone near Boston: map, station sheet, alerts, preferences, trip planner, location prompt
- [ ] Take the screenshots listed in `listing.md`
- [ ] Create the app in App Store Connect (bundle ID `com.tonyvx.transitapp`), paste the listing text
- [ ] Answer App Privacy and export compliance (see `listing.md`)
- [ ] Product > Archive > Distribute to App Store Connect; test via TestFlight
- [ ] Submit for review

## Done in the repo
- [x] Bundle ID, display name, icon, portrait only
- [x] Accurate location permission text
- [ ] Verify optional Always location permission, background GPS indicator and trip Live Activity on a real iPhone.
- [ ] Confirm trip tracking stops when the rider ends the trip or reaches the final stop.
- [x] Privacy manifest (`ios/App/PrivacyInfo.xcprivacy`)
- [x] MBTA attribution and privacy text in Preferences
- [x] Listing, privacy policy and support drafts
