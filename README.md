# 🧠 SAVA — Smart Alzheimer Virtual Assistant
**[University Name] — Faculty of [Faculty Name] | Graduation Project [Academic Year]**

Team SWE13 · Mostafa Zakaria · Samer Raef · Nezar Walid · Mohamed Atef . Aml ElGedawy
Supervisors: Dr. Sarah Nabil · Eng. Fathy Farag

## Table of Contents
- [Overview](#overview)
- [Key Features](#key-features)
- [Architecture](#architecture)
- [Team](#team)

## Overview

SAVA is a real-time patient monitoring system for Alzheimer's patients that combines face recognition, person tracking, activity recognition, and alert management into a unified platform. It bridges the gap between patients, caregivers, and relatives by replacing manual check-ins with continuous, automated monitoring.

The platform uses multimodal AI analysis — combining computer vision, pose estimation, and activity recognition — to identify who is with the patient, track daily activities, and automatically generate alerts when urgent situations such as falls or chest pain are detected.

## Key Features

### For Relatives
- **Patient Management** — Create and manage patient profiles, assign caregivers, and edit medication schedules.
- **Real-Time Alerts** — Receive instant notifications for falls, chest pain, and unrecognized faces.
- **Activity History** — View a timeline of the patient's recognized daily activities.

### For Caregivers
- **Caregiver Contracts** — Accept or decline assignment offers from relatives, monitoring up to 4 patients.
- **Medication Schedules** — View and update dosage, timing, and notes for each patient.
- **Alert Acknowledgement** — Review and respond to emergency alerts in real time.

## Architecture

SAVA follows a Layerd architecture, decoupling the AI analysis pipeline (face recognition and activity recognition) from the core application layer for scalability and maintainability.

Key architectural decisions:

- Role-Based Access Control (RBAC) separates Admin, Relative, and Caregiver privileges.
- The AI pipeline is decoupled into its own service to allow independent scaling of compute-heavy analysis tasks.
- Human-in-the-loop design: AI detects activities and identifies people, while caregivers and relatives retain final response authority.

## Team

| Name | Role |
|------|------|
| Samer Raef | Team Leader |
| Mostafa Zakaria | Team Member |
| Mohamed Atef | Team Member |
| Nezar Walid | Team Member |
| Aml ElGedawy | Team Member |

Supervised by: Dr. Sarah Nabil · Eng. Fathi Farag 
Institution: Misr International University  — Faculty of Computer Science
Academic Year: 2025-2026

---

*SAVA — Bridging AI-powered monitoring and compassionate care for Alzheimer's patients.*
