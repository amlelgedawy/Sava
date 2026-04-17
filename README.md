# SAVA - Smart Patient Monitoring System

An AI-powered patient monitoring system with face recognition, person tracking, and dangerous object detection capabilities.

## Dependencies

### Python Packages
```bash
# Core Dependencies
pip install django>=3.8
pip install djangorestframework
pip install mongoengine
pip install pymongo

# AI & Image Processing
pip install face-recognition
pip install opencv-python
pip install numpy
pip install scikit-learn

# AI Server
pip install fastapi
pip install uvicorn
pip install python-multipart
```

### Database
- **MongoDB**: Required for data storage
- **Python 3.8+**: Minimum Python version

## Features & Functionality

### Person Tracking System
- **Face Detection**: Detects faces in video frames using face_recognition library
- **Unique ID Assignment**: Assigns persistent tracking IDs (PERSON_XXXXXXX format)
- **Cross-frame Tracking**: Tracks same person across multiple frames
- **Distance Optimization**: Enhanced detection for monitoring cameras (40px minimum)
- **Status Management**: NEW -> PROCESSING -> IDENTIFIED/UNKNOWN workflow

### Face Recognition Enhancement
- **Multi-stage Detection**: Original image -> Enhanced preprocessing -> CNN fallback
- **Image Preprocessing**: CLAHE histogram equalization and sharpening
- **HOG Model**: Optimized for small/distant face detection
- **Rotation Handling**: Automatic image rotation for upright face detection
- **Embedding Generation**: 128-dimensional face embeddings for matching

### Dangerous Object Detection
- **12 Object Categories**: Weapons, sharp objects, medical items, potential risks
- **Severity Classification**: Critical, high, medium, low priority levels
- **External AI Integration**: Open API for third-party object detection systems
- **Bounding Box Detection**: Precise object location tracking
- **Confidence Scoring**: Detection confidence thresholds

### Alert Management System
- **Smart Filtering**: Only dangerous objects and unknown persons trigger alerts
- **Cooldown Protection**: Prevents alert spam (configurable cooldown period)
- **Multi-caregiver Support**: Alerts sent to all linked caregivers
- **Event Linking**: Alerts linked to specific events for audit trail
- **Status Tracking**: NEW -> SEEN alert lifecycle

## System Workflow

### Person Tracking Flow
1. **Frame Input**: Image frame received via API
2. **Face Detection**: Multi-stage detection with enhancement
3. **Embedding Generation**: Create 128-dimensional face embedding
4. **Person Matching**: Compare with existing tracked persons
5. **ID Assignment**: New tracking ID or update existing
6. **Event Creation**: PERSON_ENTER event generated
7. **Alert Trigger**: Unknown person alerts if applicable

### Object Detection Flow
1. **Detection Input**: External AI provides detection results
2. **Object Classification**: Categorize detected objects
3. **Danger Assessment**: Determine if object is dangerous
4. **Event Creation**: OBJECT event generated
5. **Alert Trigger**: Dangerous object alerts if applicable
6. **Caregiver Notification**: Alert sent to linked caregivers

### Alert System Flow
1. **Event Evaluation**: Check if event should trigger alert
2. **Cooldown Check**: Verify alert cooldown period passed
3. **Caregiver Verification**: Confirm patient has linked caregivers
4. **Alert Generation**: Create alerts for each caregiver
5. **Notification**: Alerts stored and available via API

## Key Configuration Parameters

### Face Recognition Settings
- **MIN_FACE_SIZE_PX**: 40 (minimum detectable face size)
- **FACE_TOLERANCE**: 0.6 (embedding matching tolerance)
- **BLUR_THRESHOLD**: 20 (image blur detection threshold)
- **UNKNOWN_PROB_THRESHOLD**: 0.60 (unknown person probability threshold)

### Alert System Settings
- **ALERT_COOLDOWN_SECONDS**: 60 (minimum time between same alert type)
- **FACE_UNKNOWN_THRESHOLD**: 0.80 (confidence threshold for unknown faces)

### Object Detection Categories
- **Critical**: gun, pistol, rifle
- **High**: knife, needle, broken_glass, syringe
- **Medium**: scissors, razor, hammer, medication
- **Low**: bottle (potential risk)



## System Architecture

### Components
- **Django Backend**: Main API server and business logic
- **FastAPI AI Server**: Face recognition and image processing
- **MongoDB**: Document-based data storage
- **OpenCV**: Computer vision and image preprocessing
- **Face Recognition Library**: Face detection and embedding generation

### Processing Pipeline
1. **Input**: Frame or detection data received
2. **Analysis**: AI processing (face/object detection)
3. **Decision**: Event creation and alert evaluation
4. **Storage**: Results saved to database
5. **Notification**: Alerts generated for caregivers

## External Integration

### Object Detection AI Integration
The system provides open API endpoints for external object detection AI teams:

2. **Data Format**: JSON array of detection results
3. **Required Fields**: class, confidence, bbox, is_dangerous
4. **System Response**: Event creation and alert generation

### Integration Benefits
- **Event Tracking**: All detections logged for audit
- **Alert Management**: Automatic dangerous object alerts
- **Caregiver Notification**: Immediate alert delivery
- **Cooldown Protection**: Prevents alert flooding

---

**SAVA Smart Patient Monitoring System** provides comprehensive AI-powered patient safety monitoring with face tracking, person identification, and dangerous object detection capabilities. 
