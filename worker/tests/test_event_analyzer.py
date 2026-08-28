# Mục đích: Unit test cho temporal event analyzer

import pytest
from worker.src.event_analyzer import (
    AnalyzerConfig,
    EventAnalyzer,
    FrameSnapshot,
)


def _make_frame(
    frame_index: int,
    timestamp_sec: float,
    motion_score: float = 0.0,
    has_ball: bool = False,
    ball_confidence: float = 0.0,
    ball_field_x: float | None = None,
    ball_field_y: float | None = None,
    player_count: int = 0,
    player_field_positions: list[tuple[float, float]] | None = None,
) -> FrameSnapshot:
    return FrameSnapshot(
        frame_index=frame_index,
        timestamp_sec=timestamp_sec,
        motion_score=motion_score,
        has_ball=has_ball,
        ball_confidence=ball_confidence,
        ball_pixel_x=None,
        ball_pixel_y=None,
        ball_field_x=ball_field_x,
        ball_field_y=ball_field_y,
        player_count=player_count,
        player_field_positions=player_field_positions or [],
        track_ids=set(),
    )


def test_empty_frames_returns_no_events():
    analyzer = EventAnalyzer()
    assert analyzer.analyze([], "match-1") == []


def test_low_motion_no_events():
    """Video phẳng, ít chuyển động → không emit event."""
    frames = [
        _make_frame(i, i / 25.0, motion_score=1.0)
        for i in range(100)
    ]
    analyzer = EventAnalyzer()
    result = analyzer.analyze(frames, "match-1")
    assert len(result) == 0


def test_high_motion_with_ball_emits_event():
    """Motion cao + ball visible → emit ít nhất 1 event."""
    frames = [
        _make_frame(
            i,
            i / 25.0,
            motion_score=25.0,
            has_ball=True,
            ball_confidence=0.8,
            ball_field_x=50.0,
            ball_field_y=50.0,
            player_count=5,
            player_field_positions=[
                (45.0, 40.0), (55.0, 60.0), (48.0, 52.0),
                (52.0, 48.0), (47.0, 55.0),
            ],
        )
        for i in range(100)
    ]
    analyzer = EventAnalyzer(AnalyzerConfig(window_size=10))
    result = analyzer.analyze(frames, "match-1")
    assert len(result) >= 1


def test_goal_detection_near_goal_zone():
    """Ball trong goal zone + nhiều player + motion cao → classify 'goal'."""
    frames = [
        _make_frame(
            i,
            i / 25.0,
            motion_score=25.0,
            has_ball=True,
            ball_confidence=0.9,
            ball_field_x=5.0,
            ball_field_y=50.0,
            player_count=8,
            player_field_positions=[
                (3.0, 45.0), (7.0, 55.0), (10.0, 48.0),
                (5.0, 52.0), (8.0, 50.0), (2.0, 47.0),
                (12.0, 53.0), (6.0, 49.0),
            ],
        )
        for i in range(100)
    ]
    analyzer = EventAnalyzer(AnalyzerConfig(window_size=10))
    result = analyzer.analyze(frames, "match-1")
    assert any(c.event_type == "goal" for c in result)


def test_cooldown_prevents_duplicate():
    """2 peak gần nhau (< cooldown) → chỉ emit 1."""
    frames = []
    for i in range(200):
        ts = i / 25.0
        # 2 burst tại frame 48-55 và 58-65 (cách nhau 0.4s < 12s cooldown)
        motion = 25.0 if (48 <= i <= 55 or 58 <= i <= 65) else 1.0
        frames.append(
            _make_frame(
                i,
                ts,
                motion_score=motion,
                has_ball=motion > 5,
                ball_confidence=0.8 if motion > 5 else 0.0,
                ball_field_x=50.0 if motion > 5 else None,
                ball_field_y=50.0 if motion > 5 else None,
                player_count=5 if motion > 5 else 0,
            )
        )
    analyzer = EventAnalyzer(AnalyzerConfig(window_size=5, cooldown_sec=12.0))
    result = analyzer.analyze(frames, "match-1")
    # 2 peaks cách nhau 0.4s, cooldown 12s → chỉ 1 event
    assert len(result) == 1


def test_corner_kick_detection():
    """Ball trong corner zone → classify 'corner_kick'."""
    frames = [
        _make_frame(
            i,
            i / 25.0,
            motion_score=12.0,
            has_ball=True,
            ball_confidence=0.7,
            ball_field_x=5.0,
            ball_field_y=5.0,
            player_count=3,
            player_field_positions=[(3.0, 3.0), (7.0, 7.0), (10.0, 10.0)],
        )
        for i in range(100)
    ]
    analyzer = EventAnalyzer(AnalyzerConfig(window_size=10))
    result = analyzer.analyze(frames, "match-1")
    assert any(c.event_type == "corner_kick" for c in result)