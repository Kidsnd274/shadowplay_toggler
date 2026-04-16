Yes — this is viable. The stable part is **NVIDIA’s DRS profile system through NVAPI**: NVIDIA officially documents sessions, profiles, applications, settings, enumeration, save/restore, and profile hierarchy. The unstable part is **your exact target flag**: NVIDIA’s own guide says not all driver settings are publicly exposed, and the public description I found for 0x809D5F60 is community-based rather than officially documented; the clearest public report says 0x10000000 disables NVIDIA Overlay / ShadowPlay / Instant Replay for that program.

My strongest recommendations:

- Build it as a **Windows-only Flutter desktop app**.
- Use **Flutter UI + a tiny native C/C++ bridge** for NVAPI.
- Keep **your own managed list** separate from **detected NVIDIA/default rules**.
- In MVP, use a **per-app exclusion toggle**, not a global ShadowPlay toggle.
- When disabling a rule, **restore/remove the override** instead of writing 0x00000000, because the value map for this field is not officially documented.

## **What I would change from your original idea**

Your core idea is good, but I would change the model slightly:

1. The left list should **not** try to be “everything blocked in NVIDIA.”
2. The left list should be **Managed by this app** only, and it can start empty.
3. Add a second view/tab called **Detected Existing Rules**.
4. Add a third optional view/tab called **NVIDIA Defaults**.

That solves the tension you noticed: users want a clean empty list at first, but the driver may already contain predefined profiles and overrides. NVIDIA’s DRS model distinguishes predefined vs user-created profiles/apps, and the setting structure exposes whether the current value is predefined and where it came from.

## **How Flutter should connect with NVAPI**

The clean architecture is:

```
Flutter UI (Dart)
    ↓
dart:ffi
    ↓
shadowplay_bridge.dll  (your C/C++ wrapper)
    ↓
NVAPI SDK (nvapi64.lib / NvAPI_Initialize)
    ↓
NVIDIA DRS profiles/settings
```

That approach fits both sides well. NVAPI is a Windows SDK, NVIDIA says applications should link through the NVAPI library and call NvAPI_Initialize(), and Flutter’s current guidance for native code is to use dart:ffi, with package_ffi as the recommended template for native bindings.

I would **not** bind Dart directly to raw NVAPI structs. NVAPI uses opaque handles, versioned structs, wide strings, and unions. A thin native wrapper will be much easier to keep stable. Keep the NVAPI session and handles inside native code; return simple DTOs or JSON strings to Dart.

### **Native bridge responsibilities**

Your bridge should expose a very small API surface, such as:

- initializeNvapi()
- scanProfilesForSetting(settingId)
- findOrCreateRuleForExe(fullPath)
- setProfileDword(profileHandle, settingId, value)
- restoreProfileSetting(profileHandle, settingId)
- removeManagedRule(ruleId)
- exportDriverBackup(filePath)
- importDriverBackup(filePath)

That keeps Flutter focused on UI/UX and keeps all driver complexity in one place.

## **Can the app get a full list of apps currently blocked from ShadowPlay?**

**Mostly yes, with caveats.** NVAPI lets you enumerate all profiles, enumerate applications inside each profile, and query a specific setting by ID. The setting object also tells you whether the value is predefined and what location it came from, and NVIDIA documents that effective behavior depends on the hierarchy **Application Profile > Current Global Profile > Base Profile**.

So your scan logic can be:

1. Create DRS session and load settings.
2. Enumerate all profiles.
3. For each profile, get profile info.
4. Enumerate all associated applications.
5. Query 0x809D5F60.
6. Record:
  - profile name
    - app name / friendly name
    - value
    - isPredefined
    - isCurrentPredefined
    - settingLocation
7. Separately inspect Base Profile / Global Profile for inherited behavior.

Two important caveats:

- For MVP, you should only call something “Excluded” when the value is the known preset you support, such as 0x10000000.
- Unknown nonzero values should be shown as **Custom / Unknown** in Advanced mode, not interpreted as blocked/unblocked.

That keeps the UI honest.

## **Best solution to your “app reset loses track of user changes” problem**

This is the key design problem, and the honest answer is:

**You cannot perfectly reconstruct authorship after a reset for edits made to existing predefined profiles.** The published DRS profile, application, and setting structures expose names, counts, predefined flags, setting location, and current/predefined values, but they do not expose a safe free-form metadata/comment field you can use to mark “this was written by my app.” So after losing your local database, you can detect “this is a user override,” but not reliably prove whether it came from your app, NPI, or manual editing.

The best practical solution is a **hybrid model**:

### **1) Local managed database**

Store only rules your app created or adopted.

For each managed rule, store:

- full exe path
- normalized exe name
- matched profile name
- whether profile was predefined or app-created
- intended value (0x10000000 by default)
- previous state before modification
- created/updated timestamps
- driver version at write time

### **2) Transparent profile naming for app-created profiles**

If an exe is not already attached to a driver profile, create a new user profile named after the executable itself, for example:

obs64.exe

No hidden prefix or marker — the profile is visible and understandable in NVIDIA Profile Inspector or any other tool. The local SQLite database remains the authoritative record of which rules the app manages.

### **3) Reconciliation scan on startup**

On launch:

- scan the driver DB
- rebuild a detected-state snapshot
- cross-reference each managed rule in the local DB against the driver to detect drift / orphans
- place any 0x809D5F60 override that is **not** in the local DB into **Detected Existing Rules**

If the local DB is lost, there is no automatic recovery; the user sees their previous rules in **Detected** and can re-adopt them one-by-one (or with a bulk action). DB loss is rare because the SQLite file lives in the app data directory and survives uninstalls and driver updates.

### **4) “Adopt existing rule” feature**

If the app finds 0x809D5F60 overrides that are not in its DB, show them as unmanaged and let the user adopt them.

### **5) Backup / restore support**

Before first write, offer a full driver-profile backup using NvAPI_DRS_SaveSettingsToFile. NVIDIA also exposes load-from-file, delete-setting, restore-default-setting, and restore-profile-default APIs, which gives you a real rollback story.

### **6) Disable rules by restoring defaults, not by forcing zero**

Because the alternative values for 0x809D5F60 are not officially documented, the safest “off” action is to **remove the setting override** and leave everything else alone:

- if the profile is user-created (no predefined value for this setting): call `NvAPI_DRS_DeleteSetting` to delete the setting key entirely.
- if the profile is predefined by NVIDIA: call `NvAPI_DRS_RestoreProfileDefaultSetting` to restore NVIDIA's factory value.

The app never deletes profiles or removes application attachments. An "empty" profile (one with no active settings) is functionally equivalent to no profile at all because of NVIDIA's hierarchy (Application Profile > Current Global Profile > Base Profile), and leaving it in place means the next re-exclusion is just a single `SetSetting` call. This also removes any need to make destructive decisions based on our own authorship tracking.

That is much safer than assuming 0x00000000 means “off.”

## **Recommended UX**

I would not make the main toggle “ShadowPlay On/Off.” That drifts outside your app’s job and creates confusion with NVIDIA’s own overlay controls.

The main control should be:

**Exclude this app from NVIDIA Overlay / Instant Replay**

That is concrete and maps directly to the profile rule you manage.

### **Layout**

```
┌──────────────────────────────────────────────────────────────────┐
│ Capture Exclusion Manager                                        │
│ [Scan NVIDIA Profiles] [Add Program] [Backup] [Settings]         │
├──────────────────────────────┬───────────────────────────────────┤
│ Managed                      │ App: obs64.exe                    │
│ Detected Existing Rules      │ Profile: obs64.exe                │
│ NVIDIA Defaults              │ Status: Excluded                  │
│                              │                                   │
│ Search                       │ [ Exclude from Overlay ]          │
│ • obs64.exe                  │                                   │
│ • signalrgb.exe              │ Setting ID: 0x809D5F60           │
│ • paintdotnet.exe            │ Current Value: 0x10000000        │
│                              │ Source: User Override            │
│                              │                                   │
│                              │ [Restore Default] [Advanced]      │
└──────────────────────────────┴───────────────────────────────────┘
```

### **UX choices I would make**

- **Managed** starts empty.
- **Detected Existing Rules** appears after first scan.
- **NVIDIA Defaults** is collapsed or secondary so it does not clutter the main workflow.
- Right pane shows:
  - app name
  - profile name
  - status badge
  - source badge: Managed / External / NVIDIA Default / Inherited
  - current hex value
  - advanced editor
- After save, show a notice: **“Restart the target app for changes to fully apply.”** NVIDIA’s guide says driver settings are applied when the process initializes the NVIDIA DLL, so changing them mid-run may not affect an already-running target app.

### **Add-program flow**

1. User clicks **Add Program**
2. File picker chooses an .exe
3. App resolves full path and calls FindApplicationByName
4. If it already belongs to a profile:
  - show “This executable already belongs to profile X”
    - let user apply exclusion to that existing profile
5. If not found:
  - create a dedicated user profile
    - add executable
    - apply setting
6. Add rule to Managed list

That flow matters because NVIDIA documents that a given application can only be associated with a single profile, and FindApplicationByName works best with a fully qualified path.

## **Visual style**

Since NVIDIA is consolidating GeForce Experience and Control Panel functionality into the current NVIDIA app, I would use **GeForce-style green + dark blocky controls**, but with a cleaner modern layout rather than a crowded old-school utility feel.

Suggested theme direction:

- background: dark charcoal
- panels: slightly lighter graphite
- accent: NVIDIA green
- buttons: rectangular, 4–6 px radius max
- borders: visible, sharp
- typography: compact, high contrast
- icons: simple line icons, minimal decoration

A good interaction style is “tool-like, not gamer flashy.”

---

# **Draft project document**

## **Project Title**

**ShadowPlay Toggler**

## **Project Summary**

ShadowPlay Toggler is a Windows desktop application built with Flutter that provides a focused user interface for managing per-application NVIDIA capture exclusions. The app allows users to add desktop applications or games to a managed exclusion list and writes the relevant NVIDIA DRS profile setting for those applications through NVAPI. The application is not intended to replace NVIDIA’s overlay or recording software; it is a specialized front-end for editing profile-based capture exclusion behavior.

## **Problem Statement**

Some desktop applications are detected by NVIDIA’s overlay/capture stack as if they were games, which can cause Instant Replay / ShadowPlay / overlay capture behavior to attach to the wrong program. Today, users typically solve this by using NVIDIA Profile Inspector and editing an undocumented setting manually. That workflow is obscure, error-prone, and mixes user-created rules with NVIDIA’s own predefined driver profiles. Community reports identify 0x809D5F60 = 0x10000000 as a useful per-program exclusion value, but the setting itself is not officially documented by NVIDIA.

## **Technical Background**

NVIDIA officially exposes the Driver Settings (DRS) framework through NVAPI. DRS supports sessions, profiles, associated applications, settings, setting enumeration, save/load, and restore-default operations. NVIDIA documents that profiles can be predefined or user-created, that application entries can also be predefined or user-created, and that effective settings follow the hierarchy Application Profile > Current Global Profile > Base Profile. NVIDIA also documents that settings are applied when the target process initializes the NVIDIA driver, so restarting the target application may be required after changes.

## **Goals**

- Provide a simple UI for adding and removing per-app NVIDIA capture exclusions.
- Keep a clean user-managed list separate from detected NVIDIA/default rules.
- Support safe rollback by restoring defaults instead of guessing undocumented “off” values.
- Support profile scanning so users can view current driver state.
- Expose an advanced mode for raw hex editing of the target setting.

## **Non-Goals**

- Replacing NVIDIA App / GeForce Experience.
- Managing all NVIDIA driver settings.
- Guaranteeing semantic interpretation of undocumented values besides the known supported preset(s).
- Cross-platform support outside Windows.
- Global ShadowPlay enable/disable control in MVP.

## **Target Platform**

- Windows desktop only
- NVIDIA GPU + NVIDIA drivers installed
- Flutter desktop frontend
- Native C/C++ NVAPI bridge for driver access

NVAPI is documented as a Windows SDK, and current NVAPI documentation lists Windows 10+ support. Flutter desktop supports Windows and Flutter recommends FFI for native-library bindings.

## **Core Features**

### **MVP**

- Scan NVIDIA DRS profiles
- Display managed exclusions
- Add executable to exclusion list
- Create user profile if needed
- Modify existing profile if executable already has one
- Apply supported exclusion value (0x10000000)
- Remove exclusion by restoring default / deleting managed profile
- Backup current DRS settings to file
- Show advanced raw hex editor for 0x809D5F60

### **Post-MVP**

- Adopt unmanaged existing rules
- Batch enable/disable managed rules
- Import/export app-managed rule database
- Preset support for additional values if trustworthy mappings are discovered
- Rule notes/tags in local database

## **User Experience**

The application uses a two-pane layout.

### **Left Pane**

Contains tabs:

- Managed
- Detected Existing Rules
- NVIDIA Defaults

The Managed tab is the default and starts empty on first run. This keeps the first-run experience simple while still allowing power users to inspect the driver state.

### **Right Pane**

Shows the selected rule details:

- executable name
- full path
- matched profile name
- current setting value
- source type
- primary exclusion toggle
- restore default button
- advanced editor

### **Main User Flow**

1. User opens app
2. Managed list is empty
3. User clicks Add Program
4. User selects executable
5. App checks whether executable already belongs to a profile
6. App creates or updates the rule
7. Rule appears in Managed list
8. App prompts the user to restart the target application if it is running

## **Technical Architecture**

The frontend will be written in Flutter. NVAPI access will be handled through a native Windows bridge written in C/C++. Flutter will call the bridge through dart:ffi. This avoids exposing raw NVAPI handles and complex structures directly to Dart and keeps the native interface stable and narrow. NVAPI documentation states that applications should link through the NVAPI library and call NvAPI_Initialize(), while Flutter’s native-binding guidance recommends FFI for this kind of integration.

### **Native Bridge Responsibilities**

- initialize and shut down NVAPI
- create/load/save DRS sessions
- enumerate profiles
- enumerate applications
- get/set/delete/restore settings
- export/import driver settings backups
- normalize and resolve executable paths
- convert NVAPI data to simple DTOs for Flutter

## **Data Model and Persistence**

The app will use a **hybrid persistence model**:

### **Driver State**

The NVIDIA driver database remains the source of truth for current effective profile settings.

### **Local App State**

The app stores only managed metadata:

- executable path
- profile name
- profile type
- intended exclusion value
- previous state for rollback
- timestamps
- adopted/created status

### **Recovery Strategy**

On startup, the app scans the driver DB and reconciles:

- each rule in the local DB is cross-referenced against the driver to classify it as in-sync, drifted, or orphaned
- existing overrides outside the DB are shown as unmanaged detected rules
- users can adopt unmanaged rules into app management, which doubles as the recovery path if the local DB was lost

This design is necessary because the published DRS structures expose predefined/user flags and current/predefined values, but do not expose a safe arbitrary metadata field for tagging existing profiles as “owned” by this app. Rather than embedding our ownership claim in a profile-name prefix, we rely on the local SQLite database as the source of truth for managed rules and on manual adoption as the recovery path.

## **Safety and Rollback**

Before making the first driver modification, the app should offer a backup of current DRS settings using the NVAPI save-to-file API. When disabling or removing a managed rule, the app should delete the setting key (for user-created profiles) or restore it to its predefined default (for NVIDIA predefined profiles), rather than forcing a zero value. The app does not delete profiles or remove application attachments when disabling a rule — an empty profile is functionally a no-op under NVIDIA's hierarchy, and keeping it in place makes re-exclusion cheap. NVAPI exposes save/load, delete-setting, restore-profile-default, and restore-profile-default-setting operations for this purpose.

## **Advanced Mode**

Advanced mode will expose:

- raw setting ID
- raw hex value editor
- current value
- predefined/current source info
- reset to default
- optional enum-based dropdown if NVAPI returns a trustworthy value list for the setting

Because undocumented settings may not have a public semantic map, advanced mode should present raw hex values honestly and warn that behavior may vary by driver version. NVAPI does provide APIs for enumerating available setting IDs, names, and values where available.

## **Risks**

- The target setting is undocumented and may change or disappear across driver versions.
- Community reports show both setting drift and save failures on some driver versions.
- Existing predefined profiles make provenance tracking imperfect after local-state loss.
- Some app matches may be more complex than a simple .exe filename because DRS app entries also support launcher, command-line, Metro, and folder-based fields.

## **Mitigations**

- Detect whether the target setting exists on the current driver before enabling write features.
- Keep Advanced mode explicit and cautious.
- Offer backup/restore before writes.
- Separate managed rules from detected/default rules.
- Use full executable paths during lookup to avoid ambiguous matches.
- Prefer restore-default over hardcoded “off” values.

## **Success Criteria**

The MVP is successful if a user can:

- add an executable to the managed list
- apply the known exclusion value to the correct NVIDIA profile
- remove the rule safely
- recover app-created rules after an app reset via scan/reconciliation
- inspect detected existing driver overrides without confusion

The most important architectural decision is this: **treat the NVIDIA driver database as the source of truth for current state, and your local app database as the source of user intent, recovery, and rollback.**