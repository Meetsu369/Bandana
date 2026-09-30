# BANDANA App — UI/UX Product Specification

**Project:** BANDANA — Dual-Band Wearable Human Activity Recognition  
**Target:** Flutter Android application  
**Baseline:** Stable 40 Hz hardware + firmware + dual-band ML pipeline  
**Design language:** Friendly Neo-Brutalism / Playful Corporate Minimalism  
**Primary goal:** Turn the existing functional prototype into a polished, professional, fitness-oriented wearable companion app without destabilizing the validated 40 Hz sensor/ML pipeline.

---

## 1. Product Vision

BANDANA should feel like a modern fitness/wellness product rather than an engineering demo.

The app should make the following journey extremely clear:

> **Connect → Set up profile → Collect data → Understand activity → Review progress → Improve**

The interface should be friendly and visually distinctive while remaining highly usable during real-world sensor-data collection.

### Product principles

1. **Clarity before decoration**
2. **One primary action per screen**
3. **Large readable information**
4. **Friendly, conversational microcopy**
5. **Strong visual hierarchy**
6. **Minimal cognitive load**
7. **Professional data presentation**
8. **No fake health claims**
9. **Never hide connection/sensor/model state**
10. **Do not change the validated 40 Hz acquisition pipeline just for UI work**

---

# 2. Visual Design System

## 2.1 Design Style

Use a **Soft Neo-Brutalist / Playful Corporate Minimalist** visual language.

Characteristics:

- warm cream background
- near-black typography
- bold geometric typography
- oversized headings
- rounded/squircle cards
- thick but controlled borders
- flat color blocks
- subtle shadows
- pill-shaped controls
- playful illustrations/icons
- strong CTA buttons
- generous spacing
- high contrast
- minimal gradients
- minimal glassmorphism
- no overly technical dashboard aesthetic

The app should feel similar in spirit to modern consumer fintech/insurtech products, while developing its own BANDANA identity.

---

# 3. Color Palette

## Core colors

| Token | Color | Usage |
|---|---|---|
| `background` | `#F5F3ED` | Main app background |
| `surface` | `#FFFDF8` | Cards and elevated surfaces |
| `ink` | `#111111` | Primary text/borders |
| `pink` | `#FF69B4` | Primary CTA / key metrics |
| `pinkSoft` | `#FFD4E8` | Pink secondary surface |
| `moss` | `#6B8E23` | Success / active movement |
| `forest` | `#1B3B2B` | Strong secondary action |
| `slate` | `#8C9BA5` | Secondary information |
| `slateSoft` | `#DCE2E5` | Disabled / secondary surface |
| `warning` | `#F2B84B` | Warning |
| `danger` | `#D94A4A` | Error / disconnected state |
| `white` | `#FFFFFF` | Text on dark/high-contrast buttons |

### Rules

- Never use color alone to communicate status.
- Pair status colors with icons/text.
- Maintain readable contrast.
- Pink is an accent, not a background for every screen.
- Keep large areas cream/white to avoid visual fatigue.

---

# 4. Typography

Use a modern rounded/geometric sans-serif.

Recommended Flutter font direction:

- **Primary:** `Manrope`, `Plus Jakarta Sans`, or equivalent
- fallback: system sans-serif

### Type hierarchy

| Level | Weight | Example |
|---|---:|---|
| Display | 800–900 | `82%` |
| H1 | 800 | `Your activity today` |
| H2 | 750–800 | `Your bands are ready` |
| H3 | 700 | `Walking` |
| Body | 400–500 | Supporting information |
| Label | 600–700 | `WRIST BAND` |
| Caption | 500 | Secondary metadata |

Use sentence case rather than unnecessary ALL CAPS.

Example:

**Good**

> Your bands are ready

**Avoid**

> YOUR BANDS ARE READY!!!

---

# 5. Geometry

## Border radius

Use consistent rounded geometry:

- Small: 12 px
- Medium: 18 px
- Large: 24 px
- Hero cards: 28–32 px
- Pills: fully rounded

Avoid mixing many unrelated radii.

## Borders

Primary cards:

```text
1.5–2 px near-black border
```

Use borders as part of the visual language.

## Shadows

Use short, soft, offset shadows.

Example concept:

```text
offset: 0–4 px
blur: 0–0
opacity: subtle
```

Avoid large floating Material-style shadows.

---

# 6. Component Language

## Primary CTA

Large rounded button:

```text
[ Start recording     → ]
```

Characteristics:

- high contrast
- bold label
- large touch target
- arrow/icon
- subtle press animation

## Secondary button

```text
[ View details ]
```

## Status pill

Examples:

```text
● Wrist connected
● Ankle connected
● Recording
● Model ready
```

Use icon + text, never color alone.

## Metric card

```text
┌─────────────────────────┐
│ Steps                   │
│                         │
│  6,842                  │
│ +12% from yesterday     │
└─────────────────────────┘
```

---

# 7. Navigation Architecture

Use a bottom navigation structure.

Recommended primary navigation:

```text
Home
Activity
Collect
History
Profile
```

### Home

Personal overview and connection status.

### Activity

Current activity, activity timeline, statistics and trends.

### Collect

Dataset/data collection workflow.

### History

Past sessions and recordings.

### Profile

Personal information, height, weight, preferences, device management and settings.

---

# 8. Screen Specifications

# 8.1 Onboarding

## Goal

Introduce BANDANA without overwhelming the user.

### Screen 1

**Headline**

> Meet BANDANA

Supporting text:

> Your wearable activity companion.

CTA:

```text
Get started →
```

### Screen 2

Show two-band illustration:

```text
Wrist band + Ankle band
```

Message:

> Two sensors. A clearer picture of how you move.

### Screen 3

Explain the app:

- Track movement
- Collect activity data
- Understand activity patterns
- Review progress

CTA:

```text
Set up my profile →
```

---

# 8.2 Profile Setup

Collect:

### Required

- Name
- Age
- Sex/gender if needed for research dataset
- Height
- Weight

### Optional

- Fitness goal
- Activity level
- Dominant hand
- Notes

### Height input

Support:

```text
cm
```

Optionally allow ft/in UI conversion, but store a canonical value in centimeters.

### Weight input

Support:

```text
kg
```

Store canonical value in kilograms.

### Important

Height and weight must be attached to data-collection sessions so the dataset can be analyzed later.

Do not store only the latest profile value if historical sessions need reproducibility.

---

# 8.3 Home Dashboard

The Home screen should answer four questions immediately:

1. Are my bands connected?
2. What am I doing now?
3. How active have I been?
4. What can I do next?

### Hero

Example:

> Good morning, Sumeet

Then:

> Ready to move?

### Connection card

```text
┌─────────────────────────────────────┐
│ BAND CONNECTION                     │
│                                     │
│  ● Wrist       Connected            │
│  ● Ankle       Connected            │
│                                     │
│  Signal quality        Good         │
└─────────────────────────────────────┘
```

CTA:

```text
Manage bands →
```

### Current activity card

Large activity label:

> Walking

Confidence:

> 91%

Optional visual indicator:

```text
█████████░
```

Never present confidence as medical certainty.

### Daily summary

Show:

- steps, if available
- active minutes
- walking time
- sitting time
- standing time
- stairs/up/downstairs where supported
- recording time

Do not fabricate metrics that the current hardware/model cannot actually measure.

---

# 8.4 Band Connection Screen

Purpose: reliable pairing and role assignment.

### Device cards

```text
WRIST

BANDANA-WRIST
● Connected

Battery: 82%
Signal: Good
```

```text
ANKLE

BANDANA-ANKLE
● Connected

Battery: 76%
Signal: Good
```

Actions:

- Scan
- Connect
- Disconnect
- Assign as Wrist
- Assign as Ankle
- Rename/display device
- Reconnect

### Safety rules

The UI must clearly prevent assigning the same physical device to both roles.

Connection states:

- Searching
- Connecting
- Connected
- Reconnecting
- Disconnected
- Connection error

---

# 8.5 Data Collection

This is one of the most important screens.

The workflow must be optimized for researchers/students collecting training data.

## Step 1 — Participant information

Fields:

- Participant ID
- Participant name/code
- Age
- Height (cm)
- Weight (kg)
- Sex/gender if required by study
- Session ID
- Notes

## Step 2 — Device check

Show:

```text
Wrist     ✓ Connected
Ankle     ✓ Connected
Sampling  ✓ 40 Hz
Storage   ✓ Ready
Model     ✓ Ready
```

Do not expose unnecessary engineering details unless an "Advanced" section is opened.

## Step 3 — Activity selection

Use large cards:

```text
Sitting
Standing
Walking
Upstairs
Downstairs
```

Allow future activities to be added without changing the UI architecture.

## Step 4 — Recording

Large timer:

```text
00:12
```

Activity:

```text
WALKING
```

Sensor state:

```text
WRIST ●
ANKLE ●
```

Controls:

```text
[ Pause ]       [ Stop ]
```

### During recording

Display:

- elapsed time
- sample count
- wrist packet count
- ankle packet count
- dropped/invalid packet indicator
- current activity
- sensor connection state

Keep technical metrics behind a collapsible "Diagnostics" panel for normal users.

---

# 8.6 Data Collection Metadata

Every recording/session should retain metadata.

Recommended session-level fields:

```text
sessionId
participantId
participantName/code
age
heightCm
weightKg
sex/gender (if required)
activity
startTime
endTime
durationSeconds
wristDeviceId
ankleDeviceId
samplingRateHz
windowSize
notes
```

### Critical requirement

Height and weight must be available in the exported dataset.

---

# 9. CSV Export Specification

The exported CSV should contain both sensor data and participant/session metadata.

Do not force metadata into an unusable format if the current data model supports separate session metadata.

Preferred structure:

```text
timestamp,
session_id,
participant_id,
activity,
height_cm,
weight_kg,
age,
wrist_ax,
wrist_ay,
wrist_az,
wrist_gx,
wrist_gy,
wrist_gz,
ankle_ax,
ankle_ay,
ankle_az,
ankle_gx,
ankle_gy,
ankle_gz
```

If the existing CSV architecture uses one row per sensor sample, repeat session metadata for each row.

Example:

```csv
timestamp,session_id,participant_id,activity,height_cm,weight_kg,wrist_ax,wrist_ay,wrist_az,ankle_ax,ankle_ay,ankle_az
2026-09-30T10:00:01,S001,P001,Walking,175,68,123,-420,16200,231,-512,16040
```

### Important

Use stable field names.

Recommended:

```text
height_cm
weight_kg
```

Do not use ambiguous names such as:

```text
height
weight
```

---

# 10. Activity Screen

The Activity screen should present model output in a human-friendly way.

## Current activity

Large card:

> Walking

Supporting:

```text
Confidence
91%
```

### Activity distribution

Example:

```text
Today

Walking       42 min
Standing      31 min
Sitting       68 min
Upstairs       8 min
Downstairs     7 min
```

Only show values that are actually derived from recorded/model data.

---

# 11. History

Display previous sessions as cards.

Example:

```text
Today · 10:32 AM
Walking session
12 min 42 sec
Both bands
```

Tap → session details.

Session detail:

- duration
- activity
- participant metadata
- sensor status
- sample count
- prediction timeline
- export
- delete

---

# 12. Fitness Features

For the first professional version, build a fitness-oriented foundation without pretending the current hardware provides metrics it does not.

## Phase 1 — Directly supportable

- Activity recognition
- Activity duration
- Active minutes
- Session history
- Movement timeline
- Walking/standing/sitting/upstairs/downstairs distribution
- Recording streak
- Daily/weekly activity summaries
- Personal profile
- Height
- Weight
- Dataset/session export
- Dual-band connection status
- Sensor quality
- Session notes

## Phase 2 — Add when reliable data/model support exists

- Step estimation
- Cadence
- Activity intensity
- Movement consistency
- Calories estimation
- Distance estimation
- Workout detection
- Workout summaries
- Personal activity goals

## Phase 3 — Advanced

- Long-term trends
- Personalized activity baseline
- Adaptive goals
- Anomaly flags for sensor data quality
- Model confidence trends
- Personalized model improvements
- Research analytics dashboard

### Important product rule

Never display a fitness metric simply because it is common in fitness apps.

Every metric must have:

1. a valid sensor source,
2. a documented calculation,
3. a known unit,
4. a sensible accuracy limitation.

---

# 13. Fitness Dashboard

Suggested layout:

```text
Good evening, Sumeet

┌─────────────────────────────┐
│ Today's movement            │
│                             │
│  74 min                     │
│ active                      │
└─────────────────────────────┘

┌────────────┐ ┌────────────┐
│ Walking    │ │ Standing   │
│ 42 min     │ │ 31 min     │
└────────────┘ └────────────┘

┌────────────┐ ┌────────────┐
│ Sitting    │ │ Sessions   │
│ 68 min     │ │ 4          │
└────────────┘ └────────────┘

[ Start a session → ]
```

---

# 14. Goals

Allow users to configure simple goals.

Examples:

- Active minutes/day
- Recording sessions/week
- Walking duration/day

Goal card:

```text
Daily movement

74 / 90 min

██████████████░░

16 min to go
```

Goals must be user-configurable.

Do not imply medical recommendations.

---

# 15. Profile

Sections:

### Personal

- Name
- Age
- Height
- Weight

### Fitness

- Goal
- Activity level

### Devices

- Wrist band
- Ankle band

### Data

- Export sessions
- Export CSV
- Delete session data

### App

- Notifications
- Theme
- Units
- About BANDANA

---

# 16. Settings

Include:

- Units: metric/imperial
- Theme: system/light/dark
- Notifications
- Data storage
- Export
- Device management
- Debug/diagnostics
- About

### Developer/diagnostic mode

Hide technical information behind:

```text
Settings → Advanced → Diagnostics
```

Display:

- firmware/device ID
- BLE RSSI
- packet rate
- expected sample rate
- actual received rate
- dropped packets
- database queue
- model status
- feature vector length
- prediction latency

This keeps the main UI friendly while preserving engineering visibility.

---

# 17. Dark Mode

Dark mode should preserve the visual language.

Do not simply invert every color.

Use:

```text
Background: near-black
Surface: dark charcoal
Text: cream/white
Pink: retained as accent
Moss/forest: adjusted for contrast
```

Cards remain rounded and structured.

---

# 18. Empty States

Never show blank screens.

Example:

### No sessions

> Your movement story starts here.

Supporting:

> Record your first session to see your activity history.

CTA:

```text
Start recording →
```

### No connected bands

> Your bands are taking a break.

CTA:

```text
Connect bands →
```

### No predictions

> Nothing to predict yet.

Supporting:

> Start a recording session and BANDANA will analyze your movement.

---

# 19. Error States

Errors should be friendly but explicit.

Bad:

> BLE ERROR 133

Better:

> We couldn't connect to your wrist band.

Then:

```text
Check that the band is powered on and nearby.

[ Try again ]
```

Advanced diagnostics can expose the actual technical error.

---

# 20. Loading States

Use playful but subtle loading indicators.

Example:

> Finding your bands…

Avoid long blocking spinners when progress can be shown.

---

# 21. Micro-interactions

Use restrained animation.

Recommended:

- button press scale
- card entrance
- connection status transition
- prediction change animation
- progress bar animation
- recording timer
- success check animation

Avoid:

- excessive bouncing
- long transitions
- decorative animation during recording
- animations that interfere with data collection

---

# 22. Accessibility

Requirements:

- minimum 44–48 px touch targets
- readable body text
- high contrast
- semantic labels
- screen-reader-friendly controls
- do not communicate state through color alone
- support larger system font sizes
- avoid tiny diagnostic text
- maintain sufficient spacing

---

# 23. Data Architecture Requirements

The UI must not directly manipulate low-level BLE or ML logic.

Preferred architecture:

```text
UI
 ↓
ViewModel / Controller
 ↓
Services / Repositories
 ↓
Database / BLE / ML
```

Keep existing stable services intact wherever possible.

The 40 Hz acquisition pipeline is a validated subsystem and should not be modified as part of UI development.

---

# 24. State Management

Represent important states explicitly.

Examples:

```text
BandConnectionState
RecordingState
PredictionState
ModelState
ExportState
SessionState
```

Avoid scattered boolean combinations such as:

```text
isConnected
isRecording
isLoading
hasError
```

when a finite state model can express the state more reliably.

---

# 25. Component Structure

Recommended reusable Flutter components:

```text
AppScaffold
BandStatusCard
MetricCard
HeroMetricCard
PrimaryButton
SecondaryButton
StatusPill
ActivityCard
ActivityTimeline
ConnectionCard
RecordingTimer
PredictionCard
ConfidenceIndicator
SessionCard
ProfileMetricCard
EmptyState
ErrorState
SectionHeader
```

Components should be reusable and theme-aware.

---

# 26. Suggested Flutter Folder Organization

Do not blindly restructure the existing project. Adapt this architecture to the current repository.

```text
lib/
  src/
    core/
      theme/
        app_colors.dart
        app_theme.dart
        app_typography.dart
        app_spacing.dart

    features/
      home/
      activity/
      collect/
      history/
      profile/
      settings/
      devices/

    shared/
      widgets/
        buttons/
        cards/
        status/
        charts/
        feedback/
```

Keep existing working BLE, database, ML and recording services where they are unless there is a demonstrated architectural reason to move them.

---

# 27. Design Tokens

Create a central theme instead of hardcoding visual values throughout the app.

Example conceptual API:

```dart
AppColors
AppTypography
AppSpacing
AppRadius
AppShadows
```

Avoid:

```dart
Color(0xFFFF69B4)
```

being repeated across dozens of widgets.

Prefer:

```dart
context.colors.primaryAccent
```

or the project's equivalent theme mechanism.

---

# 28. Data Collection CSV Requirements

The data-collection workflow must support:

### Participant

```text
participant_id
participant_name/code
age
height_cm
weight_kg
sex/gender (if required)
```

### Session

```text
session_id
activity
start_time
end_time
duration_seconds
notes
```

### Hardware

```text
wrist_device_id
ankle_device_id
sampling_rate_hz
```

### Sensor data

```text
timestamp
wrist_ax
wrist_ay
wrist_az
wrist_gx
wrist_gy
wrist_gz
ankle_ax
ankle_ay
ankle_az
ankle_gx
ankle_gy
ankle_gz
```

---

# 29. Data Integrity Rules

Because BANDANA is also a research/data-collection application:

- never silently discard a recording
- show recording completion status
- show whether both bands were connected
- preserve session metadata
- preserve timestamps
- validate required participant fields
- prevent accidental duplicate session IDs
- confirm before deleting sessions
- show export success/failure
- never claim a CSV was successfully exported until the file exists

---

# 30. Privacy

Participant information should be treated as sensitive application data.

For research datasets, support participant codes such as:

```text
P001
P002
P003
```

rather than requiring personally identifying names in exported research data.

If a name is collected for convenience, allow export to use the participant ID instead.

---

# 31. Professional Dashboard Direction

The app should visually balance:

```text
                    PERSONAL
                       ↓
        ┌──────────────────────────┐
        │     Today's movement     │
        │                          │
        │          74 min          │
        └──────────────────────────┘

       ┌───────────┐  ┌───────────┐
       │ Walking   │  │ Standing  │
       │ 42 min    │  │ 31 min    │
       └───────────┘  └───────────┘

       ┌──────────────────────────┐
       │      BAND STATUS         │
       │  ● Wrist   ● Ankle      │
       └──────────────────────────┘

              [ Record → ]
```

Large numbers should communicate the most important information immediately.

---

# 32. UX Copy Guidelines

Use conversational language.

### Prefer

> Your bands are ready.

> Let's capture this session.

> Nice — session complete.

> You're connected.

> We found both bands.

> Nothing recorded yet.

### Avoid

> BLE CONNECTION SUCCESSFUL!!!

> INITIATE SENSOR ACQUISITION

> PREDICTION PIPELINE ACTIVE

Engineering terminology belongs in diagnostics, not the primary experience.

---

# 33. Mascot / Illustration Direction

Optional BANDANA character system:

Use simple geometric characters rather than complex illustrations.

Possible concept:

- rounded band-shaped character
- two simple eyes
- pink accent
- cream body
- dark outline
- occasional wrist/ankle accessories

Use characters primarily for:

- onboarding
- empty states
- success states
- connection states

Do not place mascots on every screen.

---

# 34. Screen Priority

Implement in this order:

## P0 — Core product

1. App theme/design system
2. Home dashboard
3. Device connection
4. Data collection
5. Participant profile
6. Height/weight fields
7. Session metadata
8. CSV export
9. Activity prediction UI
10. Session history

## P1 — Professional polish

11. Profile screen
12. Fitness dashboard
13. Goals
14. Activity timeline
15. Empty/error states
16. Loading states
17. Dark mode
18. Accessibility
19. Advanced diagnostics

## P2 — Fitness expansion

20. Step estimation
21. Cadence
22. Activity intensity
23. Workout sessions
24. Long-term trends
25. Personalized goals

Only implement P2 metrics when their underlying data/calculation is valid.

---

# 35. Non-Negotiable Engineering Constraints

### DO

- preserve the 40 Hz firmware
- preserve stable BLE behavior
- preserve validated ML behavior
- reuse existing services
- add tests for new data/session logic
- validate CSV output
- make UI responsive
- handle BLE disconnects gracefully
- handle app lifecycle correctly
- keep diagnostics available

### DO NOT

- change 40 Hz to 50 Hz
- change sampling interval
- change firmware packet format
- change model feature length casually
- invent fitness metrics
- hardcode confidence values
- silently fall back between incompatible ML models
- rewrite working BLE code just for UI cleanup
- make large architectural changes without verification
- mix experimental ML changes with UI work

---

# 36. Definition of Done

The first professional UI release is complete when:

- [ ] App has the new visual design system
- [ ] Home dashboard is polished
- [ ] Wrist/ankle connection states are clear
- [ ] Recording workflow is reliable
- [ ] Participant metadata is captured
- [ ] Height is stored in cm
- [ ] Weight is stored in kg
- [ ] Height and weight appear in exported CSV/session data
- [ ] Activity selection works
- [ ] Recording history works
- [ ] Session details work
- [ ] CSV export works
- [ ] Activity predictions are displayed correctly
- [ ] Confidence is shown only when genuinely available
- [ ] Empty/error/loading states exist
- [ ] No fake fitness metrics are displayed
- [ ] 40 Hz acquisition remains unchanged
- [ ] Existing firmware remains unchanged
- [ ] Existing validated ML pipeline remains unchanged
- [ ] `flutter analyze` has no new errors
- [ ] Tests pass
- [ ] App has been tested with both Wrist + Ankle bands
- [ ] Disconnect/reconnect behavior has been tested
- [ ] App lifecycle behavior has been tested

---

# 37. Implementation Strategy

Do not attempt to rewrite the entire app in one pass.

Use incremental commits:

```text
1. feat: add BANDANA design system
2. feat: redesign home dashboard
3. feat: redesign device connection flow
4. feat: improve participant data collection
5. feat: add height and weight session metadata
6. feat: add CSV metadata export
7. feat: redesign activity prediction UI
8. feat: add session history
9. feat: add fitness dashboard foundation
10. feat: add accessibility and polish
```

After every significant step:

```bash
flutter analyze
flutter test
git diff
git status
```

Keep each commit small and reversible.

---

# 38. Final Product Direction

BANDANA should feel like:

> **A friendly fitness companion powered by serious wearable technology.**

The engineering complexity should remain underneath the interface.

The user should see:

```text
Simple
Friendly
Clear
Professional
Trustworthy
```

while the application underneath continues to provide:

```text
Dual-band BLE
40 Hz sensor acquisition
Local data storage
Activity recognition
Research-grade session metadata
CSV export
Diagnostics
```

The UI is the product layer.

The validated hardware + firmware + ML pipeline remains the foundation.

**Do not compromise the foundation to decorate the product.**
