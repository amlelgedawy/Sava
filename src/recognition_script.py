import sys
import os
import json 
import face_recognition
import numpy as np

if len(sys.argv) < 3:
    print(json.dumps({"status": "error", "message": "Missing arguments (input_image_path, patient_id)."}), file=sys.stderr)
    sys.exit(1)

input_image_path = sys.argv[1] 
patient_id = sys.argv[2]      


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOADS_DIR = os.path.join(SCRIPT_DIR, '..', 'uploads', 'relatives')




def load_known_faces():

    known_encodings = []
    known_keys = []
    
    print(f"DEBUG: Checking UPLOADS_DIR: {UPLOADS_DIR}", file=sys.stderr)
    
    if not os.path.exists(UPLOADS_DIR):
        print("DEBUG: UPLOADS_DIR does not exist.", file=sys.stderr)
        return known_encodings, known_keys

    for filename in os.listdir(UPLOADS_DIR):
        if filename.endswith(('.jpg', '.jpeg', '.png')):
            base_filename = os.path.splitext(filename)[0]
            
            parts = base_filename.split('_')
            
            if len(parts) >= 3:
                
                recognition_key = '_'.join(parts[1:-1]) 
            else:
                print(f"Warning: Skipping file {filename} due to unexpected naming format.", file=sys.stderr)
                continue
                
            image_path = os.path.join(UPLOADS_DIR, filename)
            
            try:
                image = face_recognition.load_image_file(image_path)
                encodings = face_recognition.face_encodings(image)

                if len(encodings) > 0:
                    known_encodings.append(encodings[0])
                    known_keys.append(recognition_key)
                else:
                    print(f"Warning: No face found in known image: {filename}", file=sys.stderr)

            except Exception as e:
                print(f"Error processing known face {filename}: {e}", file=sys.stderr)
                
    return known_encodings, known_keys

def verify_face_match(input_image_path):

    known_encodings, known_keys = load_known_faces()
    
    if not known_encodings:
        print("Warning: No known face encodings loaded.", file=sys.stderr)
        return None

    try:
        input_image = face_recognition.load_image_file(input_image_path)
        input_encodings = face_recognition.face_encodings(input_image)
    except Exception as e:
        print(f"Error loading or encoding input image: {e}", file=sys.stderr)
        return None

    if len(input_encodings) == 0:
        return None
    
    input_encoding = input_encodings[0]

    matches = face_recognition.compare_faces(known_encodings, input_encoding, tolerance=0.6)
    
    if True in matches:
        first_match_index = matches.index(True)
        return known_keys[first_match_index]
    else:
        return None


recognized_name_key = verify_face_match(input_image_path)


if recognized_name_key:
    result_data = {
        "status": "match",
        "name_key": recognized_name_key, 
    }
else:
    result_data = {
        "status": "no_match",
        "message": "No known face recognized.",
    }

print(json.dumps(result_data))

sys.exit(0)