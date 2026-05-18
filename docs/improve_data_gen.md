# Datagen Improvements (cup-stacking)

## Context

Baseline cup-stacking datagen produced **31/50 successful episodes** (~62%) — the
scripted state machine's grasp orientation ignored per-cup yaw, failed episodes
were thrown away, and the run-time log was difficult to read. This change
addresses four targeted issues without touching upstream `leisaac` or the
recorder. See [synthetic_data_generation.md](./synthetic_data_generation.md) for
the unchanged surrounding pipeline.

## A. Per-cup grasp yaw

**What changed.** `CupStackingStateMachine` now derives the gripper's base yaw
from the **blue cup's actual world yaw** (after `_apply_episode_poses` has
written it to sim), instead of from the robot's current hand heading. A new
method
[`set_episode_base_yaw_from_object`](../packages/simulator/src/simulator/datagen/state_machine/cup_stacking.py)
reads `env.scene["blue_cup"].data.root_quat_w`, extracts yaw, and folds it into
`[-π/2, π/2]` (cups are visually 180°-symmetric, so this avoids gratuitous wrist
flips). `_gripper_down_quat_w` prefers this captured yaw when set, falling back
to the previous hand-heading behavior otherwise.

**Why.** The cup's rvec is already in `object_poses.json` and
[`object_poses_loader.py`](../packages/simulator/src/simulator/utils/object_poses_loader.py)
extracts yaw and writes the quaternion to sim — the state machine simply wasn't
reading it. When a cup was rotated significantly off-axis, the gripper
approached misaligned and toppled it.

## B. Attempt counter fix

**What changed.** [`generate.py`](../scripts/datagen/generate.py) now tracks
`attempt_count` and `success_count` separately. Each finished episode prints
exactly once as `[Attempt N] episode M/total success|fail`, and successes also
print `— K total`.

**Why.** The old log used a single `cnt` that only incremented on success, so
the same `cnt/total` ratio printed for a fail and the next success — the two
lines referred to **different physical episodes**, which was easy to misread.

## C. `--max_retries`

**What changed.** A new `--max_retries N` flag (default `2`) makes failed
episodes retry the same `object_poses` entry up to N times before advancing,
each retry applying ±5 mm uniform xy jitter via
`_apply_episode_poses(..., jitter_xy=0.005)`. Pass `--max_retries 0` to opt out
and restore the prior behavior. The recorder is in `EXPORT_SUCCEEDED_ONLY` mode
([generate.py](../scripts/datagen/generate.py)), so failed retries are **not**
written to the dataset.

**Why.** Many cup-stacking failures (e.g. cup slipping during grasp, blue cup
landing just outside the success window) are recoverable with a small
perturbation. Throwing them away is wasteful.

The end-of-episode logic was refactored: `_on_episode_done` now only decides the
outcome; the main loop owns env-reset, pose application, and the
advance-vs-retry branch via a new `_stage_episode(env, sm, pose, jitter_xy=0)`
helper.

## Bonus: last-episode flush bug

**What changed.** The main loop now calls `env.reset()` once more before `break`
when all episodes have run.

**Why.** Surfaced by the smoke test: `LeRobotRecorderManager` runs in
`EXPORT_SUCCEEDED_ONLY` mode, which only flushes a finished episode when the
*next* `env.reset()` fires `record_pre_reset → export_episodes`. The original
loop broke out as soon as the last episode succeeded, never triggering that
final reset — so a successful last episode silently never made it to the
dataset. The smoke test confirmed: before the fix, 5/5 succeeded but only 4
were written; after, 5/5 were written.

## D. Fall-detection for cup-stacking

**What changed.** Added a `task_object_names` property to
[`CupStackingStateMachine`](../packages/simulator/src/simulator/datagen/state_machine/cup_stacking.py)
returning `("blue_cup", "pink_cup")`.

**Why.** [`generate.py`](../scripts/datagen/generate.py) already wires
fall-detection (objects below `_FALL_THRESHOLD_Z = 0.0` abort the episode), but
reads `task_object_names` via `getattr(..., ())` — so for the cup-stacking task
which didn't define it, fall-detection was silently a no-op and dropped cups
wasted the rest of the phase loop. Cups rest at `object_z = 0.12`, well above
the threshold, so false-positive fall detection at the start is impossible.

## Out of scope

- **No parallelization.** The state machine's phase index (`_event`) and
  step counter (`_step_count`) remain global scalars and `num_envs=1` is the
  only supported configuration. Going wider would require both per-env phase
  tracking and modifying the upstream
  `leisaac.enhance.managers.LeRobotRecorderManager` (which hardcodes
  `env_idx = 0`) — a multi-day refactor deliberately deferred.
- **No upstream `leisaac` edits.** All changes live in `packages/simulator/`
  and `scripts/datagen/`.
- **No recorder changes** and no state-machine timing tuning
  (`_events_dt`, `_HOVER_Z_OFFSET`, …).

## Reproduce

```bash
make datagen-native DATAGEN_ARGS='--task HCIS-CupStacking-SingleArm-v0 \
    --num_envs 1 --device cuda --record \
    --use_lerobot_recorder \
    --lerobot_dataset_repo_id $HF_USER/cup-stacking-sim-v1 \
    --object_poses data/kitchen-object-poses/object_poses.json \
    --max_retries 2'
```
