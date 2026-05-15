# SAVA - Smart Alzheimer Virtual Assistant

A real-time patient monitoring system for Alzheimer's patients that combines **face recognition**, **person tracking**, **activity recognition**, and **alert management** into a unified platform.

## Architecture Overview

The system consists of three services:

| Service | Port | Description |
|---------|------|-------------|
| **Django Backend** | `8000` | REST API, MongoDB storage, alert management |
| **AI Face Server** | `5000` | Face recognition, person tracking (FastAPI) |
| **Camera System** | — | Real-time activity recognition via webcam |

```
Camera (YOLO + MediaPipe + SkateFormer)
    |
    |--- face crop --> AI Face Server (port 5000) --> identifies patient
    |
    |--- activity events --> Django API (port 8000) --> stores events + sends alerts
    |
Frontend (React/Mobile)
    |
    |--- REST calls --> Django API (port 8000) --> auth, patients, alerts, events
```

### User Roles

| Role | Description |
|------|-------------|
| **ADMIN** | Set caregiver salaries, delete users, view all caregivers/users |
| **RELATIVE** | Primary: create patients, assign caregivers, manage relatives, edit meds, acknowledge alerts. Secondary: view monitoring and med schedules |
| **CAREGIVER** | Accept/decline offers, monitor patients (max 4), edit med schedules, acknowledge alerts |

**Patient** is a separate profile document (not a user), created and owned by a primary relative.

---

## Prerequisites

- **Python 3.13** (Django backend + AI face server)
- **Python 3.10** (Camera system — required for MediaPipe compatibility)
- **MongoDB** (Atlas or local)
- **CMake** and **Visual Studio Build Tools** (required by `dlib` / `face_recognition` on Windows)

---

## Installation

### 1. Django Backend (Python 3.13)

```bash
# From project root
python -m venv venv313
.\venv313\Scripts\activate    # Windows
# source venv313/bin/activate # Linux/macOS

pip install django
pip install djangorestframework
pip install mongoengine
pip install python-dotenv
pip install requests
```

### 2. AI Face Server (Python 3.13)

```bash
cd ai_face_server
pip install fastapi
pip install uvicorn
pip install python-multipart
pip install face_recognition
pip install scikit-learn
pip install joblib
pip install opencv-python
pip install numpy
```

> **Note:** `face_recognition` requires `dlib`, which needs CMake and C++ build tools installed.

### 3. Camera System (Python 3.10)

```bash
# Must use Python 3.10 for MediaPipe compatibility
python3.10 -m venv venv310
.\venv310\Scripts\activate

pip install numpy==2.4.2
pip install opencv-python==4.13.0.92
pip install torch>=2.0.0
pip install torchvision>=0.15.0
pip install mediapipe>=0.10.0
pip install ultralytics>=8.0.0
pip install timm>=0.9.0
pip install tqdm>=4.0.0
pip install pyyaml>=6.0
pip install requests
```

### 4. Additional Files Required

- **YOLOv8 model**: Place `yolov8n.pt` in the project root
- **SkateFormer checkpoint**: Place at `perception/activity_recognition/work_dir/sava_9class/best_9class.pt`
- **SkateFormer source**: `SkateFormer/SkateFormer-main/` directory with model code

---

## Environment Variables

Create a `.env` file in the project root:



## Running the Services

### 1. Start Django Backend

```bash
.\venv313\Scripts\activate
python manage.py runserver
# Runs on http://localhost:8000
```

### 2. Start AI Face Server

```bash
.\venv313\Scripts\activate
cd ai_face_server
uvicorn ai_face_server:app --host 127.0.0.1 --port 5000
# Runs on http://localhost:5000
```

### 3. Start Camera System

```bash
.\venv310\Scripts\python main.py
# Opens webcam window with real-time activity recognition
```

The camera will display:
- **"Patient: Identifying..."** until face recognition matches a known person
- **"Patient: {name}"** once identified, then starts sending activity alerts
- Activity labels (SIT, STAND, WALK, EAT, etc.) with confidence percentages
- Alert overlays for FALL and WANDERING detection

---

## API Endpoints Reference

**Base URL:** `http://localhost:8000/api`

### Authentication

#### Sign Up Relative
```
POST /api/auth/signup/relative
Content-Type: application/json
```

```json
{
  "name": "Ahmed",
  "username": "ahmed01",
  "email": "ahmed@test.com",
  "password": "Pass1234",
  "confirm_password": "Pass1234"
}
```

#### Sign Up Caregiver
```
POST /api/auth/signup/caregiver
Content-Type: multipart/form-data
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Full name |
| `username` | string | Yes | Unique username |
| `email` | string | Yes | Unique email |
| `password` | string | Yes | Password |
| `confirm_password` | string | Yes | Must match password |
| `age` | integer | Yes | Age |
| `national_id` | string | Yes | National ID |
| `cv` | file | No | CV PDF upload |

#### Login
```
POST /api/auth/login
Content-Type: application/json
```

```json
{
  "email": "ahmed@test.com",
  "password": "Pass1234"
}
```

---

### Users

#### Search Users by Username
```
GET /api/users/search?q=<query>&role=RELATIVE|CAREGIVER
```

Both parameters are optional. Returns users whose username contains the query string.

#### Get User Details
```
GET /api/users/<user_id>
```

**Response:**
```json
{
  "id": "...",
  "name": "Ahmed",
  "username": "ahmed01",
  "email": "ahmed@test.com",
  "role": "RELATIVE",
  "face_video_path": null,
  "age": null,
  "national_id": null,
  "cv_path": null,
  "salary_per_hour": null,
  "created_at": "2026-05-11T14:00:00Z",
  "updated_at": "2026-05-11T14:00:00Z"
}
```

---

### Patient Profiles

#### Create Patient (primary relative only)
```
POST /api/patients
Content-Type: application/json
```

```json
{
  "relative_id": "<primary_relative_id>",
  "name": "Grandpa",
  "date_of_birth": "1950-03-15",
  "gender": "MALE",
  "current_medication": "Aspirin"
}
```

#### List Patients for a Relative
```
GET /api/patients?relative_id=<user_id>
```

#### Get Patient Details
```
GET /api/patients/<patient_id>
```

#### Update Patient (primary relative only)
```
PATCH /api/patients/<patient_id>
Content-Type: application/json
```

```json
{
  "user_id": "<primary_relative_id>",
  "name": "Updated Name",
  "current_medication": "Aspirin, Metformin"
}
```

---

### Relative Management

#### List Relatives for a Patient
```
GET /api/patients/<patient_id>/relatives
```

#### Add Relative to Patient (primary relative only)
```
POST /api/patients/<patient_id>/relatives
Content-Type: application/json
```

```json
{
  "requester_id": "<primary_relative_id>",
  "username": "mona02",
  "role_type": "SECONDARY"
}
```

#### Remove Relative from Patient (primary relative only)
```
DELETE /api/patients/<patient_id>/relatives?requester_id=<id>&username=<username>
```

---

### Caregiver Contracts

#### List Available Caregivers (< 4 active contracts)
```
GET /api/caregivers/available
```

#### Send Caregiver Offer (primary relative only)
```
POST /api/patients/<patient_id>/caregiver-offer
Content-Type: application/json
```

```json
{
  "requester_id": "<primary_relative_id>",
  "caregiver_id": "<caregiver_id>"
}
```

#### Respond to Offer (caregiver only)
```
PATCH /api/contracts/<contract_id>/respond
Content-Type: application/json
```

```json
{
  "caregiver_id": "<caregiver_id>",
  "action": "ACCEPT"
}
```

Actions: `ACCEPT` or `DECLINE`

#### End Contract
```
POST /api/contracts/<contract_id>/end
Content-Type: application/json
```

```json
{ "user_id": "<requester_id>" }
```

#### List Caregiver's Patients
```
GET /api/caregivers/<caregiver_id>/patients
```

---

### Medication Schedule

#### Get Medication Schedule
```
GET /api/patients/<patient_id>/medication
```

#### Create / Update Medication Schedule
```
PUT /api/patients/<patient_id>/medication
Content-Type: application/json
```

```json
{
  "user_id": "<primary_relative_or_caregiver_id>",
  "entries": [
    {
      "medicine_name": "Aspirin",
      "time_to_consume": "08:00",
      "dosage": "100mg",
      "notes": "After breakfast"
    }
  ]
}
```

---

### Admin

#### List All Caregivers
```
GET /api/admin/caregivers
```

#### Set Caregiver Salary
```
PATCH /api/admin/caregivers/<caregiver_id>/salary
Content-Type: application/json
```

```json
{
  "admin_id": "<admin_id>",
  "salary_per_hour": 50.0
}
```

#### List All Users (filter by role)
```
GET /api/admin/users?role=RELATIVE|CAREGIVER|ADMIN
```

#### Delete User
```
DELETE /api/admin/users/<user_id>
Content-Type: application/json
```

```json
{ "admin_id": "<admin_id>" }
```

---

### Frame Ingestion (Face Analysis)

```
POST /api/frames/ingest
Content-Type: multipart/form-data
```

| Field | Type | Description |
|-------|------|-------------|
| `patient_id` | string | Patient being monitored |
| `frame` | file | Image frame (JPEG/PNG) |

**Response:**
```json
{
  "detail": "Frame processed.",
  "event": {
    "id": "...",
    "patient_id": "...",
    "event_type": "FACE",
    "confidence": 0.93,
    "payload": { "known": true, "person_name": "john" },
    "created_at": "2026-05-11T10:30:00Z"
  },
  "alerts_created": 0
}
```

---

### Person Tracking

#### Track a Person in a Frame
```
POST /api/person-tracking/track
Content-Type: multipart/form-data
```

| Field | Type | Description |
|-------|------|-------------|
| `patient_id` | string | Patient being monitored |
| `frame` | file | Image frame |

#### Get Active Persons
```
GET /api/person-tracking/active?patient_id=<id>&minutes=10
```

#### Cleanup Old Tracking Records
```
POST /api/person-tracking/cleanup
Content-Type: application/json
```

```json
{ "patient_id": "...", "hours": 24 }
```

---

### Activity Recognition

#### Submit Activity Event (used by Camera system)
```
POST /api/activity-recognition/event
Content-Type: application/json
```

```json
{
  "patient_id": "<patient_id>",
  "activity": "FALL",
  "confidence": 0.85
}
```

Supported activities: `EAT`, `DRINK`, `SLEEP`, `FALL`, `WALK`, `SIT`, `STAND`, `USE_PHONE`, `CHEST_PAIN`

> **Alert-triggering activities:** `FALL` and `CHEST_PAIN` automatically create alerts sent to the active caregiver and all linked relatives.

#### Get Activity History
```
GET /api/activity-recognition/history?patient_id=<id>&minutes=60
```

#### Patient Lookup by Name (used by Camera system)
```
GET /api/activity-recognition/patient-lookup?name=<person_name>
```

Used internally by the camera system to resolve face recognition results to a patient ID. The `name` parameter is matched case-insensitively against patient names.

---

### Alerts

#### List Alerts
```
GET /api/alerts?patient_id=<id>&recipient_id=<id>&status=NEW|SEEN|DISMISSED
```

All query parameters are optional. Returns up to 200 alerts, newest first.

**Response:**
```json
[
  {
    "id": "...",
    "patient_id": "...",
    "recipient_id": "...",
    "event_id": "...",
    "alert_type": "FALL_DETECTED",
    "message": "URGENT: Patient fall detected with 85% confidence. Immediate attention required.",
    "status": "NEW",
    "created_at": "2026-05-11T10:30:00Z"
  }
]
```

#### Get / Update Alert
```
GET   /api/alerts/<alert_id>
PATCH /api/alerts/<alert_id>
```

**PATCH body:**
```json
{ "status": "SEEN" }
```

Status options: `NEW`, `SEEN`, `DISMISSED`

---

### AI Face Server Endpoints

**Base URL:** `http://localhost:5000`

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/training-status` | GET | Check model training status |
| `/enroll-relative` | POST | Upload video to enroll a known person |
| `/analyze-face` | POST | Identify a face in an image |
| `/track-person` | POST | Get face embedding + bounding box |

#### Enroll a Relative
```
POST /enroll-relative
Content-Type: multipart/form-data
```

| Field | Type | Description |
|-------|------|-------------|
| `person_name` | string | Name of the person (must match a Patient name for camera linking) |
| `video` | file | Video of the person's face |

#### Analyze Face
```
POST /analyze-face
Content-Type: multipart/form-data
```

| Field | Type | Description |
|-------|------|-------------|
| `patient_id` | string | Patient context |
| `frame` | file | Image containing a face |

---

## Frontend Integration Guide

### Typical Frontend Flow

1. **Sign up** a relative via `POST /api/auth/signup/relative`
2. **Login** via `POST /api/auth/login`
3. **Create a patient** via `POST /api/patients`
4. **Search for a caregiver** via `GET /api/users/search?q=<username>&role=CAREGIVER`
5. **Send caregiver offer** via `POST /api/patients/{pid}/caregiver-offer`
6. **Caregiver accepts** via `PATCH /api/contracts/{cid}/respond`
7. **Add medication schedule** via `PUT /api/patients/{pid}/medication`
8. **Enroll known faces** via `POST localhost:5000/enroll-relative` (upload video)
9. **Start the camera** — it automatically identifies the patient and sends activity events
10. **Poll for alerts** via `GET /api/alerts?recipient_id={uid}&status=NEW`
11. **Mark alerts** via `PATCH /api/alerts/{aid}` with `{"status": "SEEN"}` or `{"status": "DISMISSED"}`
12. **View activity history** via `GET /api/activity-recognition/history?patient_id={pid}`
13. **Add secondary relatives** via `POST /api/patients/{pid}/relatives` using their username

### Example: Fetching Alerts (JavaScript)

```javascript
// Fetch new alerts for a user (caregiver or relative)
const response = await fetch(
  'http://localhost:8000/api/alerts?recipient_id=USER_ID&status=NEW'
);
const alerts = await response.json();

// Mark an alert as seen
await fetch(`http://localhost:8000/api/alerts/${alertId}`, {
  method: 'PATCH',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ status: 'SEEN' })
});
```

### Example: Getting Activity History (JavaScript)

```javascript
const response = await fetch(
  'http://localhost:8000/api/activity-recognition/history?patient_id=PATIENT_ID&minutes=60'
);
const data = await response.json();
// data.events = [{ event_type, confidence, payload, created_at }, ...]
```

### Example: Enrolling a Relative (JavaScript)

```javascript
const formData = new FormData();
formData.append('person_name', 'mostafa');
formData.append('video', videoFile);

const response = await fetch('http://localhost:5000/enroll-relative', {
  method: 'POST',
  body: formData
});
```

---

## Data Models

### User
| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Full name |
| `username` | string | Unique username (used for search/identification) |
| `email` | string | Unique email |
| `password_hash` | string | Hashed password (PBKDF2) |
| `role` | string | `ADMIN`, `CAREGIVER`, or `RELATIVE` |
| `face_video_path` | string | Path to uploaded face video |
| `age` | integer | Caregiver only |
| `national_id` | string | Caregiver only |
| `cv_path` | string | Caregiver only |
| `salary_per_hour` | float | Set by admin |

### Patient
| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Patient's full name |
| `date_of_birth` | datetime | Date of birth |
| `gender` | string | `MALE` or `FEMALE` |
| `current_medication` | string | Current medications |
| `face_video_path` | string | Path to face enrollment video |
| `created_by` | ref | Reference to the primary relative who created the patient |

### PatientRelativeLink
| Field | Type | Description |
|-------|------|-------------|
| `patient` | ref | Reference to Patient |
| `relative` | ref | Reference to User (RELATIVE) |
| `role_type` | string | `PRIMARY` (max 2) or `SECONDARY` |

### CaregiverContract
| Field | Type | Description |
|-------|------|-------------|
| `patient` | ref | Reference to Patient |
| `caregiver` | ref | Reference to User (CAREGIVER) |
| `offered_by` | ref | Reference to User who made the offer |
| `status` | string | `PENDING`, `ACTIVE`, `DECLINED`, or `ENDED` |

### MedicationSchedule
| Field | Type | Description |
|-------|------|-------------|
| `patient` | ref | Reference to Patient |
| `entries` | list | Embedded list of MedicationEntry |
| `created_by` | ref | Reference to User who created it |

### MedicationEntry (embedded)
| Field | Type | Description |
|-------|------|-------------|
| `medicine_name` | string | Name of the medicine |
| `time_to_consume` | string | Time (e.g. "08:00") |
| `dosage` | string | Dosage (e.g. "100mg") |
| `notes` | string | Optional notes |

### Event
| Field | Type | Description |
|-------|------|-------------|
| `patient` | ref | Reference to Patient |
| `event_type` | string | `FACE`, `FALL`, `OBJECT`, `PERSON_ENTER`, `PERSON_EXIT`, `ACTIVITY` |
| `confidence` | float | 0.0 - 1.0 |
| `payload` | dict | Event-specific data |
| `person_tracking` | ref | Optional reference to PersonTracking |

### PersonTracking
| Field | Type | Description |
|-------|------|-------------|
| `patient` | ref | Reference to Patient |
| `tracking_id` | string | Unique tracking identifier |
| `status` | string | `NEW`, `PROCESSING`, `IDENTIFIED`, `UNKNOWN` |
| `person_name` | string | Identified person name |
| `confidence` | float | 0.0 - 1.0 |

### Alert
| Field | Type | Description |
|-------|------|-------------|
| `patient` | ref | Reference to Patient |
| `recipient` | ref | Reference to User (caregiver or relative) |
| `event` | ref | Reference to triggering Event |
| `alert_type` | string | e.g. `FALL_DETECTED`, `CHEST_PAIN_DETECTED`, `UNKNOWN_FACE` |
| `message` | string | Human-readable alert message |
| `status` | string | `NEW`, `SEEN`, or `DISMISSED` |

---

## Project Structure

```
Sava/
├── config/                      # Django settings, URLs, WSGI
│   ├── settings.py
│   ├── urls_config.py
│   └── wsgi.py
├── apps/
│   ├── accounts/                # Auth, users, patients, relatives, caregivers, admin
│   │   ├── urls.py
│   │   ├── views/               # Domain-specific view modules
│   │   │   ├── __init__.py
│   │   │   ├── views_auth.py        # Login, signup, user search
│   │   │   ├── views_patient.py     # Patient CRUD
│   │   │   ├── views_relative.py    # Relative management
│   │   │   ├── views_caregiver.py   # Contracts, medication, available caregivers
│   │   │   ├── views_admin.py       # Admin actions
│   │   │   └── helpers.py           # Serialization helpers, error handler
│   │   ├── serializers/         # Domain-specific serializer modules
│   │   │   ├── __init__.py
│   │   │   ├── auth.py              # Login, signup serializers
│   │   │   ├── patient.py           # Patient CRUD serializers
│   │   │   ├── relative.py          # AddRelativeSerializer
│   │   │   ├── caregiver.py         # Contract, medication serializers
│   │   │   ├── admin.py             # SetSalarySerializer
│   │   │   └── common.py            # UserResponse, AlertUpdate serializers
│   │   └── services/            # Domain-specific service modules
│   │       ├── base.py              # Shared helpers, custom exceptions
│   │       ├── auth_service.py      # Registration, login, user search
│   │       ├── patient_service.py   # Patient CRUD
│   │       ├── relative_service.py  # Add/remove relatives
│   │       ├── caregiver_service.py # Contracts, medication, alert recipients
│   │       └── admin_service.py     # Salary, user deletion
│   └── monitoring/              # Events, alerts, person tracking, activity recognition
│       ├── urls.py
│       ├── models/              # Domain-specific model modules
│       │   ├── __init__.py
│       │   ├── user.py              # User model (ADMIN/CAREGIVER/RELATIVE)
│       │   ├── patient.py           # Patient, PatientRelativeLink
│       │   ├── caregiver.py         # CaregiverContract, MedicationSchedule
│       │   ├── tracking.py          # PersonTracking
│       │   └── events.py            # Event, Alert
│       ├── serializers.py
│       ├── views.py                 # Frame ingestion
│       ├── views_alerts.py          # Alert CRUD
│       ├── views_person_tracking.py # Person tracking
│       ├── views_activity.py        # Activity events + patient lookup
│       └── services/
│           ├── ai_client.py             # HTTP client for AI face server
│           ├── alert_service.py         # Alert creation + cooldowns
│           ├── event_service.py         # Event creation
│           └── person_tracking_service.py
├── ai_face_server/              # FastAPI face recognition server
│   ├── ai_face_server.py
│   ├── requirements.txt
│   ├── models/                  # Trained SVM classifier artifacts
│   └── uploads/                 # Enrolled face data
│       └── relatives/<name>/    # Per-person face crops + embeddings
├── perception/
│   └── activity_recognition/    # Camera + SkateFormer activity recognition
│       ├── camera.py                # Main camera loop with face ID + tracking
│       ├── config.py                # Camera and detection settings
│       ├── detector.py              # YOLO person detection
│       ├── pose_estimator.py        # MediaPipe pose estimation
│       └── work_dir/                # Model checkpoints
├── SkateFormer/                 # SkateFormer model source (git submodule)
├── main.py                      # Entry point for camera system
├── manage.py                    # Django management
├── requirements.txt             # Camera system dependencies
└── .env                         # Environment variables
```
