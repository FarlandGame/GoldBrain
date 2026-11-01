from app.services.forecasting import _signal_decision


def test_provisional_forecast_fails_closed() -> None:
    signal, quality, trade_allowed, reasons = _signal_decision(
        direction="upward", confidence=90, data_quality=95, calibration_status="provisional"
    )
    assert (signal, quality, trade_allowed) == ("no_trade", "unverified", False)
    assert reasons


def test_validation_based_forecast_is_paper_only() -> None:
    signal, quality, trade_allowed, reasons = _signal_decision(
        direction="downward",
        confidence=72,
        data_quality=80,
        calibration_status="validation-based",
        validation_directional_accuracy=60,
    )
    assert (signal, quality, trade_allowed) == ("sell", "paper_only", False)
    assert "Paper Trading" in reasons[0]


def test_validation_based_forecast_fails_when_directional_accuracy_is_low() -> None:
    signal, quality, trade_allowed, reasons = _signal_decision(
        direction="upward",
        confidence=80,
        data_quality=90,
        calibration_status="validation-based",
        validation_directional_accuracy=54,
    )
    assert (signal, quality, trade_allowed) == ("no_trade", "low", False)
    assert "55%" in reasons[0]


def test_calibrated_forecast_can_pass_the_trade_gate() -> None:
    signal, quality, trade_allowed, reasons = _signal_decision(
        direction="upward", confidence=85, data_quality=90, calibration_status="calibrated"
    )
    assert (signal, quality, trade_allowed) == ("buy", "high", True)
    assert reasons
