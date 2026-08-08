# giữ luật chuyển trạng thái để khớp backend

ALLOWED_TRANSITIONS = {
    "uploaded": {"processing"},
    "processing": {"completed", "failed"}
}

def is_valid_transition(current_status: str, next_status: str) -> bool:
    return next_status in ALLOWED_TRANSITIONS.get(current_status, set())