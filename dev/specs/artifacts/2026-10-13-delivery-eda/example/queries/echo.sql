-- Echocardiograms. Note: filtered by date only, not joined to the cohort.
SELECT pt_id, echo_date, lvef, peak_gradient
FROM echo_src
WHERE echo_date >= :start
ORDER BY pt_id, echo_date;
