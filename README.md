# EUM Student Timetable

Professional 1920x1080 student timetable display for Emerson University Multan.

## Included timetable sources

- 1st Semester — All Programmes
- Artificial Intelligence
- Computer Science
- Cyber Security
- Data Science
- Information Technology (2-Year)
- Information Technology
- MS Programmes
- Software Engineering

The supplied Fall 2026 timetable PDFs were converted into `timetable.json`.

## Automatic behavior

- Uses the Raspberry Pi system clock.
- Detects Monday-Friday automatically.
- Highlights the current class.
- Shows the next class.
- Shows JUMMAH BREAK where present in the source timetable.
- Automatically rotates through the sections.
- Continues to work offline.
- Refreshes instantly if `timetable.json` is replaced by a package service or another local process.

## Important

This package contains the timetable data extracted from the supplied Fall 2026 PDFs. When a new semester timetable is issued, regenerate/replace `timetable.json` with the new official timetable data and publish the updated package.
