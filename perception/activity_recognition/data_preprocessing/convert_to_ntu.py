import numpy as np

def mediapipe_to_ntu(skeleton_33):
    """
    skeleton_33: (T, 33, 3)
    return: (T, 25, 3)
    """

    T = skeleton_33.shape[0]
    ntu = np.zeros((T, 25, 3))

    def midpoint(a, b):
        return (a + b) / 2

    for t in range(T):
        s = skeleton_33[t]

        ntu[t, 0] = midpoint(s[23], s[24])
        ntu[t, 1] = midpoint(s[11], s[12])
        ntu[t, 2] = midpoint(s[11], s[12])
        ntu[t, 3] = s[0]

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