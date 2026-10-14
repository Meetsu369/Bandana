# BANDANA --- Master Project Build Specification

## Android App Completion, ML Training, Activity Recognition, Data Collection, and Validation

**Target coding environment:** Google Antigravity with Flash 3.8 High\
**Project:** BANDANA wearable activity-recognition application\
**Platform:** Flutter Android app, with an optional laptop-assisted
training service\
**Purpose:** Single source of truth for implementation scope,
constraints, acceptance criteria, testing, and delivery.

------------------------------------------------------------------------

## 1. Mission and definition of done

Complete the existing BANDANA application using its current repository
and architecture. Deliver a polished Android experience that can connect
to wrist and ankle bands, record consistent sensor data, organize and
export labeled sessions, train and compare supported ML models,
recognize activities live, and persist explicit user feedback for later
model improvement.

A feature is complete only when it works end-to-end against real data,
handles failure states, is tested, and does not damage working
functionality. A screen that merely looks complete, fake success
messages, mock production data, or an untested integration do not count.

Work in small, independently verifiable tasks. Prioritize reliable
recording, data integrity, and real activity recognition over
speculative fitness metrics or an unsafe automatic-learning loop.

## 2. Known project context --- verify against the repository

The following is the latest reported context, not proof that the current
checkout is identical.

-   Flutter app using Material 3.
-   Five-tab navigation: **Home, Live/Activity, Record/Collect, History,
    Profile**.
-   A Training screen reportedly exists at **Profile → Quick Actions →
    Model Training**.
-   Existing services include `DatabaseService` and `MlService`; a
    `TrainingController` and training screen have been added.
-   Existing model paths use 30-feature single-band vectors and
    60-feature combined wrist-plus-ankle vectors.
-   The existing single-band classifier is shared by wrist and ankle
    training. Do not introduce separate model slots without proving a
    need and documenting migration.
-   KNN training/inference is present; Logistic Regression is a
    requested addition.
-   Drift is used for local persistence; SharedPreferences has been used
    for model persistence.
-   BLE package reported: `flutter_blue_plus`.
-   Firmware is intended to acquire at **40 Hz**. Do not change
    firmware, BLE protocol, hardware configuration, or sensor rate as
    part of app work unless separately authorized.
-   Firmware device names have been reported as `BANDANA-WRIST` and
    `BANDANA-ANKLE`; verify current source before relying on these.
-   Earlier reported commits: `f4d22c9` (dashboard compile fix) and
    `78ba75d` (training test isolation and combined-window pairing fix).
    Verify actual branch, HEAD, status, and history before editing.
-   Previous reported verification: 105 tests passed and zero analyzer
    errors. Re-run verification; do not assume these results remain
    current.
-   Visual direction: warm cream background, off-white surfaces,
    near-black typography, restrained pink accent, Manrope typography,
    rounded surfaces, clear spacing. Read `UI_UX_SPEC.md` if present.

## 3. Non-negotiable engineering rules

### 3.1 Protect the repository

Before editing: 1. Run `git status --short`,
`git branch --show-current`, `git log -5 --oneline`, and inspect
staged/unstaged diffs. 2. Identify uncommitted and untracked work. Never
discard, reset, clean, or overwrite it. 3. Inspect relevant code and
tests before proposing replacements. 4. Establish a baseline with
`flutter analyze` and `flutter test`. 5. Make one coherent change at a
time and review the diff before committing.

After each task: - Run relevant tests, then the full suite when
practical. - Run `flutter analyze` and `git diff --check`. - Inspect
`git diff --stat` and `git diff`. - Confirm firmware files and unrelated
features remain unchanged. - Commit only a verified, scoped
checkpoint. - Do not push unless explicitly asked.

### 3.2 Preserve existing architecture

-   Reuse services, providers, dependency injection, navigation,
    widgets, database models, and design tokens.
-   Do not duplicate business logic inside UI widgets.
-   Avoid broad rewrites, unnecessary packages, and unrelated refactors.
-   Do not change the database schema unless required, justified,
    tested, and documented.
-   Never fabricate sensor readings, session counts, model accuracy,
    progress percentages, or successful uploads.
-   Every button must do what its label promises.
-   Make loading, empty, unavailable, disconnected, permission-denied,
    and error states explicit.
-   Do not claim physical-hardware testing unless it actually happened.
-   Do not silently fall back from dual-band inference to a single-band
    model when dual-band mode is selected.

### 3.3 Protect firmware and sensor timing

App changes must not alter firmware's 40 Hz acquisition configuration,
BLE protocol, device roles, wiring, pin assignments, or SD/Wi-Fi
behavior. Preserve firmware capture timestamp semantics.

If firmware is found to produce a timing defect, document evidence and
stop for separate approval rather than silently changing firmware during
an Android task.

------------------------------------------------------------------------

## 4. Product navigation and screens

Preserve the five-tab navigation unless the current architecture
demonstrates a necessary reason to change it.

### 4.1 Home

Provide a truthful overview: - Wrist and ankle connection status. -
Whether the expected model is available. - Latest recognized activity,
if a valid prediction exists. - Recent saved sessions from the
database. - Shortcuts to Live Recognition, Record, History, and Model
Training. - Useful first-run and disconnected states.

Do not show fabricated steps, calories, heart rate, sleep, activity
scores, or model accuracy. Only show metrics backed by real sources.

### 4.2 Live Activity Recognition

Create or complete a dedicated screen that: - Shows wrist and ankle
connection status independently. - Allows wrist, ankle, or combined
inference mode when supported. - Displays the current predicted activity
from real sensor data. - Displays confidence only when the model
produces a meaningful score; do not label an uncalibrated vote
proportion as guaranteed accuracy. - Shows "model not trained/available"
when appropriate. - Shows stale-data/disconnected status instead of
presenting the last prediction as live. - Displays a short prediction
timeline where useful. - Handles disconnect/reconnect, stream errors,
app lifecycle, and screen disposal. - Avoids rebuilding the whole screen
for every sensor sample.

Use the correct feature shape: 30 features for single-band and 60 for
combined input. Never silently use a 30-feature model when combined mode
is selected.

### 4.3 Record / Collect

Support: - Participant/user label or anonymized participant ID before
recording. - Activity selection before recording. - Adding custom
activity labels. - Connected-band readiness. - Start, stop, cancel, and
save/discard behavior. - Visible elapsed timer and sample/timing
health. - Warnings for disconnects or excessive sample gaps. - Safe
final buffer flush so final samples are not lost. - Consistent session
metadata and samples. - CSV export for every saved session. - Prevention
of accidental duplicate sessions and filename collisions.

Recording must not report success until required data and metadata are
saved.

### 4.4 History

Show real persisted sessions: - Participant label, activity, start time,
duration. - Available bands and sample counts. - Data-quality indicators
where available. - Export/share actions. - Session details and plots
where supported. - Multi-select for sharing/exporting sessions. - Empty,
loading, partial-data, and error states. - Confirmed deletion and
correct cleanup of related files/metadata.

Do not use placeholder cards that imply sessions exist.

### 4.5 Profile and Settings

Include the existing Model Training entry, device management, relevant
permissions, activity-label management, export/upload configuration,
model selection/status, app information, and troubleshooting as
supported by actual code.

Do not claim a cloud account is connected until authentication succeeds.

### 4.6 Model Training

Support: - Wrist single-band training using the existing 30-feature
pipeline. - Ankle single-band training using the existing 30-feature
pipeline. - Combined training using 60-feature wrist-plus-ankle
vectors. - Dataset readiness based on real database data. -
Activity/class counts and insufficient-data messages. -
Training/loading/success/failure states. - Model persistence status and
errors. - Algorithm selection between KNN and Logistic Regression only
when each path is implemented and verified. - Active-model indicator and
safe selection among models compatible with the selected inference mode.

Never train from empty data, silently change algorithms, or mark an
unsaved model as persisted.

------------------------------------------------------------------------

## 5. Sensor rate consistency: 40 Hz requirement

### 5.1 Desired behavior

The user reports that recording initially appears to receive more than
40 Hz and later settles near 40 Hz. Recording must have a consistent
policy from the first seconds through the end.

At 40 Hz, the nominal interval is **25 milliseconds per band**.

### 5.2 Important distinction

An app-side rate cap can limit samples accepted into a dataset, but it
cannot repair the physical sensor acquisition cadence or recover samples
that were never captured. Do not describe a UI throttle as proof that
the sensor itself samples at exactly 40 Hz.

First: 1. Inspect firmware timestamps and the actual BLE receive stream.
2. Measure per-band intervals from capture timestamps when available,
not only phone receive time. 3. Separate sensor capture time from phone
receive time. 4. Determine whether apparent \>40 Hz is caused by actual
rapid samples, duplicate samples, buffered/batched BLE delivery, or a
measurement artifact. 5. Retain enough diagnostic information to
identify the cause. 6. Add a deterministic app-side recording
gate/resampler only if needed, and define its behavior explicitly.

### 5.3 Recording gate/resampling rules

-   Treat each band independently.
-   Use monotonic capture timestamps when valid and available.
-   For a strict 40 Hz accepted dataset, accept at most one sample per
    25 ms time slot per band.
-   Define handling for samples that arrive too early, late, duplicated,
    or out of order.
-   Never pair wrist and ankle samples solely because they have the same
    list index.
-   Do not substitute phone wall-clock time for capture time without
    recording the limitation.
-   If interpolation/resampling is introduced, document it and avoid
    inventing misleading measurements.
-   If a sample gap is too large, mark the interval/window invalid
    instead of pretending it is complete.
-   Track received, accepted, dropped/duplicate samples, interval
    distribution, and gap counts.
-   Apply the same rate policy from recording start.
-   Test rapid arrivals, irregular intervals, duplicate timestamps,
    gaps, out-of-order data, and independent wrist/ankle streams.

### 5.4 Acceptance criteria

-   Bursts above 40 Hz never yield more than the defined accepted
    cadence per band.
-   Recording start has no unthrottled period.
-   Diagnostics reveal dropped or missing samples.
-   No firmware changes are made in this app task.
-   Physical-device results are reported separately from unit-test
    results.

------------------------------------------------------------------------

## 6. Participant names, activity labels, sessions, and CSV

### 6.1 Session setup

Before recording, request: - Participant/user label or anonymized ID. -
Activity selected from known labels. - Optional session notes if
practical. - Bands to record, based on real connection status.

Explain that the participant label may appear in exported filenames.
Prefer anonymized IDs when adequate.

### 6.2 Activity-label manager

Users must be able to add custom activities: - Trim whitespace and
reject empty labels. - Prevent duplicates after case/whitespace
normalization. - Use safe display/storage values and stable IDs where
supported. - Handle rename/delete without corrupting historical
sessions; prefer archiving labels already used. - Show custom labels in
recording, history, export, and training counts. - Test duplicates,
empty labels, unusual characters, and historical sessions referencing
archived labels.

Do not hard-code the list in multiple screens.

### 6.3 Filename convention

Requested example: `sumeet_walking.csv`.

Rules: - Generate a safe filename from normalized participant and
activity labels. - Use lowercase snake_case or another consistent
portable convention. - Replace filesystem-invalid characters and
separators. - Prevent path traversal. - Handle Unicode and empty
normalized values safely. - Prevent collisions when the same participant
repeats the same activity; add a timestamp or session-ID suffix while
preserving the recognizable prefix. - Preserve original labels in
session metadata.

Example: `sumeet_walking_20261014_153000.csv`, using the actual session
timestamp.

### 6.4 CSV requirements

Define and document a stable schema before implementation. Include where
available: - Schema/version marker in metadata or a sidecar file if CSV
comments would break parsers. - Session ID, participant label/ID,
activity label. - Band role and sensor capture timestamp. - Actual
accelerometer/gyroscope axes. - Units for each measurement. - Sample
quality/timing metadata where appropriate.

Inspect existing firmware CSV and BLE formats before changing export
schema. Do not break existing parsers/tests. If needed, document
separate raw-band and combined exports. CSV must be deterministic,
UTF-8, properly escaped, and testable. Never mix sessions or fabricate
samples.

------------------------------------------------------------------------

## 7. Multi-session sharing and Google Drive

### 7.1 Local export and multi-session sharing

Users should be able to: - Export one session. - Select multiple
sessions and export/share together. - Export separate CSVs, optionally
packaged into a ZIP. - Include a manifest with session IDs,
participant/activity labels, timestamps, schema version, and
filenames. - Use Android's share sheet. - Handle cancellation, missing
files, permission failures, and large exports. - Clean temporary files
safely.

Do not concatenate unrelated CSVs into an invalid single CSV. Prefer a
ZIP with one CSV per session plus a manifest.

### 7.2 Direct Drive upload

Implement direct upload only with suitable Google OAuth and Drive API
integration: - Use minimum necessary OAuth scopes. - Never embed client
secrets or service-account private keys in the app. - Use supported
account authentication. - Request consent and show selected files. -
Upload selected CSVs or a ZIP/manifest. - Show genuine progress where
available and success only after server confirmation. - Handle revoked
auth, network loss, rate limits, retries, and duplicate uploads. - Never
upload personal sensor data silently. - Store tokens appropriately and
document Google Cloud project setup. - Do not claim upload works until
credentials/configuration and tests are complete.

If OAuth setup is unavailable today, finish/test local export and
sharing, display "Drive setup required," and document the exact external
configuration still needed.

------------------------------------------------------------------------

## 8. Logistic Regression and model selection

### 8.1 Goal

Add Logistic Regression as a real alternative to KNN. Support 30-feature
single-band and 60-feature combined paths only where implementation and
data support them.

### 8.2 Inspect ML library capability first

-   Check APIs available in the exact installed `ml_algo` and
    `ml_dataframe` versions.
-   Verify multiclass Logistic Regression, persistence, inference, and
    probability output support.
-   Do not assume a Python scikit-learn model can be loaded by the
    existing Dart runtime.
-   Do not upgrade packages blindly.
-   If current Dart APIs are insufficient, compare a small compatible
    implementation with an explicit laptop-artifact format before adding
    dependencies.

### 8.3 Versioned model contract

Record: - Algorithm (KNN or Logistic Regression). - Feature
schema/version and feature count (30 or 60). - Feature ordering. - Class
labels and stable mapping. - Preprocessing/normalization parameters. -
Training data/session provenance. - Validation metrics and split
method. - Training timestamp/model version. - Serialization format and
compatibility version.

Training and inference must use identical feature extraction and
preprocessing. Reject incompatible artifacts with clear errors.

### 8.4 Evaluation and selection

-   Compare algorithms on the same eligible dataset and validation
    split.
-   Prevent leakage by splitting by session and, where appropriate,
    participant. Overlapping windows from the same session must not leak
    between train and test.
-   Report accuracy and per-class precision/recall/F1 plus confusion
    matrix where data supports it.
-   Record dataset size, class balance, and split strategy.
-   Do not claim a universally superior model based on tiny or leaked
    test data.
-   Let users choose the active compatible model, or use a transparent,
    tested recommendation policy.
-   Never change the active model without explicit user choice or
    transparent policy.
-   Keep model versions and allow rollback.

------------------------------------------------------------------------

## 9. Laptop-assisted training and on-phone training

### 9.1 Desired workflow

Provide two explicit modes: 1. **Train on phone:** supported on-device
training. 2. **Train on laptop:** send user-authorized data to a laptop
service, train/evaluate there, then import a compatible artifact.

### 9.2 Laptop service

Inspect the repository before choosing a location. If needed, create a
small Python service (for example, FastAPI) with: - Start/stop
instructions and a health/version endpoint. - Authenticated or
session-scoped pairing on a trusted local network. - Dataset upload with
size limits and validation. - Session/activity metadata validation. -
Training endpoint and cancellation/timeouts where practical. - Model
evaluation and result endpoint. - Versioned model artifact export. -
Safe error logging.

Test malformed files, invalid datasets, unsupported schemas, and
interrupted requests. Do not expose an unauthenticated service to the
public internet. Document network/firewall requirements. Do not assume
USB works unless an actual ADB/USB bridge is implemented.

### 9.3 Artifact compatibility

Never activate a laptop-trained model just because upload succeeded.
Verify: - Artifact schema/version and algorithm. - Feature count/order
and label mapping. - Preprocessing parameters. - Runtime
compatibility. - Validation results and metadata.

If scikit-learn artifacts cannot be loaded by Flutter, use an explicit
versioned interchange format, a supported inference runtime, or a
documented alternative approved after comparing complexity. Never use
Python pickle as an unsafe mobile interchange format or load arbitrary
executable code.

### 9.4 Acceptance criteria

-   Phone and laptop show clear connection/training states.
-   User explicitly selects data to send.
-   Upload failure does not corrupt local sessions or active model.
-   Imported artifact passes compatibility checks before activation.
-   Previous model remains available for rollback.
-   On-device training still works independently.
-   Laptop training documents network/service prerequisites.

------------------------------------------------------------------------

## 10. Live recognition and user feedback

### 10.1 Recognition flow

1.  Verify connection and model compatibility.
2.  Collect enough samples for a valid window.
3.  Extract the exact expected feature vector.
4.  Apply stored preprocessing.
5.  Run inference.
6.  Display predicted activity and honest confidence/score.
7.  Save prediction provenance if history is enabled.
8.  Offer optional feedback without interrupting every prediction
    excessively.

Handle invalid windows and stale data explicitly.

### 10.2 Feedback controls and records

Allow: - Correct. - Incorrect. - Optional corrected activity label.

Store prediction ID, predicted label, model/version ID, timestamp,
available score, feedback, corrected label, and session/window reference
where available.

Feedback is useful but is not automatically ground truth. Users can make
mistakes, and overlapping windows may represent the same event.

### 10.3 Safe improvement loop

Do not update model weights after every feedback tap.

1.  Save explicit feedback as a review record.
2.  Deduplicate/group overlapping windows from the same event.
3.  Allow review of uncertain/incorrect examples.
4.  Build a candidate dataset from accepted labels.
5.  Retrain a candidate model in a controlled job.
6.  Evaluate on held-out sessions/participants.
7.  Compare candidate and current metrics.
8.  Promote only if compatibility and configured acceptance criteria
    pass.
9.  Preserve the previous model and allow rollback.

Show "improvement pending" until training and evaluation actually
complete. Do not claim accuracy improved merely because feedback was
submitted.

------------------------------------------------------------------------

## 11. Reinforcement Learning --- correct scope

The user requested reinforcement learning. Do not add a misleading RL
switch that simply retrains from labels.

Activity recognition with user corrections is primarily supervised
learning/active learning. True RL needs a defined state, action, reward
signal, and environment. A thumbs-up/down alone does not establish a
safe RL problem.

For this release: - Implement feedback capture and controlled supervised
improvement. - Keep feedback records extensible for future
experiments. - If proposing real RL, isolate it from the production
classifier, define state/action/reward and evaluation, and obtain
explicit approval. - Never use unverified feedback to overwrite the
production model. - Do not promise online accuracy improvement without
measured evidence.

------------------------------------------------------------------------

## 12. Fitness features and calorie estimates

The user wants fitness features such as calorie expenditure. Add only
metrics that can be supported honestly.

### 12.1 Identify available signals

Inspect the actual hardware/data. The known band uses an MPU6050
accelerometer/gyroscope; no heart-rate sensor is known to be present. Do
not assume heart rate, SpO₂, GPS distance, sleep stages, or body
composition are available.

### 12.2 Potential features

Only when backed by real data and tested methods: - Activity duration. -
Session counts/history. - Activity distribution. - Movement-intensity
proxy from acceleration. - Step estimate only with documented, tested
step detection and disclosed limitations. - Calorie/energy estimate only
with a defensible method and required user inputs.

### 12.3 Calories

Do not present a raw acceleration heuristic as scientifically accurate
calories.

Before showing calories: - Choose/document a suitable recognized
estimation method. - Identify required inputs (e.g. body mass, age, sex,
activity type) based on the chosen method. - Make profile inputs
optional, private, and explicit. - Validate/calibrate against a suitable
reference where possible. - Label outputs as estimates and state
limitations. - Hide the metric or show "not available" if required
inputs are missing. - Test units, edge cases, and plausibility limits.

If a credible estimate cannot be implemented and tested today, ship
duration/intensity summaries first and mark calories pending validation.
Never invent heart-rate metrics.

------------------------------------------------------------------------

## 13. Permissions, privacy, security, reliability

-   Request only permissions required for Bluetooth, file sharing, and
    selected cloud integration.
-   Handle denied/permanently denied permissions with clear guidance.
-   Keep sensor data local by default unless user explicitly
    exports/uploads.
-   Explain that participant labels may appear in filenames.
-   Never upload without user confirmation.
-   Never hard-code OAuth secrets, passwords, API keys, or private keys.
-   Validate imported CSVs and laptop model artifacts.
-   Bound buffers and queues.
-   Close BLE subscriptions, streams, databases, files, and network
    resources.
-   Prevent data loss on stop/dispose and app lifecycle transitions.
-   Use safe/atomic model persistence where possible.
-   Keep the last known good model until a new one is verified.
-   Show actionable errors rather than swallowing exceptions.

------------------------------------------------------------------------

## 14. Test strategy

### Unit tests

-   40 Hz gate/resampler and timestamp handling.
-   Filename normalization and collision handling.
-   CSV schema, encoding, and escaping.
-   Activity-label validation and duplicates.
-   Session pairing and feature-vector lengths.
-   KNN and Logistic Regression training/inference.
-   Model serialization, loading, version checks, rollback.
-   Feedback record creation, deduplication, candidate promotion.
-   Units/plausibility of any fitness estimates.

### Widget tests

-   Recording setup and start/stop.
-   Custom activity creation.
-   Live recognition states.
-   Training algorithm selection.
-   Wrist/ankle/combined selection.
-   Empty, disconnected, missing-model states.
-   Multi-session selection/export feedback.
-   Upload states/errors when cloud integration is configured.
-   Navigation across all five tabs.

### Integration tests

-   Record → save → History → export CSV.
-   Select multiple sessions → ZIP/manifest → share.
-   Train KNN → persist → reload → infer.
-   Train Logistic Regression → persist/import → reload → infer.
-   Sensor samples → valid window → prediction shown.
-   Correction → feedback review → candidate training → evaluation →
    promote/rollback.
-   Laptop training round trip if implemented.
-   Verify on-device training still works.

### Static/build verification

-   `flutter analyze`
-   `flutter test`
-   Android debug build
-   Laptop-service tests if created
-   `git diff --check`
-   Physical-device tests for BLE timing, recording, sharing, and
    lifecycle

Report exact results. Do not claim critical hardware workflows are
verified if only unit tests were run.

------------------------------------------------------------------------

## 15. One-day implementation priorities

Aim to complete the highest-value reliable flows today. Do not fake
completion for features requiring external setup or scientific
validation.

### Priority 0 --- Repository safety

Verify Git state and test baseline. Preserve the last known good
training implementation.

### Priority 1 --- Recording reliability and data integrity

Measure actual per-band timing; implement/test a deterministic 40 Hz
accepted cadence if needed; fix stop/flush lifecycle; add
participant/activity setup and custom labels; save metadata and CSV
reliably.

### Priority 2 --- Export and History

Export individual sessions; add multi-session ZIP/manifest and Android
share sheet; ensure saved sessions display correctly.

### Priority 3 --- Live recognition

Connect real sensor streams to valid windows and selected model; display
predictions, model state, connection state, and feedback.

### Priority 4 --- Logistic Regression

Verify library support; implement a compatible path; add algorithm
selection, metadata, persistence, evaluation, and tests; preserve KNN.

### Priority 5 --- Feedback-driven candidate improvement

Store explicit corrections; implement controlled supervised
retraining/evaluation; never replace a good model without candidate
evaluation and rollback.

### Priority 6 --- Laptop-assisted training

Implement a minimal secure local service and compatible artifact
exchange if feasible. Otherwise document exact remaining work; do not
pretend the connection exists.

### Priority 7 --- Fitness estimates and polish

Add only validated metrics. Run full regression and physical-device
checks.

Google Drive OAuth/API setup, external credentials, physical-device
verification, and validated calorie methodology may require external
setup or more time. Report these honestly.

------------------------------------------------------------------------

## 16. Agent working protocol

The target coding agent is Antigravity with Flash 3.8 High. Keep tasks
small enough to preserve context.

For every task: 1. Inspect relevant files. 2. State a short plan. 3.
Implement one coherent feature. 4. Add focused tests. 5. Run
tests/analyzer. 6. Review the diff. 7. Report exact outcomes. 8. Commit
a scoped checkpoint if verified. 9. Stop before the next major feature.

Do not implement everything in one giant pass. If context/upstream
fails, inspect Git state and continue from the actual state rather than
blindly repeating edits.

When something is infeasible with current libraries/hardware, explain
why and propose the smallest viable alternative. Do not make speculative
dependency changes without checking APIs first.

------------------------------------------------------------------------

## 17. Final release acceptance checklist

### Recording and data

-   [ ] Cadence policy is consistent from the first second.
-   [ ] Diagnostics detect gaps and duplicates.
-   [ ] Participant and activity labels are captured before recording.
-   [ ] Users can add custom activities.
-   [ ] Session metadata and CSV persist reliably.
-   [ ] Filenames follow safe `participant_activity` convention with
    collision protection.
-   [ ] Stop/flush does not lose final samples.

### Export

-   [ ] Individual session export works.
-   [ ] Multi-session ZIP/manifest export and sharing work.
-   [ ] Android share sheet works.
-   [ ] Drive upload is authenticated, consent-based, and confirmed---or
    clearly marked as requiring configuration.

### Recognition and ML

-   [ ] Live predictions use actual sensor samples.
-   [ ] Wrist/ankle/combined modes use correct feature dimensions.
-   [ ] Missing/incompatible models are clearly reported.
-   [ ] KNN works.
-   [ ] Logistic Regression works where supported and is tested.
-   [ ] Models persist/reload with versioned metadata.
-   [ ] Candidate evaluation and rollback work.
-   [ ] Feedback is stored and reviewed before retraining.
-   [ ] No misleading RL claim or destructive automatic update exists.

### UI and fitness

-   [ ] All five tabs work.
-   [ ] Every visible control performs its labeled action.
-   [ ] Empty/loading/disconnected/unavailable/error states are covered.
-   [ ] Only real metrics are shown.
-   [ ] Calories are validated and labeled as estimates, or remain out
    of scope.

### Quality

-   [ ] Analyzer results reported.
-   [ ] Full test results reported.
-   [ ] Android build result reported.
-   [ ] Critical flows tested on physical hardware where possible.
-   [ ] No accidental firmware/protocol/schema/unrelated changes.
-   [ ] Git diff reviewed and final commit recorded.
-   [ ] Known limitations and external setup documented.

## Final instruction

Begin by verifying the current repository and baseline. Then execute
**Priority 1 only**. Report findings, files changed, test results, and
commit hash before proceeding to Priority 2. Do not implement the entire
document in one pass.
