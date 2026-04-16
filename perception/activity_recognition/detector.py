from ultralytics import YOLO
import cv2

# Load pretrained YOLOv8 model
model = YOLO("yolov8n.pt")


def detect_person(frame):
    results = model(frame)

    for result in results:
        boxes = result.boxes

        for box in boxes:
            cls = int(box.cls[0])
            confidence = float(box.conf[0])

            # COCO class 0 = person
            if cls == 0:
                x1, y1, x2, y2 = box.xyxy[0]
                x1, y1, x2, y2 = int(x1), int(y1), int(x2), int(y2)

                # Draw bounding box
                cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)

                # Label
                label = f"Person {confidence:.2f}"
                cv2.putText(frame, label,
                            (x1, y1 - 10),
                            cv2.FONT_HERSHEY_SIMPLEX,
                            0.6,
                            (0, 255, 0),
                            2)

    return frame
