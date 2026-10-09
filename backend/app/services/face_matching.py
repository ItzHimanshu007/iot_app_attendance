"""Face-signature maths (pure Python — 192 floats do not need numpy).

The phone runs MobileFaceNet and sends an embedding (a list of floats).
Everything here works on L2-normalised vectors, so cosine similarity is a
plain dot product in [-1, 1]; same person ≈ 0.6-0.9, different people ≈ < 0.4.
"""

from __future__ import annotations

import math
from collections.abc import Sequence

from app.core.exceptions import ValidationError

Vector = list[float]


def normalize(vec: Sequence[float]) -> Vector:
    """Return the L2-normalised copy of ``vec``.

    Raises:
        ValidationError: if the vector contains NaN/inf or is all zeros.
    """
    values = [float(v) for v in vec]
    if any(not math.isfinite(v) for v in values):
        raise ValidationError("Face signature contains invalid numbers", "INVALID_EMBEDDING")
    norm = math.sqrt(sum(v * v for v in values))
    if norm < 1e-6:
        raise ValidationError("Face signature is empty", "INVALID_EMBEDDING")
    return [v / norm for v in values]


def cosine(a: Sequence[float], b: Sequence[float]) -> float:
    """Cosine similarity of two already-normalised vectors."""
    if len(a) != len(b):
        raise ValidationError(
            f"Face signature size mismatch ({len(a)} vs {len(b)})", "EMBEDDING_DIM_MISMATCH"
        )
    return float(sum(x * y for x, y in zip(a, b, strict=True)))


def best_match(probe: Sequence[float], samples: Sequence[Sequence[float]]) -> float:
    """Highest similarity between ``probe`` and any enrolled sample or their mean."""
    if not samples:
        return -1.0
    scores = [cosine(probe, s) for s in samples]
    mean = normalize([sum(col) / len(samples) for col in zip(*samples, strict=True)])
    scores.append(cosine(probe, mean))
    return max(scores)


def min_pairwise_similarity(samples: Sequence[Sequence[float]]) -> float:
    """Lowest similarity between any two samples (1.0 for a single sample)."""
    worst = 1.0
    for i in range(len(samples)):
        for j in range(i + 1, len(samples)):
            worst = min(worst, cosine(samples[i], samples[j]))
    return worst
