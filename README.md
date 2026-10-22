# Personal Daily Manager

Offline Android app (Flutter): dashboard, daily tasks, budget & expenses (PKR),
udhaar (borrowed/lent with repayments), reminders, backup/restore.
No internet, no accounts. Data is stored in a local SQLite database.

## Get the APK (no coding)

1. Sign in at https://github.com and create a **new repository** (name: `personal-daily-manager`, Private is fine).
2. Click **uploading an existing file**. Unzip this project on your computer and drag
   **everything inside the folder** into the page (including the `.github` folder, `lib`, `test`, `tools`,
   `pubspec.yaml`). Click **Commit changes**.
   - If the `.github` folder did not upload: click **Add file > Create new file**, type
     `.github/workflows/build-apk.yml` as the name, paste the contents of `build-apk.yml.txt`, and commit.
3. Open the **Actions** tab. The "Build APK" run starts by itself (about 10 minutes).
   If it does not, open "Build APK" and press **Run workflow**.
4. When it shows a green check, open the run and download **PersonalDailyManager-apk** at the bottom
   (it is a zip containing `PersonalDailyManager.apk`).
5. Copy the APK to your phone, tap it, and allow "Install unknown apps" for your file manager/browser when asked.

If the build fails (red cross), open the failed step, copy the red error text and send it to Claude.

## Notes
- The first use of reminders asks for the notification permission. For exact timing also allow
  "Alarms & reminders" (More > Reminders shows a button when needed).
- Repeating reminders are scheduled ahead (30 days daily, 12 weeks weekly, 6 months monthly) and topped up
  every time the app is opened.
- Budget: a month without its own budget uses the most recent earlier one.
- Backups: More > Backup & Restore. Keep the exported file outside the phone (Drive, email, etc.).
