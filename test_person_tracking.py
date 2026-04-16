#!/usr/bin/env python3
"""
Test script for person tracking system
Run this to verify the person tracking endpoints work correctly
"""

import requests
import json
import time
from pathlib import Path

# Configuration
BASE_URL = "http://localhost:8000/api"
AI_SERVER_URL = "http://localhost:8001"

def test_ai_server_health():
    """Test if AI server is running"""
    try:
        response = requests.get(f"{AI_SERVER_URL}/health")
        if response.status_code == 200:
            print("✅ AI Server is running")
            return True
        else:
            print(f"❌ AI Server health check failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Cannot connect to AI Server: {str(e)}")
        return False

def test_track_person_endpoint():
    """Test the person tracking endpoint with a sample image"""
    # You'll need to provide a test image path
    test_image_path = "D:\Mostafa_projects\SAVA_Django\Sava\mostafa1.jpeg"  # Replace with actual test image
    
    if not Path(test_image_path).exists():
        print(f"❌ Test image not found: {test_image_path}")
        print("Please provide a test image with a face")
        return False
    
    try:
        with open(test_image_path, 'rb') as f:
            files = {'frame': f}
            data = {'patient_id': '69ddbdac102ad38f9d396857'}  # You'll need a real patient ID
            
            response = requests.post(
                f"{BASE_URL}/person-tracking/track",
                files=files,
                data=data
            )
        
        if response.status_code == 201:
            result = response.json()
            print("✅ Person tracking endpoint works!")
            print(f"   Person detected: {result.get('person_detected')}")
            print(f"   Tracking ID: {result.get('tracking_id')}")
            print(f"   Events created: {result.get('events_created')}")
            return True
        else:
            print(f"❌ Person tracking failed: {response.status_code}")
            print(f"   Response: {response.text}")
            return False
            
    except Exception as e:
        print(f"   Error testing person tracking: {str(e)}")
        return False

def test_active_persons_endpoint():
    """Test getting active persons"""
    try:
        response = requests.get(
            f"{BASE_URL}/person-tracking/active",
            params={'patient_id': '69ddbdac102ad38f9d396857', 'minutes': 10}
        )
        
        if response.status_code == 200:
            result = response.json()
            print("✅ Active persons endpoint works!")
            print(f"   Active persons count: {len(result.get('active_persons', []))}")
            return True
        else:
            print(f"❌ Active persons endpoint failed: {response.status_code}")
            print(f"   Response: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ Error testing active persons: {str(e)}")
        return False

def main():
    print("🚀 Testing Person Tracking System")
    print("=" * 50)
    
    # Test AI Server
    if not test_ai_server_health():
        print("\n❌ Please start the AI server first:")
        print("   cd ai_face_server && python ai_face_server.py")
        return
    
    # Test person tracking
    print("\n📸 Testing person tracking endpoint...")
    test_track_person_endpoint()
    
    # Test active persons
    print("\n👥 Testing active persons endpoint...")
    test_active_persons_endpoint()
    
    print("\n" + "=" * 50)
    print("✨ Test completed!")

if __name__ == "__main__":
    main()
