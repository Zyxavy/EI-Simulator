# Product Requirements Document

## EI Simulator
**Version:** 0.1.0  
**Date:** August 2026  
**Status:** In Development  

---

## 1. Overview

Epstien Island Simulator is a mobile application that visualizes romantic relationships between people as an interactive, Obsidian-inspired node graph. Each person is represented as a draggable node on a canvas; directed edges represent romantic interest between them. The app supports full CRUD operations and search functionality, backed by a local SQLite database via SQFlite.

---

## 2. Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) |
| Local DB | SQFlite `^2.4.3` |
| Graph Display | graphview `^1.5.1` |
| State Management | Provider `^6.1.5+1` |
| Image Picking | image_picker `^1.2.3` |
| ID Generation | uuid `^4.6.0` |
| Path Utilities | path `^1.9.1` |
| Lints | flutter_lints `^6.0.0` |
| Min Dart SDK | `^3.13.1` |

---

## 3. Data Models

### 3.1 Person
Represents a node on the graph.

| Field | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | Auto-increment |
| `name` | TEXT | Required |
| `description` | TEXT | 1–2 sentences |
| `personality` | TEXT | Comma-separated tags e.g. `"Tsundere, Chaotic"` |
| `imagePath` | TEXT | Path to profile image in app storage |
| `createdAt` | TEXT | ISO 8601 datetime string |

### 3.2 Relationship
Represents a directed edge between two Person nodes.

| Field | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | Auto-increment |
| `fromPersonId` | INTEGER FK | The person who has the feeling |
| `toPersonId` | INTEGER FK | The person they like |
| `label` | TEXT | e.g. `"Crush"`, `"Ex"`, `"Situationship"` |
| `isMutual` | INTEGER | Boolean, `0` = one-sided, `1` = mutual |
| `createdAt` | TEXT | ISO 8601 datetime string |

> **Constraint:** `UNIQUE(fromPersonId, toPersonId)`, no duplicate directed pairs.  
> **Mutual logic:** Before inserting A - B, check if B - A exists. If yes, set `isMutual = 1` on that row instead of inserting a new one.

### 3.3 RelationshipImage
Stores multiple "together" photos attached to a single relationship.

| Field | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | Auto-increment |
| `relationshipId` | INTEGER FK | References `Relationship.id` |
| `imagePath` | TEXT | Path to image in app storage |

---

## 4. Features

### 4.1 Graph View *(Core Feature)*
- Displays all Person records as circular avatar nodes on a dark canvas
- Displays all Relationship records as directed edges (arrows) between nodes
- **One-sided relationship:** single arrow, neutral color
- **Mutual relationship:** double-headed arrow or distinct color/heart icon
- Nodes are draggable and pannable via `InteractiveViewer`
- Tapping a node navigates to that person's Profile Screen
- FAB to add a new person
- Empty state when no persons exist

### 4.2 Profile View *(Read)*
- Full profile: image, name, description, personality tags
- "Loves" section: list of persons this node has feelings for, with relationship label
- "Loved By" section: list of persons who have feelings for this node
- Horizontal gallery of relationship images
- Edit button -> Edit Person Screen
- Delete button -> confirmation dialog -> cascading delete (person + their relationships + relationship images)
- Add Relationship button -> Add Relationship Screen

### 4.3 Add / Edit Person *(Create + Update)*
- Profile image picker
- Name field (required)
- Description field
- Personality field (comma-separated tags)
- Save -> inserts or updates Person record
- Form validation: name must not be empty

### 4.4 Add / Edit Relationship *(Create + Update)*
- Person picker for "From" (cannot be same as "To")
- Person picker for "To"
- Label text field
- isMutual toggle switch
- Relationship image upload: add multiple images, displayed as a scrollable row, tap to remove
- Save -> runs mutual check logic, then inserts or updates

### 4.5 Delete
- **Delete Person:** confirmation dialog -> deletes Person, all their Relationships, and all RelationshipImages attached to those relationships (cascading)
- **Delete Relationship:** from Profile Screen -> removes edge from graph
- **Remove Relationship Image:** tap image in gallery -> removes single image

### 4.6 Search
- Search bar queries Person records by `name` or `personality`
- Results displayed as a flat list (avatar + name + personality preview)
- Tap result -> navigate to Profile Screen
- Empty state for no results

---

## 5. Screens

| Screen | Purpose | Route |
|---|---|---|
| `GraphScreen` | Main canvas: nodes and edges | `/` (home) |
| `ProfileScreen` | View person details | `/profile` |
| `AddEditPersonScreen` | Create or update a person | `/person/add`, `/person/edit` |
| `AddEditRelationshipScreen` | Create or update a relationship | `/relationship/add`, `/relationship/edit` |
| `SearchScreen` | Search persons | `/search` |

---

## 6. Reusable Widgets

| Widget | Description |
|---|---|
| `PersonNode` | Circular avatar with glow/border, used on graph canvas |
| `EdgePainter` | CustomPainter for drawing directed edges |
| `PersonCard` | Avatar + name + personality: used in search results and pickers |
| `RelationshipChip` | Small label badge (e.g. "Crush") |
| `PersonPicker` | Modal/dropdown to select a Person from DB |
| `ImageGallery` | Horizontal scrollable row of relationship photos |
| `ProfileImagePicker` | Tappable image circle that opens image picker |
| `PersonalityTag` | Single chip for one personality trait |
| `MutualToggle` | Styled toggle switch for isMutual field |
| `DeleteConfirmDialog` | Reusable confirmation dialog for destructive actions |
| `EmptyState` | Placeholder shown on empty graph or no search results |

---

## 7. Architecture

```
lib/
├── main.dart
├── models/
│   ├── person.dart
│   ├── relationship.dart
│   └── relationship_image.dart
├── database/
│   └── db_helper.dart
├── services/
│   └── mock_data_service.dart
├── providers/
│   └── person_provider.dart
├── screens/
│   ├── graph_screen.dart
│   ├── profile_screen.dart
│   ├── add_edit_person_screen.dart
│   ├── add_edit_relationship_screen.dart
│   └── search_screen.dart
├── widgets/
│   ├── person_node.dart
│   ├── edge_painter.dart
│   ├── person_card.dart
│   ├── relationship_chip.dart
│   ├── person_picker.dart
│   ├── image_gallery.dart
│   ├── profile_image_picker.dart
│   ├── personality_tag.dart
│   ├── mutual_toggle.dart
│   ├── delete_confirm_dialog.dart
│   └── empty_state.dart
└── data/
    └── seed_data.dart
```

---

## 8. Seed Data (First Launch)

On first install, the database is seeded with:
- **3 Person records**: the 3 groupmates, with name, description, personality, and profile image
- **At least 3 Relationship records**: forming a love triangle (A->B, B->C, C->A) with at least one mutual pair
- **At least 2 RelationshipImage records** per relationship

Seed runs once, gated by a shared preference flag `db_seeded`.

---

## 9. CRUD Summary

| Operation | Where |
|---|---|
| **Create Person** | FAB on Graph Screen -> Add Person Screen |
| **Create Relationship** | Add Relationship button on Profile Screen |
| **Read Person** | Tap node on Graph Screen -> Profile Screen |
| **Read All** | Graph Screen (all nodes + edges) |
| **Search** | Search Screen |
| **Update Person** | Edit button on Profile Screen |
| **Update Relationship** | Edit on relationship entry in Profile Screen |
| **Update isMutual** | Automatic on insert; manual via Edit Relationship |
| **Delete Person** | Delete button on Profile Screen (cascading) |
| **Delete Relationship** | On Profile Screen relationship entry |
| **Delete Relationship Image** | Tap image in gallery |

---

## 10. Out of Scope

These are explicitly NOT part of this version:

- Cloud sync or backend
- Authentication / user accounts
- Notifications
- Animations beyond basic transitions (polish phase only)
- Web or desktop support
- Exporting or sharing data