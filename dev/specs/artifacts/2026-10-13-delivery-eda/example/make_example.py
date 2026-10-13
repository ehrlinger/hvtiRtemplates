"""Build a synthetic SQLite source for trying the runner end to end.

Every value is simulated; nothing here comes from patient data. The source has
problems planted on purpose so each check has something to find:

  patients_src  bmi recorded in pounds for 3 patients; preoperative LVEF not
                collected before 2008; 'Unknown' NYHA codes; one negative death
                interval; two death intervals running past the close date; two
                reoperations dated after death
  echo_src      LVEF entered as a fraction for every echo in 2017; four duplicate
                echoes with conflicting LVEF; five echoes years before surgery;
                two echoes after the close date. The echo query filters by date
                rather than by cohort, so patients operated before 2000 leak in
                as orphans.

Run:  python make_example.py            (writes source.sqlite beside this file)
"""
from pathlib import Path
import sqlite3

import numpy as np
import pandas as pd

HERE = Path(__file__).resolve().parent
CLOSE = pd.Timestamp("2025-06-30")
rng = np.random.default_rng(20261013)


def patients(n: int = 1600) -> pd.DataFrame:
    start, end = pd.Timestamp("1998-01-01"), pd.Timestamp("2024-06-30")
    surg = start + pd.to_timedelta(rng.integers(0, (end - start).days, n), unit="D")
    surg = pd.Series(surg).sort_values().reset_index(drop=True)
    pot = (CLOSE - surg).dt.days / 365.25

    death = rng.exponential(1 / 0.04, n)
    lost = rng.random(n) < 0.15
    censor = np.where(lost, pot * rng.uniform(0.05, 0.9, n), pot)
    dead = (death <= censor).astype(int)
    iv_dead = np.minimum(death, censor)
    reop_t = rng.exponential(1 / 0.015, n)
    reop = (reop_t <= iv_dead).astype(int)
    iv_reop = np.minimum(reop_t, iv_dead)

    df = pd.DataFrame({
        "pt_id": [f"SYN{i:05d}" for i in range(1, n + 1)],
        "surgery_date": surg.dt.strftime("%Y-%m-%d"),
        "age": np.clip(rng.normal(64, 12, n), 18, 95).round(),
        "sex": rng.choice(["F", "M"], n, p=[0.35, 0.65]),
        "bmi": rng.normal(28.5, 5, n).round(1),
        "creatinine": np.exp(rng.normal(0, 0.3, n)).round(2),
        "lvef_preop": np.clip(rng.normal(55, 9, n), 10, 75).round(),
        "nyha": rng.choice(["I", "II", "III", "IV", "Unknown"], n, p=[.2, .35, .3, .1, .05]),
        "diabetes": rng.binomial(1, 0.3, n),
        "hospital_los": np.ceil(np.exp(rng.normal(1.8, 0.5, n))),
        "dead": dead, "iv_dead": iv_dead.round(4),
        "reop": reop, "iv_reop": iv_reop.round(4),
    })
    df.loc[surg < pd.Timestamp("2008-01-01"), "lvef_preop"] = np.nan   # not collected yet
    df.loc[[100, 700, 1300], "bmi"] = [196.4, 211.0, 188.2]            # pounds, not kg/m2
    df.loc[400, "iv_dead"] = -0.2                                      # negative interval
    for i in (500, 900):                                               # past the close date
        df.loc[i, ["dead", "iv_dead"]] = [0, round(pot[i] + 1.5, 4)]
    for i in (600, 1100):                                              # reop after death
        df.loc[i, ["dead", "iv_dead", "reop", "iv_reop"]] = [1, 2.0, 1, 3.5]
    return df


def echoes(pts: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for _, p in pts.iterrows():
        surg = pd.Timestamp(p["surgery_date"])
        end = min(float(p["iv_dead"]) if p["iv_dead"] > 0 else 0.0, (CLOSE - surg).days / 365.25)
        times = [-rng.uniform(1, 30) / 365.25]                         # preoperative echo
        t = rng.uniform(0.5, 1.5)
        while t < end:
            times.append(t)
            t += rng.uniform(1, 3)
        base_ef, base_pg = rng.normal(55, 7), max(4, rng.normal(14, 4))
        for k, t in enumerate(times):
            rows.append({
                "pt_id": p["pt_id"],
                "echo_date": (surg + pd.Timedelta(days=round(t * 365.25))).strftime("%Y-%m-%d"),
                "lvef": round(float(np.clip(base_ef - 0.3 * max(t, 0) + rng.normal(0, 2.5), 10, 80)), 1),
                "peak_gradient": round(max(2.0, base_pg + 0.4 * max(t, 0) + rng.normal(0, 1.5)), 1),
            })
    e = pd.DataFrame(rows)
    in_2017 = e["echo_date"].str.startswith("2017")
    e.loc[in_2017, "lvef"] = (e.loc[in_2017, "lvef"] / 100).round(3)  # fraction, not percent

    cohort = pts[pts["surgery_date"] >= "2000-01-01"]
    dup = e[e["pt_id"].isin(cohort["pt_id"])].sample(4, random_state=1).copy()
    dup["lvef"] = (dup["lvef"] - 22).round(1)                          # conflicting duplicate
    pre = cohort.sample(5, random_state=2)
    pre_rows = pd.DataFrame({
        "pt_id": pre["pt_id"].values,
        "echo_date": (pd.to_datetime(pre["surgery_date"]) - pd.to_timedelta(rng.integers(800, 1500, 5), unit="D")).dt.strftime("%Y-%m-%d").values,
        "lvef": rng.normal(55, 5, 5).round(1), "peak_gradient": rng.normal(12, 3, 5).round(1)})
    post = cohort.tail(2)
    post_rows = pd.DataFrame({"pt_id": post["pt_id"].values,
                              "echo_date": ["2025-08-14", "2025-09-02"],
                              "lvef": [52.0, 48.5], "peak_gradient": [15.2, 17.9]})
    return pd.concat([e, dup, pre_rows, post_rows], ignore_index=True)


def main() -> None:
    pts = patients()
    eco = echoes(pts)
    db = HERE / "source.sqlite"
    db.unlink(missing_ok=True)
    with sqlite3.connect(db) as con:
        pts.to_sql("patients_src", con, index=False)
        eco.to_sql("echo_src", con, index=False)
    print(f"{db}: {len(pts):,} patients, {len(eco):,} echoes (synthetic)")


if __name__ == "__main__":
    main()
