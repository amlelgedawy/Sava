# SAVA - Smart Patient Monitoring System

A comprehensive AI-powered patient monitoring system with face recognition, person tracking, and dangerous object detection capabilities.

##  Features

### **Person Tracking AI**
- **Face Detection**: Detects faces in real-time video frames
- **Unique ID Assignment**: Assigns persistent tracking IDs to detected persons
- **One-time Recognition**: Performs facial recognition only when new person detected
- **Cross-frame Tracking**: Tracks persons across multiple frames
- **Distance Optimization**: Enhanced detection for monitoring cameras (40px minimum face size)

### **Face Recognition System**
- **Enhanced Distance Detection**: Works with smaller/distant faces
- **Image Preprocessing**: CLAHE enhancement and sharpening
- **Multi-stage Detection**: Original → Enhanced → CNN fallback
- **HOG Model**: Optimized for small face detection
- **Tolerance Adjustment**: 0.6 tolerance for distant face matching

### **Dangerous Object Detection**
- **12 Object Categories**: Weapons, sharp objects, medical items, etc.
- **Severity Classification**: Critical, high, medium, low priority levels
- **Real-time Alerts**: Immediate caregiver notification
- **External AI Integration**: Ready for third-party object detection AI

### **Alert System**
- **Multi-type Alerts**: Unknown persons, dangerous objects
- **Smart Filtering**: Only relevant events trigger alerts
- **Cooldown Protection**: Prevents alert spam
- **Caregiver Notification**: Alerts sent to all linked caregivers
- **Event Tracking**: Complete audit trail

## 🛠️ Setup & Installation

### **Prerequisites**
```bash
# Python 3.8+
pip install -r requirements.txt

# MongoDB
mongod

# AI Server Dependencies
pip install fastapi uvicorn python-multipart face-recognition opencv-python scikit-learn
```

### **Environment Variables**
```bash
# Create .env file in project root
SECRET_KEY=your-secret-key
DEBUG=True
ALLOWED_HOSTS=127.0.0.1,localhost

# MongoDB
MONGODB_URI=mongodb://localhost:27017/sava

# AI Server
AI_SERVER_URL=http://127.0.0.1:8001
AI_FACE_ENDPOINT=/analyze-face

# Face Recognition
FACE_TOLERANCE=0.6
FACE_UNKNOWN_THRESHOLD=0.80
ALERT_COOLDOWN_SECONDS=60

# Object Detection
MIN_FACE_SIZE_PX=40
BLUR_THRESHOLD=20
MIN_EMB_SEPARATION=0.03
```

## Running the System

### **1. Start MongoDB**
```bash
mongod
```

### **2. Start Django Server**
```bash
cd d:\Mostafa_projects\SAVA_Django\Sava
python manage.py runserver 8000
```

### **3. Start AI Face Server**
```bash
cd d:\Mostafa_projects\SAVA_Django\Sava\ai_face_server
python -m uvicorn ai_face_server:app --host 0.0.0.0 --port 8001 --reload
```

### **4. Verify System Health**
```bash
# Test AI Server
curl http://localhost:8001/health

# Test Django Server
curl http://localhost:8000/api/
```

## 📡 API Endpoints

### **Person Tracking**

#### **Track Person**
```http
POST /api/person-tracking/track
Content-Type: multipart/form-data

patient_id: string
frame: image_file
```

**Response:**
```json
{
  "detail": "Person tracking processed.",
  "person_detected": true,
  "tracking_id": "PERSON_82710F41",
  "events_created": 1,
  "alerts_created": 2,
  "tracking_result": {
    "status": "success",
    "face_detected": true,
    "embedding": [0.1, 0.2, ...],
    "bbox": {"x": 0.1, "y": 0.2, "width": 0.3, "height": 0.4}
  }
}
```

#### **Get Active Persons**
```http
GET /api/person-tracking/active?patient_id=PATIENT_ID&minutes=10
```

**Response:**
```json
{
  "active_persons": [
    {
      "tracking_id": "PERSON_82710F41",
      "status": "NEW",
      "first_seen": "2026-04-16T20:41:20.910000",
      "last_seen": "2026-04-16T20:41:20.910000",
      "frame_count": 1
    }
  ]
}
```

#### **Cleanup Old Persons**
```http
POST /api/person-tracking/cleanup
Content-Type: application/json

{
  "patient_id": "PATIENT_ID",
  "hours": 24
}
```

### **Object Detection**

#### **Detect Objects** (For External AI Team)
```http
POST /api/object-detection/detect
Content-Type: multipart/form-data

patient_id: string
detections: json_string
frame: image_file (optional)
```

**Detection Format:**
```json
[
  {
    "class": "knife",
    "confidence": 0.95,
    "bbox": {"x": 0.1, "y": 0.2, "width": 0.3, "height": 0.4},
    "is_dangerous": true
  }
]
```

**Response:**
```json
{
  "detail": "Object detection processed.",
  "total_detections": 1,
  "dangerous_objects": 1,
  "events_created": 1,
  "alerts_created": 2,
  "dangerous_objects_list": [
    {
      "object_class": "knife",
      "confidence": 0.95,
      "bbox": {"x": 0.1, "y": 0.2, "width": 0.3, "height": 0.4}
    }
  ]
}
```

#### **Get Dangerous Object Types**
```http
GET /api/object-detection/dangerous-types
```

**Response:**
```json
{
  "dangerous_objects": {
    "knife": {"category": "sharp", "severity": "high"},
    "gun": {"category": "weapon", "severity": "critical"},
    "pistol": {"category": "weapon", "severity": "critical"},
    "rifle": {"category": "weapon", "severity": "critical"},
    "scissors": {"category": "sharp", "severity": "medium"},
    "razor": {"category": "sharp", "severity": "medium"},
    "hammer": {"category": "blunt", "severity": "medium"},
    "bottle": {"category": "potential", "severity": "low"},
    "syringe": {"category": "medical", "severity": "high"},
    "needle": {"category": "sharp", "severity": "high"},
    "broken_glass": {"category": "sharp", "severity": "high"},
    "medication": {"category": "medical", "severity": "medium"}
  },
  "total_types": 12
}
```

#### **Mock Object Detection** (For Testing)
```http
POST /api/object-detection/mock
Content-Type: application/json

{
  "patient_id": "PATIENT_ID",
  "object_type": "knife"
}
```

### **Alerts**

#### **Get All Alerts**
```http
GET /api/alerts
```

#### **Get Specific Alert**
```http
GET /api/alerts/{alert_id}
```

#### **Update Alert Status**
```http
PATCH /api/alerts/{alert_id}
Content-Type: application/json

{
  "status": "SEEN"
}
```

### **User Management**

#### **Create User/Patient**
```http
POST /api/users
Content-Type: application/json

{
  "name": "John Doe",
  "email": "john@example.com",
  "role": "PATIENT"
}
```

#### **Link Caregiver to Patient**
```http
POST /api/patients/{patient_id}/caregivers/{caregiver_id}
```

#### **Get Patient Caregivers**
```http
GET /api/patients/{patient_id}/caregivers
```

## 🧪 Testing

### **Run Test Scripts**
```bash
# Test Person Tracking
python test_person_tracking.py

# Test Dangerous Objects
python test_dangerous_objects.py
```

### **Test Face Recognition with Sample Image**
```http
POST /api/person-tracking/track
Content-Type: multipart/form-data

patient_id: "69ddbdac102ad38f9d396857"
frame: [your_test_image.jpg]
```

##  Database Collections

### **MongoDB Collections**
- **users**: Patients and caregivers
- **person_tracking**: Person tracking records
- **events**: All system events (face, object, person tracking)
- **alerts**: Alert notifications for caregivers
- **patient_caregiver_links**: Patient-caregiver relationships

### **Event Types**
- `FACE`: Face recognition events
- `OBJECT`: Object detection events
- `FALL`: Fall detection events
- `PERSON_ENTER`: Person enters monitoring area
- `PERSON_EXIT`: Person exits monitoring area

### **Alert Types**
- `UNKNOWN_FACE`: Unknown person detected by face recognition
- `UNKNOWN_PERSON_ENTER`: Unknown person entered area
- `DANGEROUS_OBJECT`: Dangerous object detected

## 🔧 Configuration

### **Face Recognition Settings**
- `MIN_FACE_SIZE_PX`: 40 (minimum face size in pixels)
- `FACE_TOLERANCE`: 0.6 (matching tolerance)
- `BLUR_THRESHOLD`: 20 (blur detection threshold)
- `UNKNOWN_PROB_THRESHOLD`: 0.60 (unknown probability threshold)
- `UNKNOWN_DIST_THRESHOLD`: 0.65 (unknown distance threshold)

### **Alert Settings**
- `ALERT_COOLDOWN_SECONDS`: 60 (cooldown between same alert type)
- `FACE_UNKNOWN_THRESHOLD`: 0.80 (confidence threshold for unknown faces)

##  Dangerous Object Categories

### **Critical Severity**
- Weapons: gun, pistol, rifle

### **High Severity**
- Sharp objects: knife, needle, broken_glass, syringe
- Medical: syringe

### **Medium Severity**
- Sharp objects: scissors, razor
- Blunt objects: hammer
- Medical: medication

### **Low Severity**
- Potential risks: bottle

## 🔄 Integration Guide

### **For External Object Detection AI Team**

1. **Use the Detection Endpoint**:
   ```http
   POST /api/object-detection/detect
   ```

2. **Send Detection Results**:
   ```json
   {
     "patient_id": "patient123",
     "detections": [
       {
         "class": "detected_object",
         "confidence": 0.95,
         "bbox": {"x": 0.1, "y": 0.2, "width": 0.3, "height": 0.4},
         "is_dangerous": true
       }
     ]
   }
   ```

3. **System Will**:
   - Create events for all detections
   - Trigger alerts only for dangerous objects
   - Notify all linked caregivers
   - Apply cooldown protection

##  Troubleshooting

### **Common Issues**

1. **Faces Not Detected**
   - Check minimum face size (40px requirement)
   - Verify image quality and lighting
   - Try enhanced preprocessing (automatic)

2. **Alerts Not Triggering**
   - Verify patient has linked caregivers
   - Check cooldown period (60 seconds)
   - Confirm object marked as dangerous

3. **AI Server Not Responding**
   - Ensure AI server running on port 8001
   - Check health endpoint: `GET /health`
   - Verify face_recognition library installed

### **Health Checks**
```bash
# Django Server
curl http://localhost:8000/api/

# AI Server
curl http://localhost:8001/health

# Test Person Tracking
curl -X POST -F "patient_id=PATIENT_ID" -F "frame=@image.jpg" http://localhost:8000/api/person-tracking/track
```

##  Development Notes

### **System Architecture**
- **Django Backend**: Main application server (port 8000)
- **FastAPI AI Server**: Face and object recognition (port 8001)
- **MongoDB**: Data storage
- **OpenCV**: Image processing
- **Face Recognition**: Face detection and encoding

### **Key Features**
- **Asynchronous Processing**: Background face recognition tasks
- **Multi-rotation Support**: Handles rotated images
- **Real-time Tracking**: Live person monitoring
- **Scalable Architecture**: Ready for multiple cameras
- **External Integration**: Open API for third-party AI

##  Support

For issues or questions:
1. Check health endpoints
2. Review system logs
3. Verify environment variables
4. Test with provided test scripts

---

**SAVA Smart Patient Monitoring System** - Keeping patients safe with AI-powered monitoring 
