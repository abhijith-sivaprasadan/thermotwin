#!/usr/bin/env python3
"""
train_dnn.py  --  Offline training for ThermoTwin-F MINLP surrogate networks.

Two networks
  HR surrogate  4->32->16->1  ReLU:
    inputs  [load_frac, tamb_C, TIT_K, fouling_pct]
    output  heat_rate_kJ_kWh
    ground truth: quadratic part-load model + ambient/TIT/fouling corrections

  Commit policy  5->32->16->3  Tanh:
    inputs  [hour/24, price/150, demand/120, soc_frac, prev_cs/2]
    output  logits for [low, mid, high dispatch] used by DP pruning

Writes dnn_weights.txt that dnn_surrogate.f90 loads at runtime.
Architecture constants (layer sizes, normalization) must stay in sync
with the matching Fortran parameters.

Usage:
    python train_dnn.py              # writes dnn_weights.txt
    python train_dnn.py path/to.txt  # custom output path
"""
import sys
import numpy as np

SEED = 2024
np.random.seed(SEED)

# ── Architecture  (must match dnn_surrogate.f90) ──────────────────────────
HR_NI,  HR_NH1, HR_NH2         = 4, 32, 16
PL_NI,  PL_NH1, PL_NH2, PL_NO = 5, 32, 16, 3

HR_IN_MEAN = np.array([0.65,  15.0,  1400.0, 3.0])
HR_IN_STD  = np.array([0.25,  20.0,   100.0, 4.0])
HR_OUT_MEAN = 11500.0
HR_OUT_STD  = 2500.0

# ── Physics model  (ground-truth labels) ─────────────────────────────────

def hr_physics(lf, ta, tk, fp):
    """Multi-variable GT heat rate (kJ/kWh) matching the MINLP physics."""
    hr  = 9200.0 + 4600.0 * (1.0 - lf)**2   # quadratic part-load (matches Fortran)
    hr *= 1.0 + 0.003  * (ta - 15.0)         # +0.3 %/degC above 15 degC
    hr *= 1.0 - 0.0008 * (tk - 1400.0)       # -0.08 %/K above 1400 K TIT
    hr += fp * 0.009 * 9200.0                 # fouling: +1 % HR per 1 % fouling
    return hr

# ── MLP with Adam ─────────────────────────────────────────────────────────

def he_init(fan_in, fan_out):
    return np.random.randn(fan_out, fan_in) * np.sqrt(2.0 / fan_in)

class MLP:
    def __init__(self, sizes, acts):
        self.acts   = acts
        self.params = [(he_init(sizes[i], sizes[i+1]),
                        np.zeros(sizes[i+1]))
                       for i in range(len(sizes) - 1)]
        self.ms = [(np.zeros_like(W), np.zeros_like(b)) for W, b in self.params]
        self.vs = [(np.zeros_like(W), np.zeros_like(b)) for W, b in self.params]
        self.step = 0

    def forward(self, x):
        self._cache = [x]
        h = x
        for (W, b), act in zip(self.params, self.acts):
            z = h @ W.T + b
            if   act == 'relu': h = np.maximum(0.0, z)
            elif act == 'tanh': h = np.tanh(z)
            else:               h = z          # linear
            self._cache.append((z, h))
        return h

    def backward(self, dout):
        grads  = []
        delta  = dout
        for i in reversed(range(len(self.params))):
            z, _  = self._cache[i + 1]
            act   = self.acts[i]
            if   act == 'relu': dz = delta * (z > 0)
            elif act == 'tanh': dz = delta * (1.0 - np.tanh(z)**2)
            else:               dz = delta
            h_prev = self._cache[i] if i == 0 else self._cache[i][1]
            W, _  = self.params[i]
            grads.insert(0, (dz.T @ h_prev, dz.sum(0)))
            delta  = dz @ W
        return grads

    def adam(self, grads, lr, b1=0.9, b2=0.999, eps=1e-8):
        self.step += 1
        new_p, new_m, new_v = [], [], []
        for (dW, db), (mW, mb), (vW, vb), (W, b) in zip(
                grads, self.ms, self.vs, self.params):
            mW = b1*mW + (1-b1)*dW;   mb = b1*mb + (1-b1)*db
            vW = b2*vW + (1-b2)*dW**2; vb = b2*vb + (1-b2)*db**2
            t  = self.step
            W  = W - lr * (mW/(1-b1**t)) / (np.sqrt(vW/(1-b2**t)) + eps)
            b  = b - lr * (mb/(1-b1**t)) / (np.sqrt(vb/(1-b2**t)) + eps)
            new_p.append((W, b)); new_m.append((mW, mb)); new_v.append((vW, vb))
        self.params, self.ms, self.vs = new_p, new_m, new_v

    def fit(self, X, y, epochs, batch=1024, lr=1e-3,
            mse=True, verbose=True, val_X=None, val_y=None):
        n = X.shape[0]
        for ep in range(epochs):
            idx  = np.random.permutation(n)
            loss_ep = 0.0
            for s in range(0, n, batch):
                xb = X[idx[s:s+batch]]
                yb = y[idx[s:s+batch]]
                out = self.forward(xb)
                nb  = xb.shape[0]
                if mse:
                    loss = np.mean((out - yb)**2)
                    dl   = 2.0*(out - yb) / nb
                else:
                    ex   = np.exp(out - out.max(1, keepdims=True))
                    prob = ex / ex.sum(1, keepdims=True)
                    loss = -np.mean((yb * np.log(prob + 1e-12)).sum(1))
                    dl   = (prob - yb) / nb
                loss_ep += loss
                self.adam(self.backward(dl), lr)
            if verbose and (ep + 1) % 100 == 0:
                print(f"    epoch {ep+1:4d}  loss={loss_ep:.5f}", flush=True)

# ── Data generators ───────────────────────────────────────────────────────

def make_hr_data(n=60000):
    lf = np.random.uniform(0.15, 1.00, n)
    ta = np.random.uniform(-20,  45,   n)
    tk = np.random.uniform(1200, 1600, n)
    fp = np.random.uniform(0,    20,   n)
    hr = hr_physics(lf, ta, tk, fp) + np.random.normal(0, 25, n)
    X  = (np.stack([lf, ta, tk, fp], axis=1) - HR_IN_MEAN) / HR_IN_STD
    y  = ((hr - HR_OUT_MEAN) / HR_OUT_STD).reshape(-1, 1)
    return X, y, hr

def make_policy_data(n=30000):
    """Heuristic commitment labels for policy pre-training."""
    hr_be  = 9200.0 + 4600.0 * 0.09     # HR at 70 % load (clean)
    be_prc = hr_be * 8.0 / 1000.0       # breakeven price at gas=8 $/GJ
    hour   = np.random.uniform(0,   1,   n)
    price  = np.random.uniform(30, 200,  n)
    demand = np.random.uniform(20, 120,  n)
    soc_f  = np.random.uniform(0,   1,   n)
    prev   = np.random.choice([0.0, 0.5, 1.0], n)
    X      = np.stack([hour, price/150.0, demand/120.0, soc_f, prev], axis=1)
    y      = np.zeros((n, 3))
    low    = (price < be_prc * 0.85) | (soc_f > 0.88)
    high   = (price > be_prc * 1.05) & (demand > 60)
    mid    = ~low & ~high
    y[low,  0] = 1.0
    y[mid,  1] = 1.0
    y[high, 2] = 1.0
    return X, y

# ── Weight file writer ────────────────────────────────────────────────────

def _row(v):
    return ' '.join(f'{x:.8f}' for x in v)

def write_weights(path, hr_net, pl_net, mae):
    with open(path, 'w') as f:
        f.write('# ThermoTwin-F DNN weights v1.0\n')
        f.write(f'# HR_MAE_kJkWh: {mae:.2f}\n')
        f.write('# HR surrogate 4-32-16-1 relu relu linear\n')
        # HR layer 1: 32 rows x 4 cols
        W, b = hr_net.params[0]
        for row in W:   f.write(_row(row) + '\n')
        f.write(_row(b) + '\n')
        # HR layer 2: 16 rows x 32 cols
        W, b = hr_net.params[1]
        for row in W:   f.write(_row(row) + '\n')
        f.write(_row(b) + '\n')
        # HR output layer: 1 row x 16 cols, scalar bias
        W, b = hr_net.params[2]
        f.write(_row(W[0]) + '\n')
        f.write(f'{b[0]:.8f}\n')
        # Policy separator
        f.write('# Policy 5-32-16-3 tanh tanh linear\n')
        # Policy layer 1: 32 rows x 5 cols
        W, b = pl_net.params[0]
        for row in W:   f.write(_row(row) + '\n')
        f.write(_row(b) + '\n')
        # Policy layer 2: 16 rows x 32 cols
        W, b = pl_net.params[1]
        for row in W:   f.write(_row(row) + '\n')
        f.write(_row(b) + '\n')
        # Policy output: 3 rows x 16 cols
        W, b = pl_net.params[2]
        for row in W:   f.write(_row(row) + '\n')
        f.write(_row(b) + '\n')

# ── Main ──────────────────────────────────────────────────────────────────

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'dnn_weights.txt'

    print('=== ThermoTwin-F DNN Training ===\n')

    print('[1/2] HR surrogate  4->32->16->1  ReLU...')
    X_hr, y_hr, hr_raw = make_hr_data(60000)
    n_tr = int(0.9 * len(hr_raw))
    hr_net = MLP([HR_NI, HR_NH1, HR_NH2, 1], ['relu', 'relu', 'lin'])
    hr_net.fit(X_hr[:n_tr], y_hr[:n_tr], epochs=400, lr=2e-3)
    pred_n = hr_net.forward(X_hr[n_tr:])
    pred   = pred_n * HR_OUT_STD + HR_OUT_MEAN
    mae    = float(np.mean(np.abs(pred.ravel() - hr_raw[n_tr:])))
    print(f'  Val MAE = {mae:.1f} kJ/kWh')

    print('\n[2/2] Commit policy  5->32->16->3  Tanh...')
    X_pl, y_pl = make_policy_data(30000)
    pl_net = MLP([PL_NI, PL_NH1, PL_NH2, PL_NO], ['tanh', 'tanh', 'lin'])
    pl_net.fit(X_pl, y_pl, epochs=300, lr=5e-4, mse=False)
    logits = pl_net.forward(X_pl)
    ex     = np.exp(logits - logits.max(1, keepdims=True))
    probs  = ex / ex.sum(1, keepdims=True)
    acc    = float(np.mean(np.argmax(probs, 1) == np.argmax(y_pl, 1)))
    print(f'  Train acc = {acc*100:.1f} %')

    print(f'\nWriting {out}...')
    write_weights(out, hr_net, pl_net, mae)
    print(f'Done -> {out}')
    print('\nLaunch thermotwin-gui.exe -- weights load automatically at startup.')

if __name__ == '__main__':
    main()
