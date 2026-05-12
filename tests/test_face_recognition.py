"""
Test Scenario: Face Recognition (Known vs Unknown)

Scenario Description:
    The system identifies whether detected faces belong to known or unknown
    individuals. Unknown face detection triggers an alert to linked caregivers.

Positive Test Cases:
    TC-FACE-P1  Known enrolled person detected         (FR-13)
    TC-FACE-P2  Unknown person detected                 (FR-14)
    TC-FACE-P3  Known person from different angle       (FR-13)
    TC-FACE-P4  Correct person matched among many       (FR-13)
    TC-FACE-P5  Unknown face alert sent to caregivers   (FR-14, FR-04)
    TC-FACE-P6  Event stored with timestamp             (FR-18)

Negative Test Cases:
    TC-FACE-N1  Similar-looking person, no false match  (FR-13)
    TC-FACE-N2  Low confidence face, no alert           (FR-13, FR-14)
    TC-FACE-N3  Frame with no face                      (FR-13)
    TC-FACE-N4  Blurry / occluded face                  (FR-13)
    TC-FACE-N5  No enrolled persons in system           (FR-13)
    TC-FACE-N6  Invalid image file                      (FR-17)

Usage:
    python manage.py test --testrunner=django.test.runner.DiscoverRunner --pattern="test_face_recognition.py"
    OR
    python test_face_recognition.py
"""

import os
import sys
import time
import unittest
from datetime import datetime, timedelta
from unittest.mock import patch, MagicMock

# Add project root to path so imports work from any directory
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

import django
django.setup()

from django.conf import settings
from apps.monitoring.models import User, Event, Alert, PatientCaregiverLink
from apps.monitoring.services.event_service import EventService
from apps.monitoring.services.alert_service import AlertService
from apps.accounts.services.user_service import UserService


class FaceRecognitionTestBase(unittest.TestCase):
    """Shared setup: creates a patient, caregiver, and links them."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        ts = int(time.time())
        cls.patient = User(
            name=f"TestPatient_{ts}",
            email=f"patient_{ts}@test.com",
            role=User.ROLE_PATIENT,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        ).save()

        cls.caregiver = User(
            name=f"TestCaregiver_{ts}",
            email=f"caregiver_{ts}@test.com",
            role=User.ROLE_CAREGIVER,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        ).save()
        cls.caregiver.set_password("testpass123")
        cls.caregiver.save()

        cls.link = PatientCaregiverLink(
            patient=cls.patient,
            caregiver=cls.caregiver,
            created_at=datetime.utcnow(),
        ).save()

    @classmethod
    def tearDownClass(cls):
        Alert.objects(patient=cls.patient).delete()
        Event.objects(patient=cls.patient).delete()
        PatientCaregiverLink.objects(patient=cls.patient).delete()
        cls.caregiver.delete()
        cls.patient.delete()
        super().tearDownClass()



# POSITIVE TEST CASES


class TestFaceRecognitionPositive(FaceRecognitionTestBase):
    """Positive test cases for face recognition."""

    def test_TC_FACE_P1_known_person_detected(self):
        """
        TC-FACE-P1........
        """
        event = EventService.create_event(
            patient=self.patient,
            event_type="FACE",
            confidence=0.95,
            payload={"known": True, "person_name": "john_doe", "status": "match"},
        )

        self.assertIsNotNone(event.id)
        self.assertEqual(event.event_type, "FACE")
        self.assertTrue(event.payload["known"])
        self.assertEqual(event.payload["person_name"], "john_doe")

        should_alert = AlertService.should_alert_for_event(event)
        self.assertFalse(should_alert, "Known person should NOT trigger an alert.")

    def test_TC_FACE_P2_unknown_person_detected(self):
        """
        TC-FACE-P2...........
        """
        event = EventService.create_event(
            patient=self.patient,
            event_type="FACE",
            confidence=0.90,
            payload={"known": False, "person_name": None, "status": "unknown"},
        )

        self.assertIsNotNone(event.id)
        self.assertFalse(event.payload["known"])

        should_alert = AlertService.should_alert_for_event(event)
        self.assertTrue(should_alert, "Unknown person should trigger an alert.")

        alerts = AlertService.create_alerts_for_event(event)
        self.assertGreater(len(alerts), 0, "At least one alert should be created.")
        self.assertEqual(alerts[0].alert_type, "UNKNOWN_FACE")
        self.assertEqual(str(alerts[0].caregiver.id), str(self.caregiver.id))

    def test_TC_FACE_P3_known_person_different_angle(self):
        """
        TC-FACE-P3...........
        """
        event = EventService.create_event(
            patient=self.patient,
            event_type="FACE",
            confidence=0.82,
            payload={"known": True, "person_name": "john_doe", "status": "match"},
        )

        self.assertIsNotNone(event.id)
        self.assertTrue(event.payload["known"])

        should_alert = AlertService.should_alert_for_event(event)
        self.assertFalse(should_alert, "Known person from different angle should NOT alert.")

    def test_TC_FACE_P4_correct_person_matched_among_many(self):
        """
        TC-FACE-P4.........
        """
        event_a = EventService.create_event(
            patient=self.patient,
            event_type="FACE",
            confidence=0.93,
            payload={"known": True, "person_name": "alice", "status": "match"},
        )
        event_b = EventService.create_event(
            patient=self.patient,
            event_type="FACE",
            confidence=0.91,
            payload={"known": True, "person_name": "bob", "status": "match"},
        )

        self.assertEqual(event_a.payload["person_name"], "alice")
        self.assertEqual(event_b.payload["person_name"], "bob")
        self.assertNotEqual(
            event_a.payload["person_name"],
            event_b.payload["person_name"],
            "Different faces should map to different names.",
        )

        self.assertFalse(AlertService.should_alert_for_event(event_a))
        self.assertFalse(AlertService.should_alert_for_event(event_b))

    def test_TC_FACE_P5_unknown_face_alert_sent_to_caregivers(self):
        """
        TC-FACE-P5.........
        """
        # Clear old alerts to avoid cooldown interference
        Alert.objects(patient=self.patient, alert_type="UNKNOWN_FACE").delete()

        event = EventService.create_event(
            patient=self.patient,
            event_type="FACE",
            confidence=0.88,
            payload={"known": False, "person_name": None, "status": "no_match"},
        )

        should_alert = AlertService.should_alert_for_event(event)
        self.assertTrue(should_alert)

        alerts = AlertService.create_alerts_for_event(event)
        self.assertEqual(len(alerts), 1, "Exactly one alert (one caregiver linked).")
        self.assertEqual(alerts[0].alert_type, "UNKNOWN_FACE")
        self.assertEqual(alerts[0].message, "Unknown person detected by face recognition.")
        self.assertEqual(alerts[0].status, "NEW")
        self.assertEqual(str(alerts[0].patient.id), str(self.patient.id))
        self.assertEqual(str(alerts[0].caregiver.id), str(self.caregiver.id))

    def test_TC_FACE_P6_event_stored_with_timestamp(self):
        """
        TC-FACE-P6.........
        """
        before = datetime.utcnow()
        event = EventService.create_event(
            patient=self.patient,
            event_type="FACE",
            confidence=0.95,
            payload={"known": True, "person_name": "john_doe", "status": "match"},
        )
        after = datetime.utcnow()

        self.assertIsNotNone(event.created_at)
        self.assertGreaterEqual(event.created_at, before - timedelta(seconds=1))
        self.assertLessEqual(event.created_at, after + timedelta(seconds=1))

        self.assertEqual(event.payload["person_name"], "john_doe")
        self.assertEqual(event.payload["status"], "match")
        self.assertEqual(event.confidence, 0.95)


# ==========================================================================
# NEGATIVE TEST CASES
# ==========================================================================

class TestFaceRecognitionNegative(FaceRecognitionTestBase):
    """Negative test cases for face recognition."""

    def test_TC_FACE_N1_similar_looking_no_false_match(self):
        """
        TC-FACE-N1..........
        """
        event = EventService.create_event(
            patient=self.patient,
            event_type="FACE",
            confidence=0.85,
            payload={"known": False, "person_name": None, "status": "no_match"},
        )

        self.assertFalse(event.payload["known"], "Non-enrolled face should be known=False.")
        self.assertIsNone(event.payload["person_name"], "Should not assign a person_name.")

    def test_TC_FACE_N2_low_confidence_no_alert(self):
        """
        TC-FACE-N2............
        """
        threshold = settings.FACE_UNKNOWN_THRESHOLD
        low_confidence = threshold - 0.15  # e.g. 0.65

        event = EventService.create_event(
            patient=self.patient,
            event_type="FACE",
            confidence=low_confidence,
            payload={"known": False, "person_name": None, "status": "unknown"},
        )

        self.assertIsNotNone(event.id, "Event should still be logged.")
        self.assertLess(event.confidence, threshold)

        should_alert = AlertService.should_alert_for_event(event)
        self.assertFalse(
            should_alert,
            f"Low confidence ({low_confidence:.2f}) below threshold ({threshold}) should NOT alert.",
        )

    def test_TC_FACE_N3_frame_with_no_face(self):
        """
        TC-FACE-N3...........
        """
        event = EventService.create_event(
            patient=self.patient,
            event_type="FACE",
            confidence=0.0,
            payload={"known": True, "person_name": None, "status": "no_face"},
        )

        self.assertEqual(event.payload["status"], "no_face")
        self.assertEqual(event.confidence, 0.0)

        should_alert = AlertService.should_alert_for_event(event)
        self.assertFalse(should_alert, "No-face frame should NOT trigger an alert.")

    def test_TC_FACE_N4_blurry_occluded_face(self):
        """
        TC-FACE-N4...........
        """
        event = EventService.create_event(
            patient=self.patient,
            event_type="FACE",
            confidence=0.0,
            payload={"known": True, "person_name": None, "status": "no_face"},
        )

        self.assertIsNone(event.payload["person_name"], "Blurry face should not match anyone.")
        self.assertFalse(
            AlertService.should_alert_for_event(event),
            "Blurry/occluded face with no detection should NOT alert.",
        )

    def test_TC_FACE_N5_no_enrolled_persons(self):
        """
        TC-FACE-N5...........
        """
        event = EventService.create_event(
            patient=self.patient,
            event_type="FACE",
            confidence=1.0,
            payload={"known": False, "person_name": None, "status": "no_known_faces"},
        )

        self.assertIsNotNone(event.id, "Event should be created even with no enrolled persons.")
        self.assertEqual(event.payload["status"], "no_known_faces")
        self.assertFalse(event.payload["known"])

    @patch("apps.monitoring.services.ai_client.requests.post")
    def test_TC_FACE_N6_invalid_image_file(self, mock_post):
        """
        TC-FACE-N6...........
        """
        from apps.monitoring.services.ai_client import analyze_face, AIClientError

        mock_response = MagicMock()
        mock_response.status_code = 400
        mock_response.raise_for_status.side_effect = Exception("400 Bad Request: Failed to read image")
        mock_post.return_value = mock_response

        mock_file = MagicMock()
        mock_file.name = "corrupted.jpg"
        mock_file.content_type = "image/jpeg"

        with self.assertRaises(AIClientError) as ctx:
            analyze_face(mock_file, patient_id=str(self.patient.id))

        self.assertIn("AI server request failed", str(ctx.exception))


# ==========================================================================
# Runner
# ==========================================================================

if __name__ == "__main__":
    print("=" * 70)
    print("Test Scenario: Face Recognition (Known vs Unknown)")
    print("=" * 70)
    print()
    unittest.main(verbosity=2)
