import numpy as np

def mediapipe_to_ntu(skeleton_33):
    """
    skeleton_33: (T, 33, 3)
    return: (T, 25, 3)

    NTU joint mapping (0-indexed):
      0=hip_center, 1=spine_mid, 2=neck, 3=head,
      4=l_shoulder, 5=l_elbow, 6=l_wrist, 7=l_hand,
      8=r_shoulder, 9=r_elbow, 10=r_wrist, 11=r_hand,
      12=l_hip, 13=l_knee, 14=l_ankle, 15=l_foot,
      16=r_hip, 17=r_knee, 18=r_ankle, 19=r_foot,
      20=spine_shoulder, 21=l_fingertip, 22=l_thumb,
      23=r_fingertip, 24=r_thumb
    """

    T = skeleton_33.shape[0]
    ntu = np.zeros((T, 25, 3))

    def midpoint(a, b):
        return (a + b) / 2

    for t in range(T):
        s = skeleton_33[t]

        hip_mid      = midpoint(s[23], s[24])
        shoulder_mid = midpoint(s[11], s[12])

        ntu[t, 0] = hip_mid                      # hip center
        ntu[t, 1] = midpoint(hip_mid, shoulder_mid)  # mid-spine (between hip and shoulders)
        ntu[t, 2] = shoulder_mid                 # neck ≈ shoulder midpoint (matches Kinect "Neck")
        ntu[t, 3] = midpoint(s[7], s[8])         # head ≈ ear midpoint (matches Kinect "Head")

        ntu[t, 4] = s[11]
        ntu[t, 5] = s[13]
        ntu[t, 6] = s[15]
        ntu[t, 7] = s[19]

        ntu[t, 8] = s[12]
        ntu[t, 9] = s[14]
        ntu[t,10] = s[16]
        ntu[t,11] = s[20]

        ntu[t,12] = s[23]
        ntu[t,13] = s[25]
        ntu[t,14] = s[27]
        ntu[t,15] = s[31]

        ntu[t,16] = s[24]
        ntu[t,17] = s[26]
        ntu[t,18] = s[28]
        ntu[t,19] = s[32]

        ntu[t,20] = midpoint(s[11], s[12])

        ntu[t,21] = s[19]
        ntu[t,22] = s[21]
        ntu[t,23] = s[20]
        ntu[t,24] = s[22]

    return ntu


def normalize_skeleton(ntu25):
    """
    Normalize one skeleton frame so coordinates are scale- and position-invariant.
    This ensures MediaPipe (0–1 range) and Kinect (meters) data live in the same space.

    ntu25: (25, 3) — one frame in any coordinate system
    returns: (25, 3) — centered on hip, scaled by torso length
    """
    hip  = ntu25[0].copy()   # NTU joint 0 = hip center
    neck = ntu25[2].copy()   # NTU joint 2 = neck

    centered = ntu25 - hip

    torso_len = np.linalg.norm(neck - hip)
    normalized = centered / (torso_len + 1e-6)

    return normalized.astype(np.float32)