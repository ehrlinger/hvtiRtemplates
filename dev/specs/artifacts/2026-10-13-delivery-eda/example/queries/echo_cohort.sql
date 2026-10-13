-- Echocardiograms for the cohort only: joined to the same window as patients.sql.
SELECT e.pt_id, e.echo_date, e.lvef, e.peak_gradient
FROM echo_src e
JOIN patients_src p ON p.pt_id = e.pt_id
WHERE p.surgery_date BETWEEN :start AND :end
ORDER BY e.pt_id, e.echo_date;
