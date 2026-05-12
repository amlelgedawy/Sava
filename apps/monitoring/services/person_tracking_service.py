import uuid
import numpy as np
from datetime import datetime, timedelta
from typing import List, Optional, Tuple, Dict

from apps.monitoring.models import PersonTracking, Event, User
from apps.monitoring.services.ai_client import analyze_face, AIClientError


class PersonTrackingService:
    
    @staticmethod
    def generate_tracking_id() -> str:
        """Generate unique tracking ID"""
        return f"PERSON_{uuid.uuid4().hex[:8].upper()}"
    
    @staticmethod
    def calculate_embedding_distance(emb1: List[float], emb2: List[float]) -> float:
        """Calculate Euclidean distance between two face embeddings"""
        if not emb1 or not emb2:
            return float('inf')
        return float(np.linalg.norm(np.array(emb1) - np.array(emb2)))
    
    @staticmethod
    def find_matching_person(patient: User, face_embedding: List[float], 
                           threshold: float = 0.6) -> Optional[PersonTracking]:
        """Find existing person tracking record by face embedding"""
        # Look for recently seen persons (last 5 minutes)
        recent_time = datetime.utcnow() - timedelta(minutes=5)
        
        active_persons = PersonTracking.objects(
            patient=patient,
            status__in=[PersonTracking.STATUS_IDENTIFIED, PersonTracking.STATUS_UNKNOWN],
            last_seen__gte=recent_time,
            face_embedding__ne=[]
        )
        
        best_match = None
        best_distance = float('inf')
        
        for person in active_persons:
            if person.face_embedding:
                distance = PersonTrackingService.calculate_embedding_distance(
                    face_embedding, person.face_embedding
                )
                if distance < threshold and distance < best_distance:
                    best_match = person
                    best_distance = distance
        
        return best_match
    
    @staticmethod
    def create_new_person(patient: User, face_embedding: List[float] = None,
                         bbox: Dict = None) -> PersonTracking:
        """Create new person tracking record"""
        tracking_id = PersonTrackingService.generate_tracking_id()
        
        person = PersonTracking(
            patient=patient,
            tracking_id=tracking_id,
            status=PersonTracking.STATUS_NEW,
            face_embedding=face_embedding,
            last_bbox=bbox
        )
        person.save()
        
        return person
    
    @staticmethod
    def update_person_tracking(person: PersonTracking, bbox: Dict = None) -> None:
        """Update existing person tracking with new detection"""
        person.last_seen = datetime.utcnow()
        person.frame_count += 1
        if bbox:
            person.last_bbox = bbox
        person.save()
    
    @staticmethod
    def process_face_recognition(person: PersonTracking, frame_file) -> Dict:
        """Process face recognition for a person"""
        try:
            person.status = PersonTracking.STATUS_PROCESSING
            person.save()
            
            # Send to AI server for face recognition
            ai_result = analyze_face(frame_file, patient_id=str(person.patient.id))
            
            event_type = ai_result.get("event_type", "FACE")
            confidence = ai_result.get("confidence", 0.0)
            payload = ai_result.get("payload", {})
            
            # Update person tracking with results
            if payload.get("known", False) and payload.get("person_name"):
                person.status = PersonTracking.STATUS_IDENTIFIED
                person.person_name = payload.get("person_name")
                person.confidence = confidence
            else:
                person.status = PersonTracking.STATUS_UNKNOWN
                person.person_name = None
                person.confidence = confidence
            
            person.save()
            
            return {
                "success": True,
                "ai_result": ai_result,
                "person_tracking_id": str(person.id),
                "tracking_id": person.tracking_id,
                "status": person.status
            }
            
        except AIClientError as e:
            person.status = PersonTracking.STATUS_UNKNOWN
            person.save()
            return {
                "success": False,
                "error": str(e),
                "person_tracking_id": str(person.id),
                "tracking_id": person.tracking_id,
                "status": person.status
            }
        except Exception as e:
            person.status = PersonTracking.STATUS_UNKNOWN
            person.save()
            return {
                "success": False,
                "error": f"Processing error: {str(e)}",
                "person_tracking_id": str(person.id),
                "tracking_id": person.tracking_id,
                "status": person.status
            }
    
    @staticmethod
    def create_person_event(patient: User, person_tracking: PersonTracking,
                          event_type: str, confidence: float, payload: Dict) -> Event:
        """Create event linked to person tracking"""
        return Event(
            patient=patient,
            event_type=event_type,
            confidence=confidence,
            payload=payload,
            person_tracking=person_tracking,
            created_at=datetime.utcnow()
        ).save()
    
    @staticmethod
    def get_active_persons(patient: User, minutes: int = 10) -> List[PersonTracking]:
        """Get all active persons for a patient in the last N minutes"""
        recent_time = datetime.utcnow() - timedelta(minutes=minutes)
        return PersonTracking.objects(
            patient=patient,
            last_seen__gte=recent_time
        ).order_by("-last_seen")
    
    @staticmethod
    def cleanup_old_persons(patient: User, hours: int = 24) -> int:
        """Remove old person tracking records (persons not seen for N hours)"""
        cutoff_time = datetime.utcnow() - timedelta(hours=hours)
        old_persons = PersonTracking.objects(
            patient=patient,
            last_seen__lt=cutoff_time
        )
        count = old_persons.count()
        old_persons.delete()
        return count
