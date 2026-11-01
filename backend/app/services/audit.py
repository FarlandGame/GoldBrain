from __future__ import annotations

import json
from typing import Mapping

from sqlalchemy.orm import Session

from app.models.product import AuditLogRecord


class AuditService:
    def record(
        self,
        db: Session,
        *,
        action: str,
        user_public_id: str | None = None,
        resource: str = "",
        outcome: str = "success",
        metadata: Mapping[str, object] | None = None,
        commit: bool = True,
    ) -> None:
        safe_metadata = json.dumps(dict(metadata or {}), ensure_ascii=False, separators=(",", ":"))[:2000]
        db.add(
            AuditLogRecord(
                user_public_id=user_public_id,
                action=action[:80],
                resource=resource[:120],
                outcome=outcome[:24],
                metadata_json=safe_metadata,
            )
        )
        if commit:
            db.commit()
