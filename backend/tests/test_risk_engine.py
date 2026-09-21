from app.services.risk_engine import compute_risk_level


def test_risk_levels_follow_configured_thresholds():
    # Uses default thresholds: watch=0.75, high=0.85, critical=0.95
    assert compute_risk_level(predicted_load_mw=500, effective_capacity_mw=1000) == "normal"
    assert compute_risk_level(predicted_load_mw=760, effective_capacity_mw=1000) == "watch"
    assert compute_risk_level(predicted_load_mw=860, effective_capacity_mw=1000) == "high"
    assert compute_risk_level(predicted_load_mw=960, effective_capacity_mw=1000) == "critical"


def test_risk_level_critical_when_capacity_is_zero():
    assert compute_risk_level(predicted_load_mw=100, effective_capacity_mw=0) == "critical"
