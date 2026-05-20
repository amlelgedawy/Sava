import re
import random
from collections import defaultdict
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
PRETRAINED = Path(r"D:\Year 4 UNI\Sava\perception\activity_recognition\work_dir\sava_9class\best_9class.pt")
WORK_DIR = Path(r"D:\Year 4 UNI\Sava\perception\activity_recognition\work_dir\sava_8class")
WORK_DIR.mkdir(parents=True, exist_ok=True)

# ----------------------------
# Classes (your mapping)
# ----------------------------
CLASS_NAMES = ["EAT", "DRINK", "SLEEP", "FALL", "WALK", "SIT", "STAND", "USE_PHONE"]  # 8 classes — CHEST_PAIN removed
CLASS_TO_ID = {c: i for i, c in enumerate(CLASS_NAMES)}

# EAT upweighted to penalise EAT→DRINK misclassification
CLASS_WEIGHTS = {"EAT": 2.0}

# ----------------------------
# Training settings (good for RTX 3060 6GB)
# ----------------------------
SEED = 1
EPOCHS = 20
BATCH_SIZE = 4
LR = 1e-4
WEIGHT_DECAY = 1e-2
NUM_WORKERS = 0
VAL_RATIO = 0.2

# Cap matches the natural ceiling of minority classes (FALL/SLEEP ~990 available train windows)
MAX_SAMPLES_PER_CLASS = 1000

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
    val_items   = []

    for cls in CLASS_NAMES:
        files = list_files_for_class(cls)
        if len(files) == 0:
            raise RuntimeError(f"No files found for class: {cls} in {KEYPOINTS_DIR}")

        # Group windows by source video — strip _w{nn} suffix to get the video ID.
        # This prevents overlapping windows from the same video appearing in both splits.
        video_groups = defaultdict(list)
        for f in files:
            stem     = Path(f).stem                   # e.g. "ntu_S001C001P001R001A001_rgb_w00"
            video_id = re.sub(r'_w\d+$', '', stem)    # → "ntu_S001C001P001R001A001_rgb"
            video_groups[video_id].append(f)

        video_ids = sorted(video_groups.keys())
        random.shuffle(video_ids)

        n_val_vids = max(1, int(len(video_ids) * VAL_RATIO))
        val_ids    = set(video_ids[:n_val_vids])
        train_ids  = set(video_ids[n_val_vids:])

        train_files = [f for vid in train_ids for f in video_groups[vid]]
        val_files   = [f for vid in val_ids   for f in video_groups[vid]]

        # Cap train only — val is never capped so accuracy is representative
        if MAX_SAMPLES_PER_CLASS is not None and len(train_files) > MAX_SAMPLES_PER_CLASS:
            random.shuffle(train_files)
            train_files = train_files[:MAX_SAMPLES_PER_CLASS]

        cid = CLASS_TO_ID[cls]
        train_items.extend([(f, cid) for f in train_files])
        val_items.extend([(f, cid) for f in val_files])

        print(f"{cls}: {len(video_ids)} videos → {len(train_files)} train / {len(val_files)} val windows")

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

        num_classes=len(CLASS_NAMES),   # 8 classes
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
    per_correct = np.zeros(len(CLASS_NAMES))
    per_total   = np.zeros(len(CLASS_NAMES))

    for x, index_t, y in loader:
        x       = x.to(device)
        index_t = index_t.to(device)
        y       = torch.as_tensor(y, device=device, dtype=torch.long)
        pred    = model(x, index_t).argmax(dim=1)
        for cid in range(len(CLASS_NAMES)):
            mask = (y == cid)
            per_correct[cid] += (pred[mask] == y[mask]).sum().item()
            per_total[cid]   += mask.sum().item()

    per_acc = per_correct / np.maximum(per_total, 1)
    overall = per_correct.sum() / max(per_total.sum(), 1)
    for i, cls in enumerate(CLASS_NAMES):
        print(f"    {cls:12s}: {per_acc[i]*100:5.1f}%  ({int(per_correct[i])}/{int(per_total[i])})")
    return float(overall)


def main():
    set_seed(SEED)
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print("Device:", device)
    if device == "cuda":
        import os
        os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
        torch.cuda.empty_cache()

    train_items, val_items = build_split()

    train_ds = NPYWindowDataset(train_items)
    val_ds = NPYWindowDataset(val_items)

    sampler = make_balanced_sampler(train_items)

    train_loader = DataLoader(
        train_ds,
        batch_size=BATCH_SIZE,
        sampler=sampler,
        num_workers=NUM_WORKERS,
        pin_memory=False
    )
    val_loader = DataLoader(
        val_ds,
        batch_size=BATCH_SIZE,
        shuffle=False,
        num_workers=NUM_WORKERS,
        pin_memory=False
    )

    model = build_model(device)

    w = torch.ones(len(CLASS_NAMES))
    for cls, wt in CLASS_WEIGHTS.items():
        w[CLASS_TO_ID[cls]] = wt
    criterion = nn.CrossEntropyLoss(weight=w.to(device))
    optimizer = torch.optim.AdamW(model.parameters(), lr=LR, weight_decay=WEIGHT_DECAY)

    best_acc = 0.0
    best_path = WORK_DIR / "best_8class.pt"

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