"""
train_finetune_v2.py
--------------------
Fine-tunes SkateFormer on 5 SAVA classes: WALK, EAT, DRINK, SLEEP, FALL.
Uses keypoints extracted by extract_keypoints_ntu.py and extract_keypoints_adl.py.

Run from project root:
    python perception/activity_recognition/train_finetune_v2.py
"""

import random
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader, WeightedRandomSampler

# ---------------------------------------------------------------------------
# SkateFormer path
# ---------------------------------------------------------------------------
SKATEFORMER_DIR = r"D:\Year 4 UNI\Sava\SkateFormer"
if SKATEFORMER_DIR not in sys.path:
    sys.path.insert(0, SKATEFORMER_DIR)

from model.SkateFormer import SkateFormer
from feeders import tools as sk_tools

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
KEYPOINTS_DIR = Path(r"D:\Year 4 UNI\Sava\perception\activity_recognition\data\keypoints_v2")
PRETRAINED    = Path(r"D:\Year 4 UNI\Sava\SkateFormer\skateformer_pretrained_weights\ntu60_CSub\SkateFormer_j.pt")
WORK_DIR      = Path(r"D:\Year 4 UNI\Sava\perception\activity_recognition\work_dir\sava_v2")
WORK_DIR.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# Classes
# ---------------------------------------------------------------------------
CLASS_NAMES = ["WALK", "EAT", "DRINK", "SLEEP", "FALL"]
CLASS_TO_ID = {c: i for i, c in enumerate(CLASS_NAMES)}

# ---------------------------------------------------------------------------
# Training settings (tuned for RTX 3060 6GB)
# ---------------------------------------------------------------------------
SEED       = 42
EPOCHS     = 20
BATCH_SIZE = 8   # reduced from 16 to fit RTX 3060 6GB VRAM
LR         = 1e-4
MIN_LR     = 1e-6
WEIGHT_DECAY = 1e-2
NUM_WORKERS  = 2
VAL_RATIO    = 0.2

# Cap per class — set to match smallest well-represented class (~400) after ETRI removal
MAX_SAMPLES_PER_CLASS = 400


# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------
def set_seed(seed):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)


# ---------------------------------------------------------------------------
# Dataset
# ---------------------------------------------------------------------------
class NPYWindowDataset(Dataset):
    """Each .npy file is shape (3, 64, 24, 2) float32."""

    def __init__(self, items, augment=False):
        self.items   = items
        self.augment = augment

    def __len__(self):
        return len(self.items)

    def __getitem__(self, idx):
        path, label = self.items[idx]
        x = np.load(path)                    # (3, 64, 24, 2) float32

        if self.augment:
            x = sk_tools.shear(x, p=0.5)
            x = sk_tools.rotate(x, p=0.5)
            x = sk_tools.scale(x, p=0.5)
            x = sk_tools.gaussian_noise(x, p=0.3)

        x       = torch.from_numpy(x).float()  # (3, 64, 24, 2)
        index_t = torch.linspace(-1, 1, 64)    # (64,) normalised to [-1, 1]
        return x, index_t, label


def build_split():
    train_items, val_items = [], []

    for cls in CLASS_NAMES:
        cls_dir = KEYPOINTS_DIR / cls
        if not cls_dir.exists():
            raise RuntimeError(
                f"Missing class directory: {cls_dir}\n"
                f"Run extract_keypoints_ntu.py and extract_keypoints_adl.py first."
            )

        files = sorted(cls_dir.glob("*.npy"))
        if len(files) == 0:
            raise RuntimeError(f"No .npy files found in {cls_dir}")

        if MAX_SAMPLES_PER_CLASS is not None:
            files = files[:MAX_SAMPLES_PER_CLASS]

        random.shuffle(files)
        n_val      = max(1, int(len(files) * VAL_RATIO))
        val_files  = files[:n_val]
        train_files = files[n_val:]

        cid = CLASS_TO_ID[cls]
        train_items.extend([(str(f), cid) for f in train_files])
        val_items.extend([(str(f), cid) for f in val_files])

        print(f"  {cls}: total={len(files)}  train={len(train_files)}  val={len(val_files)}")

    random.shuffle(train_items)
    random.shuffle(val_items)
    return train_items, val_items


def make_balanced_sampler(items):
    labels        = [lbl for _, lbl in items]
    class_counts  = np.bincount(labels, minlength=len(CLASS_NAMES))
    class_weights = 1.0 / np.maximum(class_counts, 1)
    sample_weights = [class_weights[lbl] for lbl in labels]
    print("  Class counts (train):", class_counts.tolist())
    return WeightedRandomSampler(sample_weights, num_samples=len(sample_weights), replacement=True)


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------
def build_model(device):
    model = SkateFormer(
        in_channels=3,
        depths=(2, 2, 2, 2),
        channels=(96, 192, 192, 192),
        num_classes=len(CLASS_NAMES),   # 5
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

    # Load pretrained backbone (60-class NTU), drop classification head
    ckpt    = torch.load(str(PRETRAINED), map_location=device)
    state   = ckpt.get("model", ckpt.get("state_dict", ckpt))
    state   = {k: v for k, v in state.items() if not k.startswith("head.")}

    missing, unexpected = model.load_state_dict(state, strict=False)
    print(f"  Loaded pretrained backbone. Missing keys: {len(missing)}  Unexpected: {len(unexpected)}")
    # Expected: head.weight + head.bias missing (new 5-class head will be trained from scratch)

    return model


# ---------------------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------------------
@torch.no_grad()
def evaluate(model, loader, device):
    model.eval()
    correct, total = 0, 0

    # Per-class tracking
    class_correct = np.zeros(len(CLASS_NAMES), dtype=int)
    class_total   = np.zeros(len(CLASS_NAMES), dtype=int)

    for x, index_t, y in loader:
        x       = x.to(device)
        index_t = index_t.to(device)
        y       = torch.as_tensor(y, device=device, dtype=torch.long)

        logits  = model(x, index_t)
        pred    = logits.argmax(dim=1)
        correct += (pred == y).sum().item()
        total   += y.numel()

        for gt, p in zip(y.cpu().numpy(), pred.cpu().numpy()):
            class_total[gt]   += 1
            class_correct[gt] += int(gt == p)

    overall_acc = correct / max(total, 1)

    per_class = {}
    for i, name in enumerate(CLASS_NAMES):
        per_class[name] = class_correct[i] / max(class_total[i], 1)

    return overall_acc, per_class


# ---------------------------------------------------------------------------
# Training
# ---------------------------------------------------------------------------
def main():
    set_seed(SEED)
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Device: {device}")
    if device == "cuda":
        print(f"GPU: {torch.cuda.get_device_name(0)}")

    print("\nBuilding dataset split...")
    train_items, val_items = build_split()

    train_ds = NPYWindowDataset(train_items, augment=True)
    val_ds   = NPYWindowDataset(val_items,   augment=False)

    sampler      = make_balanced_sampler(train_items)
    train_loader = DataLoader(train_ds, batch_size=BATCH_SIZE, sampler=sampler,
                              num_workers=NUM_WORKERS, pin_memory=True)
    val_loader   = DataLoader(val_ds, batch_size=BATCH_SIZE, shuffle=False,
                              num_workers=NUM_WORKERS, pin_memory=True)

    print("\nBuilding model...")
    model = build_model(device)

    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.AdamW(model.parameters(), lr=LR, weight_decay=WEIGHT_DECAY)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
        optimizer, T_max=EPOCHS, eta_min=MIN_LR
    )
    # Mixed precision — cuts VRAM usage ~50%, speeds up training on RTX 3060
    scaler = torch.cuda.amp.GradScaler(enabled=(device == "cuda"))

    best_acc  = 0.0
    best_path = WORK_DIR / "best_v2.pt"

    print(f"\nTraining for {EPOCHS} epochs...\n")

    for epoch in range(1, EPOCHS + 1):
        model.train()
        running_loss = 0.0

        for x, index_t, y in train_loader:
            x       = x.to(device)
            index_t = index_t.to(device)
            y       = torch.as_tensor(y, device=device, dtype=torch.long)

            optimizer.zero_grad()
            with torch.cuda.amp.autocast(enabled=(device == "cuda")):
                logits = model(x, index_t)
                loss   = criterion(logits, y)
            scaler.scale(loss).backward()
            scaler.step(optimizer)
            scaler.update()

            running_loss += loss.item()

        scheduler.step()

        val_acc, per_class = evaluate(model, val_loader, device)
        avg_loss = running_loss / max(len(train_loader), 1)
        lr_now   = scheduler.get_last_lr()[0]

        per_class_str = "  ".join(f"{k}={v:.2f}" for k, v in per_class.items())
        print(f"Epoch {epoch:02d}/{EPOCHS} | loss={avg_loss:.4f} | val_acc={val_acc:.4f} | lr={lr_now:.2e}")
        print(f"  Per-class: {per_class_str}")

        if val_acc > best_acc:
            best_acc = val_acc
            torch.save({
                "model":        model.state_dict(),
                "class_names":  CLASS_NAMES,
                "epoch":        epoch,
                "val_acc":      val_acc,
            }, best_path)
            print(f"  ✅ New best saved → {best_path}  (val_acc={best_acc:.4f})")

        print()

    print("Training complete.")
    print(f"Best val accuracy: {best_acc:.4f}")
    print(f"Checkpoint: {best_path}")


if __name__ == "__main__":
    main()
