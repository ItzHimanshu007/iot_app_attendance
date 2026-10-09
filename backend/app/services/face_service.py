"""Face enrollment and matching (signatures only — no images ever reach the server)."""

from __future__ import annotations

from typing import Any

from app.core.config import get_settings
from app.core.exceptions import ConflictError, ValidationError, VerificationError
from app.repositories.face_repo import FaceTemplateRepository
from app.schemas.requests import FaceEnroll
from app.security.auth import CurrentStaff
from app.services import campus_service, device_service
from app.services.attempt_service import record_attempt
from app.services.face_matching import best_match, min_pairwise_similarity, normalize

_repo = FaceTemplateRepository()


def public_face(row: dict[str, Any] | None) -> dict[str, Any] | None:
    """Template metadata safe to return (never the embeddings)."""
    if row is None:
        return None
    return {
        "status": row.get("status"),
        "sample_count": row.get("sample_count"),
        "model_version": row.get("model_version"),
        "updated_at": row.get("updated_at"),
    }


def get_template(staff_id: str) -> dict[str, Any] | None:
    """Raw template row."""
    return _repo.get(staff_id)


def find_duplicate(
    staff_id: str, samples: list[list[float]], threshold: float
) -> tuple[str, float] | None:
    """Return (other_staff_id, score) if these samples match another approved staff."""
    for other in _repo.list_approved():
        if other["staff_id"] == staff_id:
            continue
        other_samples = other.get("embeddings") or []
        if not other_samples or len(other_samples[0]) != len(samples[0]):
            continue
        score = max(best_match(s, other_samples) for s in samples)
        if score >= threshold:
            return other["staff_id"], score
    return None


def enroll(staff: CurrentStaff, req: FaceEnroll, ip: str | None = None) -> dict[str, Any]:
    """Store a new face template (status = pending until an admin approves)."""
    settings = get_settings()
    device_service.require_bound_device(staff.id, req.device_fingerprint)

    existing = _repo.get(staff.id)
    if existing and existing.get("status") == "approved":
        raise ConflictError(
            "Your face is already enrolled. Ask an admin to reset it if you need to re-enroll.",
            code="FACE_ALREADY_ENROLLED",
        )

    count = len(req.embeddings)
    if not settings.face_min_samples <= count <= settings.face_max_samples:
        raise ValidationError(
            f"Provide between {settings.face_min_samples} and {settings.face_max_samples} "
            "face samples.",
            "FACE_SAMPLES",
        )
    dims = {len(e) for e in req.embeddings}
    if len(dims) != 1 or not 64 <= next(iter(dims)) <= 1024:
        raise ValidationError("Face samples have inconsistent sizes.", "INVALID_EMBEDDING")

    samples = [normalize(e) for e in req.embeddings]
    if min_pairwise_similarity(samples) < settings.face_enroll_consistency_threshold:
        raise ValidationError(
            "The face samples don't look like the same person. Retake them in good light, "
            "looking straight at the camera.",
            "FACE_INCONSISTENT",
        )

    threshold = float(campus_service.get_campus()["face_match_threshold"])
    duplicate = find_duplicate(staff.id, samples, threshold)
    if duplicate:
        other_id, score = duplicate
        record_attempt(
            staff.id,
            "face_enroll",
            False,
            "FACE_DUPLICATE",
            f"Face matches staff {other_id}",
            face_score=round(score, 4),
            device_fingerprint=req.device_fingerprint,
            ip_address=ip,
        )
        raise ConflictError(
            "This face is already enrolled for another staff member.", code="FACE_DUPLICATE"
        )

    row = _repo.upsert(
        {
            "staff_id": staff.id,
            "embeddings": [[round(v, 6) for v in s] for s in samples],
            "embedding_dim": len(samples[0]),
            "sample_count": count,
            "model_version": req.model_version,
            "status": "pending",
            "reviewed_by": None,
            "reviewed_at": None,
        }
    )
    return public_face(row) or {}


def match(staff_id: str, embedding: list[float]) -> float:
    """Similarity between a live signature and the approved template."""
    template = _repo.get(staff_id)
    if template is None:
        raise VerificationError("Enroll your face first.", "FACE_NOT_ENROLLED")
    if template.get("status") != "approved":
        raise VerificationError(
            "Your face enrollment is waiting for admin approval.", "FACE_NOT_APPROVED"
        )
    probe = normalize(embedding)
    if len(probe) != int(template["embedding_dim"]):
        raise VerificationError(
            "Face model changed — update the app and ask an admin to reset your face.",
            "EMBEDDING_DIM_MISMATCH",
        )
    return best_match(probe, template["embeddings"])


def require_approved(staff_id: str) -> dict[str, Any]:
    """Template must exist and be approved."""
    template = _repo.get(staff_id)
    if template is None:
        raise VerificationError("Enroll your face first.", "FACE_NOT_ENROLLED")
    if template.get("status") != "approved":
        raise VerificationError(
            "Your face enrollment is waiting for admin approval.", "FACE_NOT_APPROVED"
        )
    return template
