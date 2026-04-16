# 19 - Search and Filter

## Goal

Add a search bar to the left pane that filters rules across all tabs.

## Prerequisites

- Plan 15 (Left Pane Tabs) completed.
- Plan 16 (Managed Rules List) completed.

## Tasks

1. **Add a search field to the left pane**
   - Place a `TextField` above the tab bar in `lib/widgets/left_pane.dart`.
   - Style with the app theme: dark background, grey border, green focus color.
   - Search icon prefix, clear button suffix when text is present.
   - Compact height to not take too much space.

2. **Create a search provider**
   - Create `lib/providers/search_provider.dart`.
   - `StateProvider<String>` for the current search query.

3. **Implement filtering logic**
   - Filter rules by matching the search query against:
     - Executable name (primary match)
     - Executable path
     - Profile name
   - Case-insensitive substring matching.
   - Apply the filter to whichever tab is currently active.

4. **Update list providers to support filtering**
   - Create derived/computed providers that combine the base rule list with the search query:
     ```dart
     final filteredManagedRulesProvider = Provider<List<ManagedRule>>((ref) {
       final rules = ref.watch(managedRulesProvider);
       final query = ref.watch(searchProvider);
       if (query.isEmpty) return rules;
       return rules.where((r) => r.exeName.toLowerCase().contains(query.toLowerCase())).toList();
     });
     ```
   - Do the same for detected rules and NVIDIA defaults.

5. **Update tab content widgets**
   - `ManagedRulesTab`, `DetectedRulesTab`, and `NvidiaDefaultsTab` should watch the filtered providers instead of the raw providers.

6. **Show "no results" state when filter matches nothing**
   - Display "No rules matching 'query'" message.
   - Different from the empty/pre-scan state.

7. **Keyboard shortcut (nice-to-have)**
   - Ctrl+F focuses the search field.
   - Escape clears the search and unfocuses.

## Acceptance Criteria

- Search field appears above the tabs in the left pane.
- Typing filters the active tab's list in real-time.
- Clearing the search restores the full list.
- Filtering works across exe name, path, and profile name.
- "No results" state is shown when filter matches nothing.
- `flutter analyze` reports no errors.
