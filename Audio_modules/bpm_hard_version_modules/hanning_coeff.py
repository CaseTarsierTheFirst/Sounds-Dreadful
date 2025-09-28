import numpy as np
from fixedpoint import FixedPoint

#parameters
N = 1024     #number of samples per frame
W = 32       #word length 
W_FRAC = 16  #fraction length

#Hanning Window Generation

hanning = np.hanning(N) #gives array of N hanning coefficients of floating point values between 0 and 1 - use to extract coefficients

#Writing to a .mem file for Quartus initialisation:

with open("hanning_coeff.mem", 'w') as f:
    for coeff in hanning:
        fp = FixedPoint(coeff, signed = True, m = W-W_FRAC, n = W_FRAC)
        print(fp)
        f.write(str(fp) + '\n')
