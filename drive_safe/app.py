from __future__ import annotations

import time
from dataclasses import dataclass, field

import customtkinter as ctk
import cv2
import mediapipe as mp
from PIL import Image, ImageTk

from drive_safe.alerting import AlarmPlayer, EmailNotifier
from drive_safe.logging_utils import AlertLogger
from drive_safe.metrics import (
    LEFT_EYE,
    MOUTH,
    RIGHT_EYE,
    calculate_ear,
    calculate_fatigue_score,
    calculate_forward_drop,
    calculate_head_angle,
    calculate_mar,
)
from drive_safe.settings import Settings, load_settings

ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")

APP_BG = "#09111a"
SURFACE = "#0f1b2b"
SURFACE_2 = "#132338"
CARD = "#17283d"
CARD_ALT = "#1c3047"
BORDER = "#27415d"
TEXT = "#eef4fb"
MUTED = "#8ca0b7"
GREEN = "#42c983"
AMBER = "#f0b24d"
RED = "#ff6b78"
BLUE = "#55a8ff"
CYAN = "#56e0d2"


@dataclass
class DetectionState:
    eyes_started_at: float | None = None
    mouth_started_at: float | None = None
    head_started_at: float | None = None
    forward_started_at: float | None = None
    session_started_at: float = field(default_factory=time.time)
    blink_window_started_at: float = field(default_factory=time.time)
    calibration_started_at: float = field(default_factory=time.time)
    blink_counter: int = 0
    blinks_per_minute: int = 0
    previous_eye_open: bool = True
    alert_count: int = 0
    fatigue_score: int = 0
    max_fatigue_score: int = 0
    average_fatigue_sum: float = 0.0
    processed_frames: int = 0
    ear_history: list[float] = field(default_factory=list)
    eyes_alert_sent: bool = False
    mouth_alert_sent: bool = False
    head_alert_sent: bool = False
    forward_alert_sent: bool = False
    calibration_complete: bool = False
    baseline_ear_sum: float = 0.0
    baseline_mar_sum: float = 0.0
    baseline_samples: int = 0
    baseline_ear: float = 0.28
    baseline_mar: float = 0.12
    last_status_text: str = "Calibration en cours"
    dominant_alert: str = "Aucune"


def detection_quality(face_detected: bool, brightness_score: int) -> tuple[str, str]:
    if not face_detected:
        return "Visage non detecte", RED
    if brightness_score < 35:
        return "Lumiere faible", AMBER
    if brightness_score > 92:
        return "Image surexposee", AMBER
    return "Detection stable", GREEN


def vigilance_level(score: int) -> tuple[str, str]:
    if score < 30:
        return "Vigilance elevee", GREEN
    if score < 60:
        return "Vigilance moderee", AMBER
    return "Vigilance critique", RED


def fatigue_recommendation(score: int, alert_count: int) -> str:
    if score >= 70 or alert_count >= 5:
        return "Pause immediate recommandee. Arretez-vous au plus vite pour recuperer."
    if score >= 40 or alert_count >= 2:
        return "Fatigue moderee detectee. Planifiez une pause dans les prochaines minutes."
    return "Etat global stable. Continuez a surveiller les signes de fatigue."


def format_duration(seconds: int) -> str:
    return f"{seconds // 60:02d}:{seconds % 60:02d}"


def compute_thresholds(settings: Settings, state: DetectionState) -> tuple[float, float]:
    if not state.calibration_complete:
        return settings.eye_threshold, settings.mouth_threshold
    calibrated_eye = min(settings.eye_threshold, state.baseline_ear * 0.72)
    calibrated_mouth = max(settings.mouth_threshold, state.baseline_mar * 2.2)
    return calibrated_eye, calibrated_mouth


def trigger_alert(
    *,
    should_alert: bool,
    already_sent: bool,
    alert_type: str,
    message: str,
    duration: float,
    ear: float,
    mar: float,
    angle: float,
    logger: AlertLogger,
    alarm: AlarmPlayer,
    notifier: EmailNotifier,
    state: DetectionState,
) -> None:
    if not should_alert or already_sent:
        return
    state.alert_count += 1
    state.dominant_alert = alert_type
    logger.log_alert(alert_type, ear, mar, angle, duration)
    alarm.start()
    notifier.send(message)


def clear_alarm_if_safe(alarm: AlarmPlayer, eye_alert: bool, mouth_alert: bool, head_alert: bool, forward_alert: bool) -> None:
    if not any([eye_alert, mouth_alert, head_alert, forward_alert]):
        alarm.stop()


class MetricCard(ctk.CTkFrame):
    def __init__(self, parent, title: str) -> None:
        super().__init__(parent, fg_color=CARD, corner_radius=18, border_color=BORDER, border_width=1)
        self.grid_propagate(False)
        self.title = ctk.CTkLabel(self, text=title, text_color=MUTED, font=ctk.CTkFont(size=12, weight="bold"))
        self.title.pack(anchor="w", padx=16, pady=(14, 4))
        self.value = ctk.CTkLabel(self, text="--", text_color=TEXT, font=ctk.CTkFont(size=20, weight="bold"))
        self.value.pack(anchor="w", padx=16, pady=(0, 14))

    def update_value(self, value: str, color: str) -> None:
        self.value.configure(text=value, text_color=color)


class DriveSafeDesktopApp:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.logger = AlertLogger(settings.log_dir)
        self.alarm = AlarmPlayer(settings.alarm_file)
        self.notifier = EmailNotifier(settings.email, settings.email_cooldown_seconds)
        self.state = DetectionState()
        self.running = True
        self.video_image = None

        self.mp_face = mp.solutions.face_mesh
        self.detector = self.mp_face.FaceMesh(
            max_num_faces=1,
            refine_landmarks=True,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        self.camera = cv2.VideoCapture(settings.camera_index)
        if not self.camera.isOpened():
            raise RuntimeError("Unable to open camera 0.")

        self.root = ctk.CTk()
        self.root.title("Drive Safe")
        self.root.geometry("1520x900")
        self.root.minsize(1320, 820)
        self.root.configure(fg_color=APP_BG)
        self.root.protocol("WM_DELETE_WINDOW", self.stop)

        self._build_layout()

    def _build_layout(self) -> None:
        shell = ctk.CTkFrame(self.root, fg_color=APP_BG)
        shell.pack(fill="both", expand=True, padx=20, pady=20)
        shell.grid_columnconfigure(0, weight=1)
        shell.grid_rowconfigure(1, weight=1)

        header = ctk.CTkFrame(shell, fg_color=APP_BG)
        header.grid(row=0, column=0, sticky="ew", pady=(0, 16))
        header.grid_columnconfigure(0, weight=1)
        header.grid_columnconfigure(1, weight=0)

        left = ctk.CTkFrame(header, fg_color=APP_BG)
        left.grid(row=0, column=0, sticky="w")
        ctk.CTkLabel(left, text="Drive Safe", text_color=TEXT, font=ctk.CTkFont(size=32, weight="bold")).pack(anchor="w")
        ctk.CTkLabel(
            left,
            text="Assistant de vigilance en temps reel • Edge AI • Privacy-first",
            text_color=MUTED,
            font=ctk.CTkFont(size=14),
        ).pack(anchor="w", pady=(4, 0))

        pill = ctk.CTkFrame(header, fg_color=SURFACE, corner_radius=20, border_color=BORDER, border_width=1)
        pill.grid(row=0, column=1, sticky="e")
        ctk.CTkLabel(
            pill,
            text="Aucune video stockee • Traitement local",
            text_color=CYAN,
            font=ctk.CTkFont(size=12, weight="bold"),
        ).pack(padx=16, pady=10)

        body = ctk.CTkFrame(shell, fg_color=APP_BG)
        body.grid(row=1, column=0, sticky="nsew")
        body.grid_columnconfigure(0, weight=7)
        body.grid_columnconfigure(1, weight=5)
        body.grid_rowconfigure(0, weight=1)

        video_wrap = ctk.CTkFrame(body, fg_color=SURFACE, corner_radius=26, border_color=BORDER, border_width=1)
        video_wrap.grid(row=0, column=0, sticky="nsew", padx=(0, 14))
        video_wrap.grid_rowconfigure(1, weight=1)
        video_wrap.grid_columnconfigure(0, weight=1)

        video_head = ctk.CTkFrame(video_wrap, fg_color="transparent")
        video_head.grid(row=0, column=0, sticky="ew", padx=18, pady=(18, 12))
        video_head.grid_columnconfigure(0, weight=1)
        ctk.CTkLabel(video_head, text="Live Monitor", text_color=TEXT, font=ctk.CTkFont(size=20, weight="bold")).grid(row=0, column=0, sticky="w")
        self.live_badge = ctk.CTkLabel(
            video_head,
            text="SESSION ACTIVE",
            text_color=TEXT,
            fg_color=GREEN,
            corner_radius=14,
            font=ctk.CTkFont(size=11, weight="bold"),
            padx=12,
            pady=6,
        )
        self.live_badge.grid(row=0, column=1, sticky="e")

        self.video_label = ctk.CTkLabel(video_wrap, text="", fg_color="#061019", corner_radius=22)
        self.video_label.grid(row=1, column=0, sticky="nsew", padx=18, pady=(0, 18))

        dashboard = ctk.CTkFrame(body, fg_color=SURFACE, corner_radius=26, border_color=BORDER, border_width=1)
        dashboard.grid(row=0, column=1, sticky="nsew")
        dashboard.grid_rowconfigure(3, weight=1)
        dashboard.grid_columnconfigure(0, weight=1)

        ctk.CTkLabel(dashboard, text="Dashboard", text_color=TEXT, font=ctk.CTkFont(size=20, weight="bold")).grid(row=0, column=0, sticky="w", padx=18, pady=(18, 2))
        ctk.CTkLabel(
            dashboard,
            text="Indicateurs de vigilance, qualite de detection et recommandations temps reel.",
            text_color=MUTED,
            font=ctk.CTkFont(size=12),
        ).grid(row=1, column=0, sticky="w", padx=18, pady=(0, 12))

        hero = ctk.CTkFrame(dashboard, fg_color=CARD_ALT, corner_radius=22, border_color=BORDER, border_width=1)
        hero.grid(row=2, column=0, sticky="ew", padx=18, pady=(0, 14))
        hero.grid_columnconfigure(0, weight=1)
        ctk.CTkLabel(hero, text="Vigilance Score", text_color=MUTED, font=ctk.CTkFont(size=12, weight="bold")).grid(row=0, column=0, sticky="w", padx=18, pady=(14, 2))
        self.hero_value = ctk.CTkLabel(hero, text="100%", text_color=TEXT, font=ctk.CTkFont(size=34, weight="bold"))
        self.hero_value.grid(row=1, column=0, sticky="w", padx=18)
        self.hero_state = ctk.CTkLabel(hero, text="Calibration en cours", text_color=MUTED, font=ctk.CTkFont(size=13))
        self.hero_state.grid(row=2, column=0, sticky="w", padx=18, pady=(0, 10))
        self.progress = ctk.CTkProgressBar(hero, progress_color=GREEN, fg_color="#2a3d55", height=16, corner_radius=100)
        self.progress.grid(row=3, column=0, sticky="ew", padx=18, pady=(0, 18))
        self.progress.set(1)

        grid = ctk.CTkFrame(dashboard, fg_color="transparent")
        grid.grid(row=3, column=0, sticky="nsew", padx=10)
        for col in range(2):
            grid.grid_columnconfigure(col, weight=1)

        self.card_level = MetricCard(grid, "Etat")
        self.card_quality = MetricCard(grid, "Detection")
        self.card_eyes = MetricCard(grid, "Yeux")
        self.card_mouth = MetricCard(grid, "Bouche")
        self.card_head = MetricCard(grid, "Tete")
        self.card_light = MetricCard(grid, "Lumiere")
        self.card_session = MetricCard(grid, "Session")
        self.card_alerts = MetricCard(grid, "Alertes")
        self.card_blinks = MetricCard(grid, "Clin/min")
        self.card_mode = MetricCard(grid, "Mode")
        cards = [
            self.card_level,
            self.card_quality,
            self.card_eyes,
            self.card_mouth,
            self.card_head,
            self.card_light,
            self.card_session,
            self.card_alerts,
            self.card_blinks,
            self.card_mode,
        ]
        for idx, card in enumerate(cards):
            r, c = divmod(idx, 2)
            card.grid(row=r, column=c, sticky="ew", padx=8, pady=8)
            card.configure(height=96)

        footer = ctk.CTkFrame(dashboard, fg_color="transparent")
        footer.grid(row=4, column=0, sticky="ew", padx=18, pady=(8, 18))
        footer.grid_columnconfigure(0, weight=1)

        self.status_box = ctk.CTkFrame(footer, fg_color=CARD, corner_radius=20, border_color=BORDER, border_width=1)
        self.status_box.grid(row=0, column=0, sticky="ew")
        ctk.CTkLabel(self.status_box, text="Statut session", text_color=MUTED, font=ctk.CTkFont(size=12, weight="bold")).pack(anchor="w", padx=16, pady=(14, 4))
        self.status_label = ctk.CTkLabel(self.status_box, text="Calibration en cours", text_color=TEXT, font=ctk.CTkFont(size=18, weight="bold"))
        self.status_label.pack(anchor="w", padx=16)
        self.reco_label = ctk.CTkLabel(
            self.status_box,
            text="Positionnez-vous face a la camera pendant la calibration.",
            text_color=MUTED,
            wraplength=420,
            justify="left",
            font=ctk.CTkFont(size=12),
        )
        self.reco_label.pack(anchor="w", padx=16, pady=(6, 14))

        actions = ctk.CTkFrame(footer, fg_color="transparent")
        actions.grid(row=1, column=0, sticky="ew", pady=(14, 0))
        actions.grid_columnconfigure(0, weight=1)
        ctk.CTkLabel(actions, text="Privacy by design • Edge AI • Aucune biometrie stockee", text_color=CYAN, font=ctk.CTkFont(size=12, weight="bold")).grid(row=0, column=0, sticky="w")
        self.stop_button = ctk.CTkButton(
            actions,
            text="Arreter la session",
            command=self.stop,
            fg_color=RED,
            hover_color="#e45b68",
            text_color=TEXT,
            corner_radius=16,
            height=42,
            width=170,
            font=ctk.CTkFont(size=13, weight="bold"),
        )
        self.stop_button.grid(row=0, column=1, sticky="e")

    def stop(self) -> None:
        self.running = False

    def render_frame(self, frame_bgr) -> None:
        display = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        image = Image.fromarray(display)
        max_w = max(760, self.video_label.winfo_width() or 760)
        max_h = max(560, self.video_label.winfo_height() or 560)
        image.thumbnail((max_w, max_h))
        self.video_image = ImageTk.PhotoImage(image=image)
        self.video_label.configure(image=self.video_image)

    def update_dashboard(self, brightness_score: int, face_detected: bool, values: dict[str, str]) -> None:
        level_text, level_color = vigilance_level(self.state.fatigue_score)
        quality_text, quality_color = detection_quality(face_detected, brightness_score)
        recommendation = fatigue_recommendation(self.state.max_fatigue_score, self.state.alert_count)

        vigilance_percent = max(0, 100 - self.state.fatigue_score)
        self.hero_value.configure(text=f"{vigilance_percent}%")
        self.hero_state.configure(text=level_text, text_color=level_color)
        self.progress.configure(progress_color=level_color)
        self.progress.set(vigilance_percent / 100)
        self.live_badge.configure(fg_color=RED if self.alarm.active else GREEN, text="ALERTE ACTIVE" if self.alarm.active else "SESSION ACTIVE")

        self.card_level.update_value(level_text, level_color)
        self.card_quality.update_value(quality_text, quality_color)
        self.card_eyes.update_value(values["eyes"], BLUE if values["eyes"] == "Ouverts" else RED)
        self.card_mouth.update_value(values["mouth"], BLUE if values["mouth"] == "Fermee" else AMBER)
        self.card_head.update_value(values["head"], BLUE if values["head"] == "Droite" else AMBER)
        self.card_light.update_value(f"{brightness_score}%", GREEN if brightness_score >= 35 else AMBER)
        self.card_session.update_value(format_duration(int(time.time() - self.state.session_started_at)), TEXT)
        self.card_alerts.update_value(str(self.state.alert_count), RED if self.state.alert_count else TEXT)
        self.card_blinks.update_value(str(self.state.blinks_per_minute), TEXT)
        self.card_mode.update_value("Edge AI", CYAN)
        self.status_label.configure(text=self.state.last_status_text, text_color=RED if self.alarm.active else TEXT)
        self.reco_label.configure(text=recommendation)

    def process_frame(self, image):
        image = cv2.flip(image, 1)
        overlay = image.copy()
        brightness_score = int(min(100, max(0, image.mean() / 255 * 100)))
        values = {"eyes": "Ouverts", "mouth": "Fermee", "head": "Droite"}
        face_detected = False
        ear = 0.30
        mar = 0.0
        angle = 0.0
        forward_drop = 0.0
        eye_alert = False
        mouth_alert = False
        head_alert = False
        forward_alert = False

        rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        results = self.detector.process(rgb_image)

        if results.multi_face_landmarks:
            face_detected = True
            points = results.multi_face_landmarks[0].landmark
            left_ear = calculate_ear(points, LEFT_EYE)
            right_ear = calculate_ear(points, RIGHT_EYE)
            ear = (left_ear + right_ear) / 2.0
            mar = calculate_mar(points, MOUTH)
            angle = calculate_head_angle(points)
            forward_drop = calculate_forward_drop(points)

            if not self.state.calibration_complete:
                self.state.baseline_ear_sum += ear
                self.state.baseline_mar_sum += mar
                self.state.baseline_samples += 1
                calibration_elapsed = time.time() - self.state.calibration_started_at
                remaining = max(0, int(self.settings.calibration_seconds - calibration_elapsed))
                self.state.last_status_text = f"Calibration en cours ({remaining}s)"
                if calibration_elapsed >= self.settings.calibration_seconds and self.state.baseline_samples:
                    self.state.baseline_ear = self.state.baseline_ear_sum / self.state.baseline_samples
                    self.state.baseline_mar = self.state.baseline_mar_sum / self.state.baseline_samples
                    self.state.calibration_complete = True
                    self.state.last_status_text = "Calibration terminee. Surveillance active."

            eye_threshold, mouth_threshold = compute_thresholds(self.settings, self.state)

            self.state.ear_history.append(ear)
            if len(self.state.ear_history) > self.settings.ear_graph_max_points:
                self.state.ear_history.pop(0)

            eye_open = ear >= eye_threshold
            if not eye_open and self.state.previous_eye_open:
                self.state.blink_counter += 1
            self.state.previous_eye_open = eye_open

            elapsed = time.time() - self.state.blink_window_started_at
            if elapsed >= 10:
                self.state.blinks_per_minute = int(self.state.blink_counter * (60 / elapsed))
                self.state.blink_counter = 0
                self.state.blink_window_started_at = time.time()

            self.state.fatigue_score = calculate_fatigue_score(
                ear,
                mar,
                angle,
                self.state.blinks_per_minute,
                forward_drop,
                eye_threshold,
                mouth_threshold,
                self.settings.head_angle_threshold,
                self.settings.blink_rate_threshold,
            )
            self.state.max_fatigue_score = max(self.state.max_fatigue_score, self.state.fatigue_score)
            self.state.average_fatigue_sum += self.state.fatigue_score
            self.state.processed_frames += 1

            if self.state.calibration_complete:
                level_text, _ = vigilance_level(self.state.fatigue_score)
                self.state.last_status_text = level_text

                if ear < eye_threshold:
                    if self.state.eyes_started_at is None:
                        self.state.eyes_started_at = time.time()
                    eye_duration = time.time() - self.state.eyes_started_at
                    values["eyes"] = f"Fermes {eye_duration:.1f}s"
                    eye_alert = eye_duration >= self.settings.eyes_time_threshold
                    trigger_alert(
                        should_alert=eye_alert,
                        already_sent=self.state.eyes_alert_sent,
                        alert_type="YEUX_FERMES",
                        message="Alerte Drive Safe : yeux fermes depuis trop longtemps.",
                        duration=eye_duration,
                        ear=ear,
                        mar=mar,
                        angle=angle,
                        logger=self.logger,
                        alarm=self.alarm,
                        notifier=self.notifier,
                        state=self.state,
                    )
                    if eye_alert:
                        self.state.eyes_alert_sent = True
                        self.state.last_status_text = "Risque critique : yeux fermes"
                else:
                    self.state.eyes_started_at = None
                    self.state.eyes_alert_sent = False

                if mar > mouth_threshold:
                    if self.state.mouth_started_at is None:
                        self.state.mouth_started_at = time.time()
                    mouth_duration = time.time() - self.state.mouth_started_at
                    values["mouth"] = f"Ouverte {mouth_duration:.1f}s"
                    mouth_alert = mouth_duration >= self.settings.mouth_time_threshold
                    trigger_alert(
                        should_alert=mouth_alert,
                        already_sent=self.state.mouth_alert_sent,
                        alert_type="BAILLEMENT",
                        message="Alerte Drive Safe : baillement detecte, fatigue probable.",
                        duration=mouth_duration,
                        ear=ear,
                        mar=mar,
                        angle=angle,
                        logger=self.logger,
                        alarm=self.alarm,
                        notifier=self.notifier,
                        state=self.state,
                    )
                    if mouth_alert:
                        self.state.mouth_alert_sent = True
                        self.state.last_status_text = "Signe de fatigue : baillement prolonge"
                else:
                    self.state.mouth_started_at = None
                    self.state.mouth_alert_sent = False

                if abs(angle) > self.settings.head_angle_threshold:
                    if self.state.head_started_at is None:
                        self.state.head_started_at = time.time()
                    head_duration = time.time() - self.state.head_started_at
                    values["head"] = f"Penchee {'Gauche' if angle > 0 else 'Droite'}"
                    head_alert = head_duration >= self.settings.head_time_threshold
                    trigger_alert(
                        should_alert=head_alert,
                        already_sent=self.state.head_alert_sent,
                        alert_type="TETE_PENCHEE",
                        message="Alerte Drive Safe : tete inclinee, risque de somnolence.",
                        duration=head_duration,
                        ear=ear,
                        mar=mar,
                        angle=angle,
                        logger=self.logger,
                        alarm=self.alarm,
                        notifier=self.notifier,
                        state=self.state,
                    )
                    if head_alert:
                        self.state.head_alert_sent = True
                        self.state.last_status_text = "Posture a risque detectee"
                else:
                    self.state.head_started_at = None
                    self.state.head_alert_sent = False

                if forward_drop > self.settings.forward_drop_threshold:
                    if self.state.forward_started_at is None:
                        self.state.forward_started_at = time.time()
                    forward_duration = time.time() - self.state.forward_started_at
                    forward_alert = forward_duration >= self.settings.forward_time_threshold
                    trigger_alert(
                        should_alert=forward_alert,
                        already_sent=self.state.forward_alert_sent,
                        alert_type="TETE_AVANT",
                        message="Alerte Drive Safe : tete projetee vers l'avant.",
                        duration=forward_duration,
                        ear=ear,
                        mar=mar,
                        angle=angle,
                        logger=self.logger,
                        alarm=self.alarm,
                        notifier=self.notifier,
                        state=self.state,
                    )
                    if forward_alert:
                        self.state.forward_alert_sent = True
                        self.state.last_status_text = "Micro-sommeil possible"
                else:
                    self.state.forward_started_at = None
                    self.state.forward_alert_sent = False

            for landmark in points[0:468:24]:
                px = int(landmark.x * overlay.shape[1])
                py = int(landmark.y * overlay.shape[0])
                cv2.circle(overlay, (px, py), 2, (86, 224, 210), -1)
        else:
            self.state.last_status_text = "Repositionnez votre visage face a la camera"
            values = {"eyes": "Non detecte", "mouth": "Non detecte", "head": "Non detecte"}

        self.update_dashboard(brightness_score, face_detected, values)
        clear_alarm_if_safe(self.alarm, eye_alert, mouth_alert, head_alert, forward_alert)
        return overlay

    def loop(self) -> None:
        if not self.running:
            self.root.quit()
            return
        ok, image = self.camera.read()
        if ok:
            processed = self.process_frame(image)
            self.render_frame(processed)
        self.root.after(20, self.loop)

    def show_summary(self) -> None:
        avg_score = int(self.state.average_fatigue_sum / max(1, self.state.processed_frames))
        recommendation = fatigue_recommendation(self.state.max_fatigue_score, self.state.alert_count)
        level_text, level_color = vigilance_level(self.state.max_fatigue_score)

        summary = ctk.CTkToplevel(self.root)
        summary.title("Drive Safe - Resume")
        summary.geometry("840x580")
        summary.configure(fg_color=APP_BG)
        summary.transient(self.root)
        summary.grab_set()

        container = ctk.CTkFrame(summary, fg_color=SURFACE, corner_radius=24, border_color=BORDER, border_width=1)
        container.pack(fill="both", expand=True, padx=22, pady=22)
        ctk.CTkLabel(container, text="Resume de session", text_color=TEXT, font=ctk.CTkFont(size=28, weight="bold")).pack(anchor="w", padx=24, pady=(24, 4))
        ctk.CTkLabel(container, text="Synthese de vigilance et recommandation finale", text_color=MUTED, font=ctk.CTkFont(size=13)).pack(anchor="w", padx=24, pady=(0, 18))

        stats = ctk.CTkFrame(container, fg_color="transparent")
        stats.pack(fill="x", padx=16)
        for col in range(2):
            stats.grid_columnconfigure(col, weight=1)
        items = [
            ("Duree", format_duration(int(time.time() - self.state.session_started_at)), TEXT),
            ("Alertes", str(self.state.alert_count), RED if self.state.alert_count else TEXT),
            ("Niveau max", level_text, level_color),
            ("Score moyen", f"{avg_score}%", BLUE),
            ("Score max", f"{self.state.max_fatigue_score}%", level_color),
            ("Evenement dominant", self.state.dominant_alert, AMBER if self.state.dominant_alert != "Aucune" else TEXT),
        ]
        for idx, (title, value, color) in enumerate(items):
            card = MetricCard(stats, title)
            card.grid(row=idx // 2, column=idx % 2, sticky="ew", padx=8, pady=8)
            card.configure(height=96)
            card.update_value(value, color)

        advice = ctk.CTkFrame(container, fg_color=CARD_ALT, corner_radius=20, border_color=BORDER, border_width=1)
        advice.pack(fill="x", padx=24, pady=(18, 0))
        ctk.CTkLabel(advice, text="Recommendation", text_color=TEXT, font=ctk.CTkFont(size=16, weight="bold")).pack(anchor="w", padx=16, pady=(14, 4))
        ctk.CTkLabel(advice, text=recommendation, text_color=MUTED, wraplength=720, justify="left", font=ctk.CTkFont(size=13)).pack(anchor="w", padx=16, pady=(0, 12))
        ctk.CTkLabel(advice, text=f"Log CSV : {self.logger.log_file}", text_color=CYAN, wraplength=720, justify="left", font=ctk.CTkFont(size=12)).pack(anchor="w", padx=16, pady=(0, 14))

        ctk.CTkButton(
            container,
            text="Fermer",
            command=summary.destroy,
            fg_color=BLUE,
            hover_color="#4b98e6",
            text_color=TEXT,
            corner_radius=16,
            height=42,
            width=140,
            font=ctk.CTkFont(size=13, weight="bold"),
        ).pack(anchor="e", padx=24, pady=24)

        summary.wait_window()

    def run(self) -> None:
        self.root.after(10, self.loop)
        self.root.mainloop()
        self.running = False
        duration = int(time.time() - self.state.session_started_at)
        print("\n" + "=" * 40)
        print("  SESSION TERMINEE - Drive Safe")
        print("=" * 40)
        print(f"  Duree        : {duration // 60}m {duration % 60}s")
        print(f"  Alertes      : {self.state.alert_count}")
        print(f"  Log sauvegarde : {self.logger.log_file}")
        print("=" * 40 + "\n")
        self.camera.release()
        self.alarm.close()
        self.show_summary()
        self.root.destroy()
        print("Programme arrete proprement.")


def main() -> None:
    app = DriveSafeDesktopApp(load_settings())
    app.run()
