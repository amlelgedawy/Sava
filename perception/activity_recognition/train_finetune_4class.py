import random
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader, WeightedRandomSampler

# Add SkateFormer repo to path
import sys
SKATEFORMER_DIR = r"D:\Year 4 UNI\Sava\SkateFormer"
sys.path.append(SKATEFORMER_DIR)

from model.SkateFormer import SkateFormer

# ----------------------------
# Paths
# ----------------------------
KEYPOINTS_DIR = Path(r"D:\Year 4 UNI\Sava\perception\activity_recognition\data\keypoints")
PRETRAINED = Path(r"D:\Year 4 UNI\Sava\SkateFormer\skateformer_pretrained_weights\ntu60_CSub\SkateFormer_j.pt")
WORK_DIR = Path(r"D:\Year 4 UNI\Sava\perception\activity_recognition\work_dir\sava_4class")
WORK_DIR.mkdir(parents=True, exist_ok=True)

# ----------------------------
# Classes (your mapping)
# ----------------------------
CLASS_NAMES = ["EAT", "DRINK", "NAP", "SLEEP"]
CLASS_TO_ID = {c: i for i, c in enumerate(CLASS_NAMES)}

# ----------------------------
# Training settings (good for RTX 3060 6GB)
# ----------------------------
SEED = 1
EPOCHS = 10
BATCH_SIZE = 16
LR = 1e-4
WEIGHT_DECAY = 1e-2
NUM_WORKERS = 2
VAL_RATIO = 0.2

# For speed, you can cap per class (optional). Set to None to use all.
MAX_SAMPLES_PER_CLASS = None  # e.g. 400

# ----------------------------
# Utils
# ----------------------------
def set_seed(seed=1):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)


class NPYWindowDataset(Dataset):
    """
    Loads saved windows: each file is shape (3,64,24,2) float32
    Returns: x (tensor), index_t (tensor), label (int)
    """
    def __init__(self, items):
        self.items = items

    def __len__(self):
        return len(self.items)

    def __getitem__(self, idx):
        path, label = self.items[idx]
        x = np.load(path)  # (3,64,24,2)
        x = torch.from_numpy(x).float()
        index_t = torch.arange(64, dtype=torch.long)  # (64,)
        return x, index_t, label


def list_files_for_class(cls_name):
    d = KEYPOINTS_DIR / cls_name
    files = sorted([str(p) for p in d.glob("*.npy")])
    return files


def build_split():
    train_items = []
    val_items = []

    for cls in CLASS_NAMES:
        files = list_files_for_class(cls)
        if len(files) == 0:
            raise RuntimeError(f"No files found for class: {cls} in {KEYPOINTS_DIR}")

        # Optional cap for speed
        if MAX_SAMPLES_PER_CLASS is not None:
            files = files[:MAX_SAMPLES_PER_CLASS]

        random.shuffle(files)
        n_val = max(1, int(len(files) * VAL_RATIO))
        val_files = files[:n_val]
        train_files = files[n_val:]

        cid = CLASS_TO_ID[cls]
        train_items.extend([(f, cid) for f in train_files])
        val_items.extend([(f, cid) for f in val_files])

        print(f"{cls}: total={len(files)} train={len(train_files)} val={len(val_files)}")

    random.shuffle(train_items)
    random.shuffle(val_items)
    return train_items, val_items


def make_balanced_sampler(items):
    # Weight each sample inversely to its class count
    labels = [lbl for _, lbl in items]
    class_counts = np.bincount(labels, minlength=len(CLASS_NAMES))
    class_weights = 1.0 / np.maximum(class_counts, 1)
    sample_weights = [class_weights[lbl] for lbl in labels]
    sampler = WeightedRandomSampler(sample_weights, num_samples=len(sample_weights), replacement=True)
    print("Class counts (train):", class_counts.tolist())
    return sampler


def build_model(device):
    # Must match the pretrained model settings, except num_classes
    model = SkateFormer(
        in_channels=3,
        depths=(2, 2, 2, 2),
        channels=(96, 192, 192, 192),

        num_classes=len(CLASS_NAMES),   # ✅ 4 classes now
        embed_dim=96,
        num_people=2,
        num_frames=64,
        num_points=24,
        kernel_size=7,
        num_heads=32,

        type_1_size=(8, 8),
        type_2_size=(8, 12),
        type_3_size=(8, 8),
        type_4_size=(8, 12),

        attn_drop=0.5,
        head_drop=0.0,
        rel=True,
        drop_path=0.2,
        mlp_ratio=4.0,
        index_t=True
    ).to(device)

    # Load pretrained weights, ignore old head
    ckpt = torch.load(str(PRETRAINED), map_location=device)
    state = ckpt.get("model", ckpt.get("state_dict", ckpt))

    # Remove head keys (60-class head) if present
    state = {k: v for k, v in state.items() if not k.startswith("head.")}

    missing, unexpected = model.load_state_dict(state, strict=False)
    print("Loaded pretrained backbone.")
    print("Missing keys:", len(missing))      # expected: head.weight, head.bias
    print("Unexpected keys:", len(unexpected))

    return model


@torch.no_grad()
def evaluate(model, loader, device):
    model.eval()
    correct = 0
    total = 0

    for x, index_t, y in loader:
        x = x.to(device)
        index_t = index_t.to(device)  # ✅ already (B,64)
        y = torch.as_tensor(y, device=device, dtype=torch.long)

        logits = model(x, index_t)
        pred = logits.argmax(dim=1)
        correct += (pred == y).sum().item()
        total += y.numel()

    return correct / max(total, 1)


def main():
    set_seed(SEED)
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print("Device:", device)

    train_items, val_items = build_split()

    train_ds = NPYWindowDataset(train_items)
    val_ds = NPYWindowDataset(val_items)

    sampler = make_balanced_sampler(train_items)

    train_loader = DataLoader(
        train_ds,
        batch_size=BATCH_SIZE,
        sampler=sampler,
        num_workers=NUM_WORKERS,
        pin_memory=True
    )
    val_loader = DataLoader(
        val_ds,
        batch_size=BATCH_SIZE,
        shuffle=False,
        num_workers=NUM_WORKERS,
        pin_memory=True
    )

    model = build_model(device)

    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.AdamW(model.parameters(), lr=LR, weight_decay=WEIGHT_DECAY)

    best_acc = 0.0
    best_path = WORK_DIR / "best_4class.pt"

    for epoch in range(1, EPOCHS + 1):
        model.train()
        running_loss = 0.0

        for x, index_t, y in train_loader:
            x = x.to(device)
            index_t = index_t.to(device)  # ✅ already (B,64)
            y = torch.as_tensor(y, device=device, dtype=torch.long)

            optimizer.zero_grad()
            logits = model(x, index_t)
            loss = criterion(logits, y)
            loss.backward()
            optimizer.step()

            running_loss += loss.item()

        val_acc = evaluate(model, val_loader, device)
        avg_loss = running_loss / max(len(train_loader), 1)

        print(f"Epoch {epoch}/{EPOCHS} | loss={avg_loss:.4f} | val_acc={val_acc:.4f}")

        if val_acc > best_acc:
            best_acc = val_acc
            torch.save({
                "model": model.state_dict(),
                "class_names": CLASS_NAMES
            }, best_path)
            print(f"✅ Saved best checkpoint: {best_path} (val_acc={best_acc:.4f})")

    print("\nDone.")
    print("Best val acc:", best_acc)
    print("Checkpoint:", best_path)


if __name__ == "__main__":
    main()