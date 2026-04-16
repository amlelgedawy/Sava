# SAVA — Activity Recognition (Samer's Branch)

Activity recognition module for the SAVA eldercare system. Uses MediaPipe for pose estimation, SkateFormer for skeleton-based action classification, and YOLOv8 for object/person detection.

## Setup

### 1. Install dependencies

```bash
pip install -r requirements.txt
```

### 2. Download required model weights

These files are **not included** in the repository and must be downloaded manually:

#### YOLOv8n (person detection)
Download `yolov8n.pt` from Ultralytics and place it in the project root:
```
https://github.com/ultralytics/assets/releases/download/v8.2.0/yolov8n.pt
```

#### SkateFormer pretrained weights
Download the pretrained weights and place them under `SkateFormer/skateformer_pretrained_weights/`:
```
https://github.com/KAIST-VICLab/SkateFormer
```

## Trained Models

Fine-tuned models are included in the repository:
- `perception/activity_recognition/work_dir/sava_4class/best_4class.pt` — 4-class fine-tuned model
- `perception/activity_recognition/work_dir/sava_v2/best_v2.pt` — v2 fine-tuned model

## Project Structure

```
perception/activity_recognition/
├── inference.py              # Live inference pipeline
├── train_finetune_4class.py  # Fine-tuning script (4-class)
├── train_finetune_v2.py      # Fine-tuning script (v2)
├── extract_keypoints*.py     # Keypoint extraction scripts
├── pose_estimator.py         # MediaPipe pose wrapper
├── detector.py               # YOLOv8 detector wrapper
├── camera.py                 # Camera input handler
└── work_dir/                 # Trained model outputs
SkateFormer/                  # SkateFormer model architecture
```