# fastapi_yolo_server.py
from fastapi import FastAPI, File, UploadFile
from fastapi.responses import StreamingResponse
from ultralytics import YOLO
import cv2
import numpy as np
import io

app = FastAPI(title="YOLOv26 Dangerous Object Detection")

# Load YOLO v26 model once at startup
model = YOLO("yolo26n.pt")

# Define dangerous classes
dangerous_classes = ["knife", "scissors"]

@app.post("/detect/")
async def detect_dangerous_objects(file: UploadFile = File(...)):
    # Read image from uploaded file
    image_bytes = await file.read()
    np_arr = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    # Run YOLO inference
    results = model(img_rgb)

    # Draw bounding boxes for dangerous objects
    for r in results:
        boxes = r.boxes
        class_ids = r.boxes.cls.cpu().numpy().astype(int)
        for i, cls_id in enumerate(class_ids):
            cls_name = model.names[cls_id]
            if cls_name in dangerous_classes:
                x1, y1, x2, y2 = boxes.xyxy[i].cpu().numpy().astype(int)
                cv2.rectangle(img_rgb, (x1, y1), (x2, y2), (255,0,0), 2)  # Red box
                cv2.putText(img_rgb, f"{cls_name} unsafe", (x1, y1-10),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255,0,0), 2)

    # Convert image back to bytes
    img_bgr = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR)
    _, buffer = cv2.imencode(".jpg", img_bgr)
    return StreamingResponse(io.BytesIO(buffer.tobytes()), media_type="image/jpeg")
