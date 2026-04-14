from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class EmailConfig:
    sender: str = ""
    password: str = ""
    recipient: str = ""

    @property
    def enabled(self) -> bool:
        return all([self.sender, self.password, self.recipient])


@dataclass(frozen=True)
class Settings:
    base_dir: Path
    alarm_file: Path
    log_dir: Path
    email: EmailConfig
    eye_threshold: float = 0.25
    mouth_threshold: float = 0.50
    head_angle_threshold: float = 20.0
    forward_drop_threshold: float = 0.08
    eyes_time_threshold: float = 2.0
    mouth_time_threshold: float = 1.0
    head_time_threshold: float = 2.0
    forward_time_threshold: float = 2.5
    blink_rate_threshold: int = 25
    email_cooldown_seconds: int = 60
    camera_index: int = 0
    ear_graph_max_points: int = 100
    calibration_seconds: float = 6.0


def _load_email_config() -> EmailConfig:
    sender = os.getenv("DRIVE_SAFE_EMAIL_SENDER", "")
    password = os.getenv("DRIVE_SAFE_EMAIL_PASSWORD", "")
    recipient = os.getenv("DRIVE_SAFE_EMAIL_RECIPIENT", "")

    if sender and password and recipient:
        return EmailConfig(sender=sender, password=password, recipient=recipient)

    try:
        from config import GMAIL_DESTINATAIRE, GMAIL_EXPEDITEUR, GMAIL_MOT_PASSE

        return EmailConfig(
            sender=GMAIL_EXPEDITEUR,
            password=GMAIL_MOT_PASSE,
            recipient=GMAIL_DESTINATAIRE,
        )
    except Exception:
        return EmailConfig()


def load_settings() -> Settings:
    base_dir = Path(__file__).resolve().parent.parent
    return Settings(
        base_dir=base_dir,
        alarm_file=base_dir / "alarme.mp3",
        log_dir=base_dir / "logs",
        email=_load_email_config(),
    )
