"""
SAVA Object Detection Server
Receives JPEG frames from the Flutter app and returns YOLO detections.

Run with:
    pip install flask flask-cors ultralytics pillow
    python detection_server.py

The server runs on http://localhost:5000
Flutter calls POST /detect with multipart form field "frame" (JPEG bytes)
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
from ultralytics import YOLO
from PIL import Image
import numpy as np
import io

app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})

# ── Load your trained model ───────────────────────────────────────────────────
MODEL_PATH = r"C:\Users\Nezar\Downloads\Object detection\Object detection\runs\runs\sava_dangerous_objects\weights\best.pt"
CONF_THRESHOLD = 0.54

model = YOLO(MODEL_PATH)
print(f"Model loaded from: {MODEL_PATH}")
print(f"Classes: {model.names}")


@app.route('/detect', methods=['POST'])
def detect():
    if 'frame' not in request.files:
        return jsonify({"error": "No frame provided", "detections": []}), 400

    try:
        frame_bytes = request.files['frame'].read()
        image = Image.open(io.BytesIO(frame_bytes)).convert('RGB')
        img_width, img_height = image.size

        results = model.predict(
            source=np.array(image),
            conf=CONF_THRESHOLD,
            verbose=False
        )

        detections = []
        for box in results[0].boxes:
            cls_id = int(box.cls[0])
            confidence = float(box.conf[0])
            label = model.names[cls_id].lower()
            
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            detections.append({
                "label": label,
                "confidence": round(confidence, 3),
                "box": {
                    "x1": round(x1 / img_width, 4),
                    "y1": round(y1 / img_height, 4),
                    "x2": round(x2 / img_width, 4),
                    "y2": round(y2 / img_height, 4),
                }
            })

        return jsonify({"detections": detections})

    except Exception as e:
        print(f"Detection error: {e}")
        return jsonify({"error": str(e), "detections": []}), 500


@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok", "classes": list(model.names.values())})


if __name__ == '__main__':
    print("Starting SAVA Object Detection Server on http://localhost:5000")
    app.run(host='0.0.0.0', port=5001, debug=False)