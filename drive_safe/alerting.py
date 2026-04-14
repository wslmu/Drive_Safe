from __future__ import annotations

import smtplib
import time
from email.mime.text import MIMEText
from pathlib import Path

import pygame

from drive_safe.settings import EmailConfig


class AlarmPlayer:
    def __init__(self, alarm_file: Path) -> None:
        self.available = False
        self.active = False

        try:
            pygame.mixer.init()
            if alarm_file.exists():
                pygame.mixer.music.load(str(alarm_file))
                self.available = True
            else:
                print(f"Alarm file not found: {alarm_file}")
        except Exception as exc:
            print(f"Audio disabled: {exc}")

    def start(self) -> None:
        if self.available and not self.active:
            pygame.mixer.music.play(-1)
            self.active = True

    def stop(self) -> None:
        if self.available and self.active:
            pygame.mixer.music.stop()
            self.active = False

    def close(self) -> None:
        if pygame.mixer.get_init():
            pygame.mixer.quit()


class EmailNotifier:
    def __init__(self, config: EmailConfig, cooldown_seconds: int) -> None:
        self.config = config
        self.cooldown_seconds = cooldown_seconds
        self.last_sent_at = 0.0

    @property
    def enabled(self) -> bool:
        return self.config.enabled

    def send(self, message: str) -> None:
        if not self.enabled:
            return

        if time.time() - self.last_sent_at < self.cooldown_seconds:
            return

        try:
            mail = MIMEText(message)
            mail["Subject"] = "ALERTE Drive Safe"
            mail["From"] = f"Drive Safe <{self.config.sender}>"
            mail["To"] = self.config.recipient

            with smtplib.SMTP_SSL("smtp.gmail.com", 465) as smtp:
                smtp.login(self.config.sender, self.config.password)
                smtp.send_message(mail)

            self.last_sent_at = time.time()
            print(f"Email sent: {message}")
        except Exception as exc:
            print(f"Email error: {exc}")
