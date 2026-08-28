# Mục đích: Temporal analysis trên chuỗi frame để phát hiện highlight events
# Tách khỏi detector.py để detector chỉ lo tracking, analyzer lo business logic highlight

from dataclasses import dataclass

@dataclass
class FrameSnapshot:
    """Dữ liệu 1 frame do detector thu thập - input cho analyzer"""
    frame_index: int
    timestamp_sec: float
    motion_score: float
    has_ball: bool
    ball_confidence: float
    ball_pixel_x: float | None
    ball_pixel_y: float | None
    ball_field_x: float | None
    ball_field_y: float | None
    player_count: int
    player_field_positions: list[tuple[float, float]]
    track_ids: set[int]

@dataclass
class EventCandidate:
    """Một highlight event đã detect được, chờ map sang clip/event item"""
    event_type: str
    peak_timestamp_sec: float
    start_sec: float
    end_sec: float
    confidence: float
    track_ids_involved: list[int]

@dataclass
class AnalyzerConfig:
    """Tuning parameters cho temporal analysis."""
    # Sliding window
    window_size: int = 30
    # Ngưỡng phát hiện
    motion_threshold: float = 8.0
    high_motion_threshold: float = 18.0
    # Cooldown giữa 2 event cùng loại (giây)
    cooldown_sec: float = 12.0
    # Clip padding (giây)
    clip_before_sec: float = 5.0
    clip_after_sec: float = 5.0
    # Vùng goal area trên field 0-100 (2 đầu sân theo chiều dài)
    goal_zone_x_min: float = 0.0
    goal_zone_x_max: float = 15.0
    goal_zone_x_min_2: float = 85.0
    goal_zone_x_max_2: float = 100.0
    # Vùng corner (4 góc sân)
    corner_zone_size: float = 15.0
    # Player density: số player tối thiểu trong goal zone để coi là "tập trung"
    goal_zone_player_threshold: int = 4

class EventAnalyzer:
    def __init__(self, config: AnalyzerConfig | None = None) ->  None:
        self.config = config or AnalyzerConfig()

    def analyze(
        self,
        frames: list[FrameSnapshot],
        match_id: str,
    ) -> list[EventCandidate]:
        """
        2-pass temporal analysis:
            Pass 1: Tính rolling score cho mỗi frame (motion + ball + density)
            Pass 2: Tìm peak windows -> classify event type -> merge overlapping
        """
        if not frames:
            return []
        
        # Pass 1: rolling scores
        scores = self._compute_rolling_scores(frames)

        # Pass 2: find event candicates from score peaks
        candicates = self._find_event_candidates(frames, scores)

        # Merge overlapping candidates
        merged = self._merge_candidates(candicates)

        return merged

    def _compute_rolling_scores(self, frames: list[FrameSnapshot]) -> list[float]:
        """
        Mỗi frame nhận 1 score tổng hợp từ:
            - motion intensity (normalized)
            - ball presence + confidence
            - player density near goal zones
        Scores càng cao -> càng có khả năng là highlight moment.
        """
        cfg = self.config
        n = len(frames)
        raw_scores: list[float] = []

        for i, f in enumerate(frames):
            # 1. Motion component (0-10)
            motion_component = min(f.motion_score / 3.0, 10.0)

            # 2. Ball component (0-5)
            ball_component = 0.0
            if f.has_ball:
                ball_component = 3.0 + min(f.ball_confidence * 2.0, 2.0)

            # 3. Goal-zone density component (0-5)
            density_component = 0.0
            if f.player_field_positions:
                players_in_goal = sum(
                    1 for px, py in f.player_field_positions
                    if self._is_in_goal_zone(px)
                )
                if players_in_goal >= cfg.goal_zone_player_threshold:
                    density_component = min(players_in_goal * 0.8, 5.0)

            raw_scores.append(motion_component + ball_component + density_component)

        # Rolling average smoothing (window_size frames)
        half_w = cfg.window_size // 2
        smoothed: list[float] = []
        for i in range(n):
            start = max(0, i - half_w)
            end = min(n, i + half_w + 1)
            window = raw_scores[start:end]
            smoothed.append(sum(window) / len(window))

        return smoothed

    def _is_in_goal_zone(self, field_x: float) -> bool:
        cfg = self.config
        return (
            cfg.goal_zone_x_min <= field_x <= cfg.goal_zone_x_max
            or cfg.goal_zone_x_min_2 <= field_x <= cfg.goal_zone_x_max_2
        )   

    def _is_in_corner_zone(self, field_x: float, field_y: float) -> bool:
        s = self.config.corner_zone_size
        corners = [
            (0.0, 0.0), (100.0, 0.0),
            (0.0, 100.0), (100.0, 100.0)
        ]
        for cx, cy in corners:
            if abs(field_x - cx) <= s and abs(field_y - cy) <= s:
                return True
        return False

    def _find_event_candidates(
        self,
        frames: list[FrameSnapshot],
        scores: list[float]
    ) -> list[EventCandidate]:
        """
        Duyệt scores, tìm peak moments vượt ngưỡng -> classify event type.
        Dùng cooldown để tránh duplicate sát nhau.
        """
        cfg = self.config
        candidates: list[EventCandidate] = []
        last_event_sec: dict[str, float] = {}
        min_score = cfg.motion_threshold

        for i, (frame, score) in enumerate(zip(frames, scores)):
            if score < min_score:
                continue

            ts = frame.timestamp_sec

            # Classify dựa trên context tại peak frame
            event_type = self._classify_event(frame, frames, i, score)

            # Cooldown check per event_type
            last_sec = last_event_sec.get(event_type, -9999.0)
            if ts - last_sec < cfg.cooldown_sec:
                continue
        
            # Clip boundaries - mở rộng dựa trên context
            start_sec = max(0.0, ts - cfg.clip_before_sec)
            end_sec = ts + cfg.clip_after_sec

            # Confidence: score normalized về 0-1
            confidence = min(1.0, score / 20.0)

            candidates.append(
                EventCandidate(
                    event_type=event_type,
                    peak_timestamp_sec=ts,
                    start_sec=start_sec,
                    end_sec=end_sec,
                    confidence=round(confidence, 3),
                    track_ids_involved=sorted(frame.track_ids)
                )
            )

            last_event_sec[event_type] = ts

        return candidates

    def _classify_event(
        self,
        current_frame: FrameSnapshot,
        all_frames: list[FrameSnapshot],
        frame_index: int,
        score: float,
    ) -> str:
        """
        Phân loại event dựa trên nhiều signals tại frame peak + context window:

        Logic (ưu tiên từ trên xuống thấp):
        1. goal: motion rất cao + ball trong goal zone + nhiều player tập trung
        2. shot: ball confidence cao + motion cao + ball gần goal zone
        3. corner_kick: ball trong corner zone + player tập trung ở corner
        4. fast_break: motion cao + ball di chuyển nhanh theo chiều dọc sân + ít player phía trước
        5. foul: fallback - motion spike nhưng không match pattern trên
        """
        cfg = self.config
        f = current_frame

        # Tín hiệu: ball có trong goal zone không ?
        ball_in_goal_zone = False
        if f.ball_field_x is not None:
            ball_in_goal_zone = self._is_in_goal_zone(f.ball_field_x)

        # Tín hiệu: ball có trong corner zone không ?
        ball_in_corner =  False
        if f.ball_field_x is not None and f.ball_field_y is not None:
            ball_in_corner = self._is_in_corner_zone(f.ball_field_x, f.ball_field_y)

        # Tín hiệu: số player trong goal zone
        players_in_goal = 0
        if f.player_field_positions:
            players_in_goal = sum(
                1 for px, _ in f.player_field_positions
                if self._is_in_goal_zone(px)
            )

        # Tín hiệu: ball velocity (thay đổi position giữa các frame gần nhau)
        ball_speed = self._estimate_ball_speed(all_frames, frame_index)

        # Tín hiệu: player concentration (tổng player detected)
        player_concentration = f.player_count

        # ===== Classification logic ====
        # 1. GOAL: motion rất cao + ball gần goal + nhiều player tập trung
        if (
            f.motion_score >= cfg.high_motion_threshold
            and ball_in_goal_zone
            and players_in_goal >= cfg.goal_zone_player_threshold
            and f.has_ball
        ):
            return "goal"

        # 2. SHOT: ball di chuyển nhanh về phía goal + motion cao
        if (
            f.has_ball
            and f.ball_confidence >= 0.5
            and ball_speed > 5.0
            and f.motion_score >= cfg.motion_threshold
        ):
            return "shot"

        # 3. CORNER KICK: ball trong corner zone
        if ball_in_corner and f.has_ball and player_concentration >= 2:
            return "corner_kick"

        # 4. FAST BREAK: motion cao + ball di chuyển nhanh +  ít player xung quanh
        if (
            f.motion_score >= cfg.high_motion_threshold
            and ball_speed > 3.0
            and f.has_ball
            and player_concentration <= 4
        ): 
            return "fast_break"

        # 5. FOUL: fallback
        return "foul"

    def _estimate_ball_speed(
        self,
        frames: list[FrameSnapshot],
        frame_index: int,
    ) -> float:
        """
        Ước lượng tốc độ ball (fields units / giây) bằng cách so sánh
        ball position hiện tại với frame trước đó (cách ~5 frame để giảm noise)
        """
        lookback = 5
        prev_idx = max(0, frame_index - lookback)
        curr = frames[frame_index]
        prev = frames[prev_idx]

        if (
            curr.ball_field_x is None
            or curr.ball_field_y is None
            or prev.ball_field_x is None
            or prev.ball_field_y is None
        ):
            return 0.0

        dx = curr.ball_field_x - prev.ball_field_x
        dy = curr.ball_field_y - prev.ball_field_y
        distance = (dx * dx + dy * dy) ** 0.5

        dt = curr.timestamp_sec - prev.timestamp_sec
        if dt <= 0:
            return 0.0

        return distance / dt

    def _merge_candidates(self, candidates: list[EventCandidate]) -> list[EventCandidate]:
        """
        Merge các candidate trùng lặp (cùng event_type, clip overlap > 50%)
        Giữ candidate có confidence cao hơn
        """
        if not candidates:
            return []

        sorted_cands = sorted(candidates, key=lambda c: c.peak_timestamp_sec)
        merged: list[EventCandidate] = [sorted_cands[0]]

        for cand in sorted_cands[1:]:
            last = merged[-1]

            # Check overlap 
            overlap_start = max(last.start_sec, cand.start_sec)
            overlap_end = min(last.end_sec, cand.end_sec)
            overlap_duration = max(0.0, overlap_end - overlap_start)
            cand_duration = cand.end_sec - cand.start_sec

            if cand_duration > 0 and overlap_duration / cand_duration > 0.5:
                # Merge: giữ cái confidence cao hơn, mở rộng boundary
                if cand.confidence > last.confidence:
                    merged[-1] = EventCandidate(
                        event_type=cand.event_type,
                        peak_timestamp_sec=cand.peak_timestamp_sec,
                        start_sec=min(last.start_sec, cand.start_sec),
                        end_sec=max(last.end_sec, cand.end_sec),
                        confidence=cand.confidence,
                        track_ids_involved=sorted(
                            set(last.track_ids_involved) | set(cand.track_ids_involved)
                        ),
                    )
                else:
                    merged[-1] = EventCandidate(
                        event_type=last.event_type,
                        peak_timestamp_sec=last.peak_timestamp_sec,
                        start_sec=min(last.start_sec, cand.start_sec),
                        end_sec=max(last.end_sec, cand.end_sec),
                        confidence=last.confidence,
                        track_ids_involved=sorted(
                            set(last.track_ids_involved) | set(cand.track_ids_involved)
                        ),
                    )
            else:
                merged.append(cand)

        return merged