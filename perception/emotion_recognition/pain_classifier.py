from pathlib import Path

import cv2
import numpy as np
import torch
import torch.nn as nn
from torchvision import models, transforms


class PainClassifier:
    """
    EfficientNet-B0 binary pain classifier.
    Input : face crop (BGR numpy array, any size — resized internally to 224×224)
    Output: pain probability 0–100 %, or None if model checkpoint not found.

    Architecture matches the fine-tuning target:
      - EfficientNet-B0 backbone (ImageNet weights replaced during fine-tuning)
      - Single linear output head → sigmoid → probability
    Drop a trained 'pain_efficientnet_b0.pt' at PAIN_MODEL_PATH to activate.
    """

    _TRANSFORM = transforms.Compose([
        transforms.ToPILImage(),
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ])

    def __init__(self, model_path: str, device: str):
        self._device = device
        self._model  = None

        if not Path(model_path).exists():
            print(f"⚠  Pain classifier model not found: {model_path}")
            print("   Fine-tune EfficientNet-B0 and save to that path. Pain detection disabled.")
            return

        net = models.efficientnet_b0(weights=None)
        net.classifier[1] = nn.Linear(net.classifier[1].in_features, 1)
        net.load_state_dict(torch.load(model_path, map_location=device, weights_only=True))
        net.eval()
        self._model = net.to(device)
        print(f"✅ Pain classifier loaded from {model_path}")

    def predict(self, face_crop: np.ndarray) -> float | None:
        """Return pain probability 0–100, or None if model is not loaded."""
        if self._model is None or face_crop is None or face_crop.size == 0:
            return None
        try:
            face_rgb = cv2.cvtColor(face_crop, cv2.COLOR_BGR2RGB)
            tensor   = self._TRANSFORM(face_rgb).unsqueeze(0).to(self._device)
            with torch.no_grad():
                prob = torch.sigmoid(self._model(tensor)).item()
            return prob * 100.0
        except Exception as e:
            print(f"[PainClassifier] {e}")
            return None
