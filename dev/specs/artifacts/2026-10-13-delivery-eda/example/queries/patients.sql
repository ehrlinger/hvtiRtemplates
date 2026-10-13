-- Cohort: operations in the request window.
SELECT pt_id, surgery_date, age, sex, bmi, creatinine, lvef_preop, nyha,
       diabetes, hospital_los, dead, iv_dead, reop, iv_reop
FROM patients_src
WHERE surgery_date BETWEEN :start AND :end
ORDER BY pt_id;
