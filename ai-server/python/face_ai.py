import os
import sys
import json

import face_recognition


def out(obj):
    print(json.dumps(obj))
    sys.stdout.flush()


def main():
    if len(sys.argv) < 2:
        out({"status": "error", "message": "Missing frame path argument"})
        return 0

    frame_path = sys.argv[1]

 
    script_dir = os.path.dirname(os.path.abspath(__file__))
    relatives_dir = os.path.abspath(os.path.join(script_dir, "..", "uploads", "relatives"))

    try:
        if not os.path.exists(frame_path):
            out({"status": "error", "message": f"Frame not found: {frame_path}"})
            return 0

        try:
            unknown_image = face_recognition.load_image_file(frame_path)
        except Exception as e:
            out({"status": "error", "message": f"Failed to load image: {str(e)}"})
            return 0

        unknown_encodings = face_recognition.face_encodings(unknown_image)

        if len(unknown_encodings) == 0:
            out({"status": "no_face"})
            return 0

        unknown_encoding = unknown_encodings[0]

        if not os.path.isdir(relatives_dir):
            out({"status": "no_known_faces"})
            return 0

        files = [
            f for f in os.listdir(relatives_dir)
            if f.lower().endswith((".jpg", ".jpeg", ".png"))
        ]

        if len(files) == 0:
            out({"status": "no_known_faces"})
            return 0

        known_encodings = []
        known_keys = []

        for filename in files:
            path = os.path.join(relatives_dir, filename)
            name_key = os.path.splitext(filename)[0]

            try:
                img = face_recognition.load_image_file(path)
                encs = face_recognition.face_encodings(img)
                if len(encs) == 0:
                    continue
                known_encodings.append(encs[0])
                known_keys.append(name_key)
            except Exception:
                continue

        if len(known_encodings) == 0:
            out({"status": "no_known_faces"})
            return 0

        matches = face_recognition.compare_faces(known_encodings, unknown_encoding, tolerance=0.5)

        if True in matches:
            idx = matches.index(True)
            out({"status": "match", "name_key": known_keys[idx], "confidence": 1.0})
            return 0

        out({"status": "no_match", "confidence": 1.0})
        return 0

    except Exception as e:
        out({"status": "error", "message": str(e)})
        return 0


if __name__ == "__main__":
    sys.exit(main())
