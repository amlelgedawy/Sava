import sys
import torch

# Add SkateFormer repo to Python path
SKATEFORMER_DIR = r"D:\Year 4 UNI\Sava\SkateFormer"
sys.path.append(SKATEFORMER_DIR)

from model.SkateFormer import SkateFormer

WEIGHTS = r"D:\Year 4 UNI\Sava\SkateFormer\skateformer_pretrained_weights\ntu60_CSub\SkateFormer_j.pt"


def load_pretrained(device):
    # ✅ MUST match the pretrained YAML (SkateFormer_j / ntu60_CSub)
    model = SkateFormer(
        in_channels=3,
        depths=(2, 2, 2, 2),
        channels=(96, 192, 192, 192),

        num_classes=60,
        embed_dim=96,          # ✅ checkpoint expects 96 (your error showed 96 vs 64)
        num_people=2,
        num_frames=64,
        num_points=24,         # ✅ partition=True makes 24 points in their feeder
        kernel_size=7,
        num_heads=32,

        # ✅ these must NOT be (1,1) — must match YAML
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

    ckpt = torch.load(WEIGHTS, map_location=device)
    state = ckpt.get("model", ckpt.get("state_dict", ckpt))

    # strict=False is okay, but now shapes should match anyway
    missing, unexpected = model.load_state_dict(state, strict=False)

    print("✅ Weights loaded")
    print("Missing keys:", len(missing))
    print("Unexpected keys:", len(unexpected))

    model.eval()
    return model


@torch.no_grad()
def dummy_forward(model, device):
    # input shape must be (B, C, T, V, M) = (1, 3, 64, 24, 2)
    x = torch.zeros((1, 3, 64, 24, 2), device=device)

    # index_t must be (B, T) when index_t=True
    index_t = torch.arange(64, device=device).unsqueeze(0)  # (1, 64)

    y = model(x, index_t)
    print("✅ Output logits shape:", tuple(y.shape))  # expected (1, 60)


def main():
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print("Device:", device)

    model = load_pretrained(device)
    dummy_forward(model, device)


if __name__ == "__main__":
    main()