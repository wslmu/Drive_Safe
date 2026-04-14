from __future__ import annotations

import csv
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


@dataclass
class AlertLogger:
    log_dir: Path

    def __post_init__(self) -> None:
        self.log_dir.mkdir(parents=True, exist_ok=True)
        filename = f"session_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
        self.log_file = self.log_dir / filename
        with self.log_file.open("w", newline="", encoding="utf-8") as file:
            writer = csv.writer(file)
            writer.writerow(
                ["Horodatage", "Type_Alerte", "EAR", "MAR", "Angle", "Duree_s"]
            )

    def log_alert(
        self, alert_type: str, ear: float, mar: float, angle: float, duration: float
    ) -> None:
        with self.log_file.open("a", newline="", encoding="utf-8") as file:
            writer = csv.writer(file)
            writer.writerow(
                [
                    datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                    alert_type,
                    f"{ear:.3f}",
                    f"{mar:.3f}",
                    f"{angle:.1f}",
                    f"{duration:.1f}",
                ]
            )
