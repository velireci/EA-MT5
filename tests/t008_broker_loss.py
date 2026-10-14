"""Read-only profit-estimate comparison. No costs, fills or execution guarantee."""
import math
from t007_planning_reference import _risk_exceeded


def permit_risk(profit, model_loss):
    if not all(math.isfinite(x) for x in (profit, model_loss)) or profit >= 0 or model_loss <= 0:
        return 0
    return max(-profit, model_loss)


def check(calc_ok, profit, model_loss, budget, tolerance):
    if not calc_ok:
        return 'CALC_FAILED'
    if not all(math.isfinite(x) for x in (profit, model_loss, budget, tolerance)):
        return 'INVALID_INPUT'
    if model_loss <= 0 or budget <= 0 or not 0 <= tolerance <= 1:
        return 'INVALID_INPUT'
    if profit >= 0:
        return 'NOT_A_LOSS'
    loss = -profit
    if _risk_exceeded(0, loss, budget):
        return 'BUDGET_EXCEEDED'
    relative = abs(loss-model_loss)/model_loss
    if not math.isfinite(relative) or relative > tolerance + 4*2.220446049250313e-16:
        return 'MODEL_MISMATCH'
    return 'OK'
